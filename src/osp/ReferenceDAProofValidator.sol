// Copyright 2021-2024, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./ICustomDAProofValidator.sol";

/**
 * @title ReferenceDAProofValidator
 * @notice Reference implementation of a CustomDA proof validator
 */
contract ReferenceDAProofValidator is ICustomDAProofValidator {
    mapping(address => bool) public trustedSigners;

    constructor(
        address[] memory _trustedSigners
    ) {
        for (uint256 i = 0; i < _trustedSigners.length; i++) {
            trustedSigners[_trustedSigners[i]] = true;
        }
    }
    /**
     * @notice Validates a ReferenceDA proof and returns the preimage chunk
     * @param certHash The keccak256 hash of the certificate (from machine's proven state)
     * @param offset The offset into the preimage to read from (from machine's proven state)
     * @param proof The proof data: [certSize(8), certificate, version(1), preimageSize(8), preimageData]
     * @return preimageChunk The 32-byte chunk at the specified offset
     */

    function validateReadPreimage(
        bytes32 certHash,
        uint256 offset,
        bytes calldata proof
    ) external pure override returns (bytes memory preimageChunk) {
        // Extract certificate size from proof
        uint256 certSize;
        assembly {
            certSize := shr(192, calldataload(add(proof.offset, 0))) // Read 8 bytes
        }

        require(proof.length >= 8 + certSize, "Proof too short for certificate");
        bytes calldata certificate = proof[8:8 + certSize];

        // Verify certificate hash matches what OSP validated
        require(keccak256(certificate) == certHash, "Certificate hash mismatch");

        // Validate certificate format: [prefix(1), dataHash(32), v(1), r(32), s(32)] = 98 bytes
        // First byte must be 0x01 (CustomDA message header flag)
        require(certificate.length == 98, "Invalid certificate length");
        require(certificate[0] == 0x01, "Invalid certificate header");

        // Custom data starts after certificate
        uint256 customDataStart = 8 + certSize;
        require(proof.length >= customDataStart + 9, "Proof too short for custom data");

        // Verify version
        require(proof[customDataStart] == 0x01, "Unsupported proof version");

        // Extract preimage size
        uint256 preimageSize;
        assembly {
            preimageSize := shr(192, calldataload(add(proof.offset, add(customDataStart, 1))))
        }

        require(proof.length >= customDataStart + 9 + preimageSize, "Invalid proof length");

        // Extract and verify preimage against sha256sum in the certificate
        bytes calldata preimage = proof[customDataStart + 9:customDataStart + 9 + preimageSize];
        bytes32 dataHashFromCert = bytes32(certificate[1:33]);
        require(sha256(preimage) == dataHashFromCert, "Invalid preimage hash");

        // Extract chunk at offset
        preimageChunk = new bytes(32);
        if (offset < preimage.length) {
            uint256 endPos = offset + 32 > preimage.length ? preimage.length : offset + 32;
            for (uint256 i = offset; i < endPos; i++) {
                preimageChunk[i - offset] = preimage[i];
            }
        }

        return preimageChunk;
    }

    /**
     * @notice Validates whether a certificate is well-formed and legitimate
     * @dev The proof format is: [certSize(8), certificate, claimedValid(1), validityProof...]
     *      For ReferenceDA, the validityProof is simply a version byte (0x01).
     *      Other DA providers can include more complex validity proofs after the claimedValid byte,
     *      such as cryptographic signatures, merkle proofs, or other verification data.
     *
     *      Return vs Revert behavior:
     *      - Reverts when:
     *        - Proof is malformed (checked in this function)
     *        - Provided cert matches proven hash in the instruction (checked in hostio)
     *        - Claimed valid but is invalid and vice versa (checked in hostio)
     *      - Returns false when:
     *        - Certificate is malformed, including wrong length
     *        - Signature is malformed
     *        - Signer is not a trustedSigner
     *      - Returns true when:
     *        - Signer is a trustedSigner and certificate is valid
     *
     * @param proof The proof data starting with [certSize(8), certificate, claimedValid(1), validityProof...]
     * @return isValid True if the certificate is valid, false otherwise
     */
    function validateCertificate(
        bytes calldata proof
    ) external view override returns (bool isValid) {
        // Extract certificate size
        require(proof.length >= 8, "Proof too short");

        uint256 certSize;
        assembly {
            certSize := shr(192, calldataload(add(proof.offset, 0)))
        }

        // Check we have enough data for certificate and validity proof
        require(proof.length >= 8 + certSize + 2, "Proof too short for cert and validity");

        bytes calldata certificate = proof[8:8 + certSize];

        // Certificate format is: [prefix(1), dataHash(32), v(1), r(32), s(32)] = 98 bytes total
        // First byte must be 0x01 (CustomDA message header flag)
        // Note: We return false for invalid certificates instead of reverting
        // because the certificate is already onchain. An honest validator must be able
        // to win a challenge to prove that ValidatePreImage should return false
        // so that an invalid cert can be skipped.
        if (certificate.length != 98) {
            return false; // Invalid certificate length
        }
        if (certificate[0] != 0x01) {
            return false; // Invalid certificate header
        }

        // Extract data hash and signature components
        bytes32 dataHash = bytes32(certificate[1:33]);
        uint8 v = uint8(certificate[33]);
        bytes32 r = bytes32(certificate[34:66]);
        bytes32 s = bytes32(certificate[66:98]);

        // Recover signer from signature
        address signer = ecrecover(dataHash, v, r, s);

        // Check if signature is valid (ecrecover returns 0 on invalid signature)
        if (signer == address(0)) {
            return false;
        }

        // Check if signer is trusted
        if (!trustedSigners[signer]) {
            return false;
        }

        // Check version byte at the end of the proof
        // Note: This is a deliberately simple example. A good rule of thumb is that
        // anything added to the proof beyond the isValid byte must not be able to cause both
        // true and false to be returned from this function, given the same certificate.
        uint8 version = uint8(proof[proof.length - 1]);
        require(version == 0x01, "Invalid proof version");

        return true;
    }
}
