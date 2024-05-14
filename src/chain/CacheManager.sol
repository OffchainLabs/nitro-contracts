// Copyright 2022-2024, Offchain Labs, Inc.
// For license information, see https://github.com/nitro/blob/master/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "../precompiles/ArbOwnerPublic.sol";
import "../precompiles/ArbWasm.sol";
import "../precompiles/ArbWasmCache.sol";
import "solady/src/utils/MinHeapLib.sol";

contract CacheManager {
    using MinHeapLib for MinHeapLib.Heap;

    ArbOwnerPublic internal constant ARB_OWNER_PUBLIC = ArbOwnerPublic(address(0x6b));
    ArbWasm internal constant ARB_WASM = ArbWasm(address(0x71));
    ArbWasmCache internal constant ARB_WASM_CACHE = ArbWasmCache(address(0x72));
    uint64 internal constant MAX_MAKE_SPACE = 5 * 1024 * 1024;

    MinHeapLib.Heap internal bids;
    Entry[] public entries;

    uint64 public cacheSize;
    uint64 public queueSize;
    uint64 public decay;
    bool public isPaused;

    error NotChainOwner(address sender);
    error AsmTooLarge(uint256 asm, uint256 queueSize, uint256 cacheSize);
    error AlreadyCached(bytes32 codehash);
    error BidTooLarge(uint256 bid);
    error BidTooSmall(uint192 bid, uint192 min);
    error BidsArePaused();
    error MakeSpaceTooLarge(uint64 size, uint64 limit);

    event InsertBid(bytes32 indexed codehash, uint192 bid, uint64 size);
    event DeleteBid(bytes32 indexed codehash, uint192 bid, uint64 size);
    event SetCacheSize(uint64 size);
    event SetDecayRate(uint64 decay);
    event Pause();
    event Unpause();

    struct Entry {
        bytes32 code;
        uint64 size;
        uint192 bid;
    }

    constructor(uint64 initCacheSize, uint64 initDecay) {
        cacheSize = initCacheSize;
        decay = initDecay;
    }

    modifier onlyOwner() {
        if (!ARB_OWNER_PUBLIC.isChainOwner(msg.sender)) {
            revert NotChainOwner(msg.sender);
        }
        _;
    }

    /// Sets the intended cache size. Note that the queue may temporarily be larger.
    function setCacheSize(uint64 newSize) external onlyOwner {
        cacheSize = newSize;
        emit SetCacheSize(newSize);
    }

    /// Sets the intended decay factor. Does not modify existing bids.
    function setDecayRate(uint64 newDecay) external onlyOwner {
        decay = newDecay;
        emit SetDecayRate(newDecay);
    }

    /// Disable new bids.
    function paused() external onlyOwner {
        isPaused = true;
        emit Pause();
    }

    /// Enable new bids.
    function unpause() external onlyOwner {
        isPaused = false;
        emit Unpause();
    }

    /// Evicts all programs in the cache.
    function evictAll() external onlyOwner {
        evictPrograms(type(uint256).max);
        delete entries;
    }

    /// Evicts up to `count` programs from the cache.
    function evictPrograms(uint256 count) public onlyOwner {
        while (bids.length() != 0 && count > 0) {
            (uint192 bid, uint64 index) = _getBid(bids.pop());
            _deleteEntry(bid, index);
            count -= 1;
        }
    }

    /// Returns all entries in the cache. Might revert if the cache is too large.
    function getEntries() external view returns (Entry[] memory) {
        return entries;
    }

    /// Returns the `k` smallest entries in the cache sorted in ascending order.
    /// If the cache have less than `k` entries, returns all entries.
    function getSmallestEntries(uint256 k) public view returns (Entry[] memory result) {
        if (bids.length() < k) {
            k = bids.length();
        }
        result = new Entry[](k);
        uint256[] memory kbids = bids.smallest(k);
        for (uint256 i = 0; i < k; i++) {
            (, uint64 index) = _getBid(kbids[i]);
            result[i] = entries[index];
        }
        return result;
    }

    /// Returns the minimum bid required to cache a program of the given size.
    /// Value returned here is the minimum bid that you can send with msg.value
    function getMinBid(uint64 size) public view returns (uint192 min) {
        if (size > cacheSize) {
            revert AsmTooLarge(size, 0, cacheSize);
        }
        uint256 freeSize = cacheSize - queueSize;
        if (size < freeSize) {
            return 0;
        }
        uint256 chunkSize = 10;
        uint256 k = chunkSize;
        while (true) {
            // this loop must terminate as size <= cacheSize
            Entry[] memory smallest = getSmallestEntries(k);
            for (uint256 i = k - chunkSize; i < smallest.length; i++) {
                freeSize += smallest[i].size;
                if (freeSize >= size) {
                    min = smallest[i].bid;
                    break;
                }
            }
            if (min > 0) break;
            k += chunkSize;
        }
        if (min < _calcDecay()) {
            return 0;
        }
        min = min - uint192(_calcDecay());
    }

    /// Returns the minimum bid required to cache the program with given codehash.
    /// Value returned here is the minimum bid that you can send with msg.value
    function getMinBid(bytes32 codehash) external view returns (uint192 min) {
        return getMinBid(_asmSize(codehash));
    }

    /// Sends all revenue to the network fee account.
    function sweepFunds() external {
        (bool success, bytes memory data) = ARB_OWNER_PUBLIC.getNetworkFeeAccount().call{
            value: address(this).balance
        }("");
        if (!success) {
            assembly {
                revert(add(data, 32), mload(data))
            }
        }
    }

    /// Places a bid, reverting if payment is insufficient.
    function placeBid(bytes32 codehash) external payable {
        if (isPaused) {
            revert BidsArePaused();
        }
        if (_isCached(codehash)) {
            revert AlreadyCached(codehash);
        }

        uint64 asm = _asmSize(codehash);
        (uint192 bid, uint64 index) = _makeSpace(asm);
        return _addBid(bid, codehash, asm, index);
    }

    /// Evicts entries until enough space exists in the cache, reverting if payment is insufficient.
    /// Returns the new amount of space available on success.
    /// Note: will revert for requests larger than 5Mb. Call repeatedly for more.
    function makeSpace(uint64 size) external payable returns (uint64 space) {
        if (isPaused) {
            revert BidsArePaused();
        }
        if (size > MAX_MAKE_SPACE) {
            revert MakeSpaceTooLarge(size, MAX_MAKE_SPACE);
        }
        _makeSpace(size);
        return cacheSize - queueSize;
    }

    function _calcDecay() internal view returns (uint256) {
        return block.timestamp * decay;
    }

    /// Converts a value to a bid by adding the time decay term.
    function _toBid(uint256 value) internal view returns (uint192 bid) {
        uint256 _bid = value + _calcDecay();
        if (_bid > type(uint192).max) {
            revert BidTooLarge(_bid);
        }
        return uint192(_bid);
    }

    /// Evicts entries until enough space exists in the cache, reverting if payment is insufficient.
    /// Returns the bid and the index to use for insertion.
    function _makeSpace(uint64 size) internal returns (uint192 bid, uint64 index) {
        // discount historical bids by the number of seconds
        bid = _toBid(msg.value);
        index = uint64(entries.length);

        uint192 min;
        uint64 limit = cacheSize;
        while (queueSize + size > limit) {
            (min, index) = _getBid(bids.pop());
            _deleteEntry(min, index);
        }
        // if the new bid equals to the minimum bid, a random entry with minimum bid will be evicted
        if (bid < min) {
            revert BidTooSmall(bid, min);
        }
    }

    /// Adds a bid
    function _addBid(
        uint192 bid,
        bytes32 code,
        uint64 size,
        uint64 index
    ) internal {
        if (queueSize + size > cacheSize) {
            revert AsmTooLarge(size, queueSize, cacheSize);
        }

        Entry memory entry = Entry({size: size, code: code, bid: bid});
        ARB_WASM_CACHE.cacheCodehash(code);
        bids.push(_packBid(bid, index));
        queueSize += size;
        if (index == entries.length) {
            entries.push(entry);
        } else {
            entries[index] = entry;
        }
        emit InsertBid(code, bid, size);
    }

    /// Clears the entry at the given index
    function _deleteEntry(uint192 bid, uint64 index) internal {
        Entry memory entry = entries[index];
        ARB_WASM_CACHE.evictCodehash(entry.code);
        queueSize -= entry.size;
        emit DeleteBid(entry.code, bid, entry.size);
        delete entries[index];
    }

    /// Gets the bid and index from a packed bid item
    function _getBid(uint256 info) internal pure returns (uint192 bid, uint64 index) {
        bid = uint192(info >> 64);
        index = uint64(info);
    }

    /// Creates a packed bid item
    function _packBid(uint192 bid, uint64 index) internal pure returns (uint256) {
        return (uint256(bid) << 64) | uint256(index);
    }

    /// Gets the size of the given program in bytes
    function _asmSize(bytes32 codehash) internal view returns (uint64) {
        uint32 size = ARB_WASM.codehashAsmSize(codehash);
        return uint64(size >= 4096 ? size : 4096); // pretend it's at least 4Kb
    }

    /// Determines whether a program is cached
    function _isCached(bytes32 codehash) internal view returns (bool) {
        return ARB_WASM_CACHE.codehashIsCached(codehash);
    }
}
