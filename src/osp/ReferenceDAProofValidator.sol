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
     * @param proof ReferenceDA proof format: [certKeccak256(32), offset(8), certificate(33), Version(1), PreimageSize(8), PreimageData]
     * @return preimageChunk The 32-byte chunk at the specified offset
     */
    function validateReadPreimage(
        bytes calldata proof
    ) external pure override returns (bytes memory preimageChunk) {
        // New proof format: [certKeccak256(32), offset(8), certificate(33), Version(1), PreimageSize(8), PreimageData]
        // Certificate is always 33 bytes: [0x01 header(1), SHA256(32)]
        require(proof.length >= 82, "Proof too short"); // 32 + 8 + 33 + 1 + 8

        // Extract certKeccak256 and offset
        bytes32 certKeccak256;
        uint256 offset;
        assembly {
            certKeccak256 := calldataload(add(proof.offset, 0))
            offset := shr(192, calldataload(add(proof.offset, 32))) // Read 8 bytes as uint256
        }

        // Extract and verify certificate (always at offset 40, always 33 bytes)
        bytes memory certificate = proof[40:73];
        require(certificate[0] == 0x01, "Invalid certificate header");
        require(keccak256(certificate) == certKeccak256, "Invalid certificate hash");

        // Extract SHA256 from certificate
        bytes32 sha256Hash;
        assembly {
            sha256Hash := mload(add(certificate, 33)) // Skip length prefix and header byte
        }

        // Verify proof version at offset 73
        require(proof[73] == 0x01, "Unsupported proof version");

        // Extract preimage size at offset 74
        uint256 preimageSize;
        assembly {
            preimageSize := shr(192, calldataload(add(proof.offset, 74))) // Read 8 bytes as uint256
        }

        require(proof.length == 82 + preimageSize, "Invalid proof length");

        // Extract preimage data starting at offset 82
        bytes memory preimage = proof[82:];

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
