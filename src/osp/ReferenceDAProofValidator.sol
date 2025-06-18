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
     * @param proof ReferenceDA proof format: [hash(32), offset(8), Version(1), PreimageSize(8), PreimageData]
     * @return preimageChunk The 32-byte chunk at the specified offset
     */
    function validateReadPreimage(
        bytes calldata proof
    ) external pure override returns (bytes memory preimageChunk) {
        // ReferenceDA proof format: [hash(32), offset(8), Version(1), PreimageSize(8), PreimageData]
        require(proof.length >= 49, "Proof too short"); // 32 + 8 + 1 + 8

        // Extract hash and offset that were included by the off-chain enhancer
        bytes32 hash;
        uint256 offset;
        assembly {
            hash := calldataload(add(proof.offset, 0))
            offset := shr(192, calldataload(add(proof.offset, 32))) // Read 8 bytes as uint256
        }

        // Decode the actual proof data
        require(proof[40] == 1, "Unsupported proof version");

        uint256 preimageSize;
        assembly {
            preimageSize := shr(192, calldataload(add(proof.offset, 41))) // Read 8 bytes as uint256
        }
        require(proof.length == 49 + preimageSize, "Invalid proof length");

        // Extract preimage data
        bytes memory preimage = proof[49:];

        // Verify hash
        require(keccak256(preimage) == hash, "Invalid preimage");

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
