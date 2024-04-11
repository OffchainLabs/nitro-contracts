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

    MinHeapLib.Heap internal bids;
    Entry[] public entries;

    uint64 public cacheSize;
    uint64 public queueSize;
    uint64 public decay;
    bool public isPaused;

    error NotChainOwner(address sender);
    error AsmTooLarge(uint256 asm, uint256 queueSize, uint256 cacheSize);
    error AlreadyCached(bytes32 codehash);
    error BidTooSmall(uint256 bid, uint256 min);
    error BidsArePaused();

    event InsertBid(uint256 bid, bytes32 indexed codehash, uint64 size);
    event DeleteBid(uint256 bid, bytes32 indexed codehash, uint64 size);
    event Pause();
    event Unpause();

    struct Entry {
        bytes32 code;
        uint64 size;
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
    }

    /// Sets the intended decay factor. Does not modify existing bids.
    function setDecayRate(uint64 newDecay) external onlyOwner {
        decay = newDecay;
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
            (uint256 bid, uint64 index) = _getBid(bids.pop());
            _deleteEntry(bid, index);
            count -= 1;
        }
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

        // discount historical bids by the number of seconds
        uint256 bid = msg.value + block.timestamp * uint256(decay);
        uint64 asm = _asmSize(codehash);
        uint64 index = uint64(entries.length);
        uint256 min;

        // pop entries until we have enough space
        while (queueSize + asm > cacheSize) {
            (min, index) = _getBid(bids.pop());
            _deleteEntry(min, index);
        }
        if (bid < min) {
            revert BidTooSmall(bid, min);
        }
        return _addBid(bid, codehash, asm, index);
    }

    /// Adds a bid
    function _addBid(
        uint256 bid,
        bytes32 code,
        uint64 size,
        uint64 index
    ) internal {
        if (queueSize + size > cacheSize) {
            revert AsmTooLarge(size, queueSize, cacheSize);
        }

        Entry memory entry = Entry({size: size, code: code});
        ARB_WASM_CACHE.cacheCodehash(code);
        bids.push(_packBid(bid, index));
        queueSize += size;
        if (index == entries.length) {
            entries.push(entry);
        } else {
            entries[index] = entry;
        }
        emit InsertBid(bid, code, size);
    }

    /// Clears the entry at the given index
    function _deleteEntry(uint256 bid, uint64 index) internal {
        Entry memory entry = entries[index];
        ARB_WASM_CACHE.evictCodehash(entry.code);
        queueSize -= entry.size;
        emit DeleteBid(bid, entry.code, entry.size);
        delete entries[index];
    }

    /// Gets the bid and index from a packed bid item
    function _getBid(uint256 info) internal pure returns (uint256 bid, uint64 index) {
        bid = info >> 64;
        index = uint64(info);
    }

    /// Creates a packed bid item
    function _packBid(uint256 bid, uint64 index) internal pure returns (uint256) {
        return (bid << 64) | uint256(index);
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
