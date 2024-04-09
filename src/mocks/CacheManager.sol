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

    error NotChainOwner(address sender);
    error AsmTooLarge(uint256 asm, uint256 cacheSize);
    error AlreadyCached(bytes32 codehash);
    error BidTooSmall(uint256 bid, uint256 min);

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

    /// Evicts all programs in the cache.
    function evictAll() external onlyOwner {
        while (bids.length() != 0) {
            uint64 index = _getIndex(bids.pop());
            Entry memory entry = entries[index];
            _evict(entry.code);
            delete entries[index];
        }
        queueSize = 0;
    }

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

    function placeBid(bytes32 codehash) external payable {
        if (_isCached(codehash)) {
            revert AlreadyCached(codehash);
        }

        // discount historical bids by the number of seconds
        uint256 bid = msg.value + block.timestamp * uint256(decay);
        uint64 asm = _asmSize(codehash);
        if (asm > cacheSize) {
            revert AsmTooLarge(asm, cacheSize);
        }

        Entry memory candidate = Entry({size: asm, code: codehash});

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
            if (bid > min) {
                revert BidTooSmall(_clearIndex(bid), _clearIndex(min));
            }

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

    function _getIndex(uint256 info) internal pure returns (uint64) {
        return uint64(info >> 192);
    }

    function _setIndex(uint256 info, uint64 index) internal pure returns (uint256) {
        uint256 mask = 0xffffffffffffffffffffffffffffffffffffffffffffffff;
        return (info & mask) | (uint256(index) << 192);
    }

    function _clearIndex(uint256 info) internal pure returns (uint256) {
        return _setIndex(info, 0);
    }

    function _asmSize(bytes32 codehash) internal view returns (uint64) {
        uint32 size = ARB_WASM.codehashAsmSize(codehash);
        return uint64(size >= 4096 ? size : 4096); // pretend it's at least 4Kb
    }

    function _isCached(bytes32 codehash) internal view returns (bool) {
        return ARB_WASM_CACHE.codehashIsCached(codehash);
    }

    function _cache(bytes32 codehash) internal {
        ARB_WASM_CACHE.cacheCodehash(codehash);
    }

    function _evict(bytes32 codehash) internal {
        ARB_WASM_CACHE.evictCodehash(codehash);
    }
}
