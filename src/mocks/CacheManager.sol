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

    MinHeapLib.Heap bids;
    Entry[] entries;

    uint64 cacheSize;
    uint64 queueSize;
    uint64 decay;

    struct Entry {
        bytes32 code;
        uint256 paid;
        uint64 size;
        address payable bidder;
    }

    constructor(uint64 initCacheSize, uint64 initDecay) {
        cacheSize = initCacheSize;
        decay = initDecay;
    }

    /// Sets the intended cache size. Note that the queue may temporarily be larger.
    function setCacheSize(uint64 newSize) external {
        _requireOwner();
        cacheSize = newSize;
    }

    /// Evicts all programs in the cache and returns all payments.
    function evictAll() external {
        _requireOwner();

        while (bids.length() != 0) {
            uint64 index = _getIndex(bids.pop());
            Entry memory entry = entries[index];
            _evict(entry.code);

            // return funds to user
            entry.bidder.call{value: entry.paid, gas: 0};
            delete entries[index];
        }
        queueSize = 0;
    }

    function placeBid(bytes32 codehash) external payable {
        require(!_isCached(codehash), "ALREADY_CACHED");

        // discount historical bids by the number of seconds
        uint256 bid = msg.value + block.timestamp * uint256(decay);
        uint64 asm = _asmSize(codehash);

        Entry memory candidate = Entry({
            size: asm,
            code: codehash,
            paid: msg.value,
            bidder: payable(msg.sender)
        });

        uint64 index;

        // if there's space, append to the end
        if (queueSize + asm < cacheSize) {
            index = uint64(entries.length);
            bid = _setIndex(bid, index);

            bids.push(bid);
            queueSize += asm;
            _cache(codehash);
            entries[index] = candidate;
            return;
        }

        // pop entries until we have enough space
        while (true) {
            uint256 min = bids.root();
            index = _getIndex(min);
            bid = _setIndex(bid, index); // make both have same index

            require(bid > min, "BID_TOO_SMALL");

            // evict the entry
            Entry memory entry = entries[index];
            _evict(entry.code);
            queueSize -= entry.size;
            bids.pop();
            delete entries[index];

            if (queueSize + asm < cacheSize) {
                break;
            }
        }

        // replace the min with the new bid
        _cache(codehash);
        entries[index] = candidate;
        bids.push(bid);
    }

    function _requireOwner() internal view {
        bool owner = ArbOwnerPublic(address(0x6b)).isChainOwner(address(msg.sender));
        require(owner, "NOT_OWNER");
    }

    function _getIndex(uint256 info) internal pure returns (uint64) {
        return uint64(info >> 192);
    }

    function _setIndex(uint256 info, uint64 index) internal pure returns (uint256) {
        uint256 mask = 0xffffffffffffffffffffffffffffffffffffffffffffffff;
        return (info & mask) | (uint256(index) << 192);
    }

    function _asmSize(bytes32 codehash) internal view returns (uint64) {
        uint64 size = ArbWasm(address(0x71)).codehashAsmSize(codehash);
        return size >= 4096 ? size : 4096; // pretend it's at least 4Kb
    }

    function _isCached(bytes32 codehash) internal view returns (bool) {
        return ArbWasmCache(address(0x72)).codehashIsCached(codehash);
    }

    function _cache(bytes32 codehash) internal {
        ArbWasmCache(address(0x72)).cacheCodehash(codehash);
    }

    function _evict(bytes32 codehash) internal {
        ArbWasmCache(address(0x72)).evictCodehash(codehash);
    }
}
