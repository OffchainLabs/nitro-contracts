// Copyright 2021-2024, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

/**
 * @title ICustomDAProofValidator
 * @notice Interface for custom data availability proof validators
 */
interface ICustomDAProofValidator {
    /**
     * @notice Validates a custom DA proof and returns the preimage chunk
     * @param certHash The keccak256 hash of the certificate (from machine's proven state)
     * @param offset The offset into the preimage to read from (from machine's proven state)
     * @param proof The proof data starting with [certSize(8), certificate, customData...]
     * @return preimageChunk The 32-byte chunk of preimage data at the specified offset
     */
    function validateReadPreimage(
        bytes32 certHash,
        uint256 offset,
        bytes calldata proof
    ) external view returns (bytes memory preimageChunk);
}
