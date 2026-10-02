// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

/**
 * @title IHashProofHelper
 * @notice Proves keccak256 preimages and stores slices of up to 32 bytes for later retrieval.
 *         Used by the OneStepProverHostIo to verify large preimages that don't fit
 *         in a single transaction's calldata. The preimage is uploaded in advance
 *         (in one or more transactions), and later retrieved during the one-step proof.
 */
interface IHashProofHelper {
    /// @notice Emitted when a preimage part is proven and stored
    event PreimagePartProven(bytes32 indexed fullHash, uint64 indexed offset, bytes part);

    /// @notice The requested preimage part has not been proven yet
    error NotProven(bytes32 fullHash, uint64 offset);

    /**
     * @notice Proves a preimage in a single transaction by providing all data at once
     * @param data The full preimage
     * @param offset Byte offset into the preimage. Up to 32 bytes at this offset are stored
     *        as the proven part. If offset is past the end of data, an empty part is stored.
     * @return fullHash keccak256(data)
     */
    function proveWithFullPreimage(
        bytes calldata data,
        uint64 offset
    ) external returns (bytes32 fullHash);

    /**
     * @notice Proves a preimage across multiple transactions by uploading data in chunks.
     *         Each chunk is absorbed into an incremental keccak256 computation stored
     *         per sender. On the final chunk, the hash is finalized and the proven part
     *         is stored.
     * @param data The next chunk of preimage data. Must be a multiple of 136 bytes
     *        (the keccak round size) unless this is the final chunk
     * @param offset Byte offset into the full preimage for the 32-byte part to prove.
     *        Must be the same value across all chunks of a single proof.
     * @param flags a bitset signaling various things about the proof, ordered from least to most significant bits:
     *        - bit 0: indicates that this data is the final chunk of preimage data, which triggers padding, hash finalization, and storage
     *        - bit 1: indicates that the unfinished preimage currently being built should be cleared before this
     * @return fullHash if the final chunk is passed, keccak256 of the full preimage; otherwise, bytes32(0)
     */
    function proveWithSplitPreimage(
        bytes calldata data,
        uint64 offset,
        uint256 flags
    ) external returns (bytes32 fullHash);

    /**
     * @notice Retrieves a previously proven preimage part
     * @param fullHash The keccak256 hash of the preimage
     * @param offset The byte offset that was used when the part was proven
     * @return The proven bytes (up to 32). Reverts with NotProven if the part
     *         at this hash and offset hasn't been proven yet.
     */
    function getPreimagePart(
        bytes32 fullHash,
        uint64 offset
    ) external view returns (bytes memory);
}
