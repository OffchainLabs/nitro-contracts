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
     * @param proof ReferenceDA proof format: [certKeccak256(32), offset(8), Version(1), CertificateSize(8), Certificate, PreimageSize(8), PreimageData]
     * @return preimageChunk The 32-byte chunk at the specified offset
     */
    function validateReadPreimage(
        bytes calldata proof
    ) external pure override returns (bytes memory preimageChunk) {
        // Proof format: [certKeccak256(32), offset(8), Version(1), CertificateSize(8), Certificate, PreimageSize(8), PreimageData]
        require(proof.length >= 58, "Proof too short"); // 32 + 8 + 1 + 8 + 8 + at least 1 byte

        // Extract certKeccak256 and offset from enhanced proof wrapper
        bytes32 certKeccak256;
        uint256 offset;
        assembly {
            certKeccak256 := calldataload(add(proof.offset, 0))
            offset := shr(192, calldataload(add(proof.offset, 32))) // Read 8 bytes as uint256
        }

        // The actual custom proof starts at offset 40
        uint256 customProofStart = 40;

        // Verify version
        require(proof[customProofStart] == 0x01, "Unsupported proof version");

        // Extract certificate size
        uint256 certSize;
        assembly {
            certSize := shr(192, calldataload(add(proof.offset, add(customProofStart, 1)))) // Read 8 bytes as uint256
        }
        require(certSize == 33, "Certificate must be 33 bytes");

        // Extract and verify certificate
        uint256 certStart = customProofStart + 9; // Skip version(1) + certSize(8)
        bytes memory certificate = proof[certStart:certStart + certSize];
        require(certificate[0] == 0x01, "Invalid certificate header");
        require(keccak256(certificate) == certKeccak256, "Invalid certificate hash");

        // Extract SHA256 from certificate
        bytes32 sha256Hash;
        assembly {
            sha256Hash := mload(add(certificate, 33)) // Skip length prefix and header byte
        }

        // Extract preimage size
        uint256 preimageOffset = certStart + certSize;
        uint256 preimageSize;
        assembly {
            preimageSize := shr(192, calldataload(add(proof.offset, preimageOffset))) // Read 8 bytes as uint256
        }

        require(proof.length >= preimageOffset + 8 + preimageSize, "Invalid proof length");

        // Extract preimage data
        bytes memory preimage = proof[preimageOffset + 8:preimageOffset + 8 + preimageSize];

        // Verify SHA256 hash matches
        require(sha256(abi.encodePacked(preimage)) == sha256Hash, "Invalid preimage hash");

        // Extract chunk at offset
        uint256 chunkStart = offset;
        uint256 chunkEnd = offset + 32;
        if (chunkEnd > preimage.length) {
            chunkEnd = preimage.length;
        }

        uint256 chunkSize = chunkEnd - chunkStart;
        preimageChunk = new bytes(32);

        if (chunkSize > 0) {
            for (uint256 i = 0; i < chunkSize; i++) {
                preimageChunk[i] = preimage[chunkStart + i];
            }
        }

        return preimageChunk;
    }
}
