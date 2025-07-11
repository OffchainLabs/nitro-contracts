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

        // Validate certificate format for ReferenceDA
        require(certificate.length == 33, "Invalid certificate length");
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
        require(sha256(preimage) == bytes32(certificate[1:33]), "Invalid preimage hash");

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
}
