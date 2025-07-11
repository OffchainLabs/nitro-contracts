// Copyright 2021-2024, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

/**
 * @title ICustomDAProofValidator
 * @notice Interface for custom data availability proof validators
 * @dev All proofs MUST start with [certKeccak256(32), offset(8), certSize(8), certificate, ...]
 *      The OSP validates certKeccak256 matches the machine's request before calling this
 */
interface ICustomDAProofValidator {
    /**
     * @notice Validates a custom DA proof and returns the preimage chunk
     * @param proof The complete proof data starting with [certKeccak256(32), offset(8), certSize(8), certificate, ...]
     * @return preimageChunk The 32-byte chunk of preimage data
     */
    function validateReadPreimage(
        bytes calldata proof
    ) external view returns (bytes memory preimageChunk);
}
