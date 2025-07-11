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
     * @param proof Standardized CustomDA proof format is: [certKeccak256(32), offset(8), certSize(8), certificate]
	                followed by the ReferenceDA specific: [version(1), preimageSize(8), preimageData]
     * @return preimageChunk The 32-byte chunk at the specified offset
     */
    function validateReadPreimage(
        bytes calldata proof
    ) external pure override returns (bytes memory preimageChunk) {
        // Extract offset from standardized header (already validated by OSP)
        uint256 offset;
        uint256 certSize;
        assembly {
            offset := shr(192, calldataload(add(proof.offset, 32))) // Read 8 bytes at position 32
            certSize := shr(192, calldataload(add(proof.offset, 40))) // Read 8 bytes at position 40
        }

        // Certificate has already been validated by OSP, just extract it
        uint256 certStart = 48;
        require(proof.length >= certStart + certSize, "Proof too short for certificate");
        bytes calldata certificate = proof[certStart:certStart + certSize];

        // Validate certificate format for ReferenceDA
        require(certificate.length == 33, "Invalid certificate length");
        require(certificate[0] == 0x01, "Invalid certificate header");

        // Extract SHA256 hash from certificate
        bytes32 sha256Hash = bytes32(certificate[1:33]);

        // Custom data starts after certificate
        uint256 customDataStart = certStart + certSize;
        require(proof.length >= customDataStart + 9, "Proof too short for custom data");

        // Verify version
        require(proof[customDataStart] == 0x01, "Unsupported proof version");

        // Extract preimage size
        uint256 preimageSize;
        assembly {
            preimageSize := shr(192, calldataload(add(proof.offset, add(customDataStart, 1))))
        }

        require(proof.length >= customDataStart + 9 + preimageSize, "Invalid proof length");

        // Extract and verify preimage
        bytes calldata preimage = proof[customDataStart + 9:customDataStart + 9 + preimageSize];
        require(sha256(preimage) == sha256Hash, "Invalid preimage hash");

        // Extract chunk at offset
        uint256 chunkEnd = offset + 32;
        if (chunkEnd > preimage.length) {
            chunkEnd = preimage.length;
        }

        preimageChunk = new bytes(32);
        if (offset < preimage.length) {
            uint256 chunkSize = chunkEnd - offset;
            for (uint256 i = 0; i < chunkSize; i++) {
                preimageChunk[i] = preimage[offset + i];
            }
        }

        return preimageChunk;
    }
}
