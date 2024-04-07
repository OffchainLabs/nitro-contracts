// Copyright 2022-2024, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro/blob/master/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity >=0.4.21 <0.9.0;

/**
 * @title Methods for managing Stylus caches
 * @notice Precompiled contract that exists in every Arbitrum chain at 0x0000000000000000000000000000000000000072.
 */
interface ArbWasmCache {
    /// @notice See if the user is a cache manager.
    function isCacheManager(address manager) external view returns (bool);

    /// @notice Gets the trie table params.
    /// @return bits size of the cache as a power of 2.
    /// @return reads the number of items to read when determining inclusion.
    function trieTableParams() external view returns (uint8 bits, uint8 reads);

    /// @notice Configures the trie table.
    /// @notice Caller must be a cache manager or chain owner.
    /// @param bits size of the cache as a power of 2.
    /// @param reads the number of items to read when determining inclusion.
    function setTrieTableParams(uint8 bits, uint8 reads) external;

    /// @notice Caches all programs with the given codehash.
    /// @notice Reverts if the programs have expired.
    /// @notice Caller must be a cache manager or chain owner.
    /// @notice If you're looking for how to bid for position, interact with the chain's cache manager contract.
    function cacheCodehash(bytes32 codehash) external;

    /// @notice Evicts all programs with the given codehash.
    /// @notice Caller must be a cache manager or chain owner.
    function evictCodehash(bytes32 codehash) external;

    /// @notice Gets whether a program is cached. Note that the program may be expired.
    function codehashIsCached(bytes32 codehash) external view returns (bool);

    /// @notice Reads the trie table record at the given offset.
    /// @notice Caller must be a cache manager or chain owner.
    /// @param offset the record's offset.
    /// @return slot the cached slot.
    /// @return program the slot's account.
    /// @return next the next record to read when determining inclusion.
    function ReadTrieTableRecord(uint64 offset)
        external
        view
        returns (
            uint256 slot,
            address program,
            uint64 next
        );

    /// @notice Writes a trie table record.
    /// @notice Caller must be a cache manager or chain owner.
    /// @notice If you're looking for how to bid for position, interact with the chain's cache manager contract.
    /// @param slot the slot to cache.
    /// @param program the slot's account.
    /// @param next the next record to read when determining inclusion.
    /// @param offset the record's offset.
    function WriteTrieTableRecord(
        uint256 slot,
        address program,
        uint64 next,
        uint64 offset
    ) external;
}
