// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "../../src/chain/CacheManager.sol";

contract CacheManagerTest is Test {
    CacheManager public cacheManager;
    CachedItem[] public expectedCache;

    uint256 internal constant MAX_PAY = 100_000_000 ether;

    ArbWasmMock internal constant ARB_WASM = ArbWasmMock(address(0x71));
    ArbWasmCacheMock internal constant ARB_WASM_CACHE = ArbWasmCacheMock(address(0x72));

    constructor() {
        uint64 cacheSize = 1_000_000;
        uint64 decay = 0.1 ether;
        cacheManager = new CacheManager(cacheSize, decay);
        require(cacheManager.cacheSize() == cacheSize, "wrong cache size");
        require(cacheManager.decay() == decay, "wrong decay rate");

        vm.etch(address(0x6b), type(ArbOwnerPublicMock).runtimeCode);
        vm.etch(address(0x71), type(ArbWasmMock).runtimeCode);
        vm.etch(address(0x72), type(ArbWasmCacheMock).runtimeCode);
    }

    struct CachedItem {
        bytes32 codehash;
        uint256 bid;
        uint256 size;
    }

    function test_randomBids() external {
        address[] memory programs = new address[](256);
        for (uint256 i = 0; i < programs.length; i++) {
            // Deploy bytes(bytes32(i)) as code to a sample program
            // PUSH32 i PUSH1 0 MSTORE PUSH1 32 PUSH1 0 RETURN
            // at the time of writing this our forge version or config doesn't have PUSH0 support
            bytes memory bytecode = bytes.concat(hex"7F", abi.encodePacked(i), hex"60005260206000F3");
            address program;
            assembly {
                program := create(0, add(bytecode, 32), mload(bytecode))
            }
            if (program == address(0)) {
                revert("zero");
            }
            if (program.codehash != keccak256(abi.encodePacked(i))) {
                revert("failed to deploy sample code");
            }
            programs[i] = program;
        }

        for (uint256 epoch = 0; epoch < 4; epoch++) {
            for (uint256 round = 0; round < 512; round++) {
                // roll one of 256 random programs
                address program = programs[uint256(keccak256(abi.encodePacked("code", epoch, round))) % programs.length];
                bytes32 codehash = program.codehash;

                // roll a random bid
                uint256 pay = uint256(keccak256(abi.encodePacked("value", epoch, round))) % MAX_PAY;
                uint256 bid = pay + block.timestamp * uint256(cacheManager.decay());

                // determine the expected insertion index on success and the bid needed
                uint256 index;
                uint256 asmSize = ARB_WASM.codehashAsmSize(codehash);
                uint256 cumulativeCacheSize = asmSize;
                uint256 neededBid;
                for (; index < expectedCache.length; index++) {
                    if (bid >= expectedCache[index].bid) {
                        break;
                    }
                    cumulativeCacheSize += expectedCache[index].size;
                    if (cumulativeCacheSize > cacheManager.cacheSize()) {
                        neededBid = expectedCache[index].bid;
                        break;
                    }
                }

                if (ARB_WASM_CACHE.codehashIsCached(codehash)) {
                    vm.expectRevert(
                        abi.encodeWithSelector(CacheManager.AlreadyCached.selector, codehash)
                    );
                } else if (neededBid > 0) {
                    vm.expectRevert(
                        abi.encodeWithSelector(CacheManager.BidTooSmall.selector, bid, neededBid)
                    );
                } else {
                    // insert the item by moving over those to the right
                    expectedCache.push(CachedItem(bytes32(0), 0, 0));
                    for (uint256 j = expectedCache.length - 1; j > index; j--) {
                        expectedCache[j] = expectedCache[j - 1];
                    }
                    expectedCache[index] = CachedItem(codehash, bid, asmSize);

                    // pop any excess cache elements
                    for (index++; index < expectedCache.length; index++) {
                        cumulativeCacheSize += expectedCache[index].size;
                        if (cumulativeCacheSize > cacheManager.cacheSize()) {
                            break;
                        }
                    }
                    while (index < expectedCache.length) {
                        expectedCache.pop();
                    }
                }

                cacheManager.placeBid{value: pay}(program);

                require(
                    ARB_WASM_CACHE.numCached() == expectedCache.length,
                    "wrong number of cached items"
                );
                for (uint256 j = 0; j < expectedCache.length; j++) {
                    require(
                        ARB_WASM_CACHE.codehashIsCached(expectedCache[j].codehash),
                        "codehash not cached"
                    );
                }

                if (round == 768) {
                    uint256 newCacheSize = 500_000 +
                        (uint256(keccak256(abi.encodePacked("cacheSize", epoch))) % 1_000_000);
                    cacheManager.setCacheSize(uint64(newCacheSize));
                }
            }

            cacheManager.evictAll();
            require(ARB_WASM_CACHE.numCached() == 0, "cached items after evictAll");
            delete expectedCache;
        }
        require(ARB_WASM_CACHE.uselessCalls() == 0, "useless ArbWasmCache calls");
    }
}

contract ArbOwnerPublicMock {
    address payable constant NETWORK_FEE_ACCOUNT = payable(address(0xba5eba11));

    function getNetworkFeeAccount() external pure returns (address payable) {
        return NETWORK_FEE_ACCOUNT;
    }

    // pretend all smart contracts are chain owners
    function isChainOwner(address addr) external view returns (bool) {
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(addr)
        }
        return codeSize > 0;
    }
}

contract ArbWasmMock {
    // returns a non-uniform distribution of mock code sizes
    function codehashAsmSize(bytes32 codehash) external pure returns (uint64) {
        uint256 size;
        for (uint256 i = 0; i < 3; i++) {
            size += uint256(keccak256(abi.encodePacked(codehash, i))) % 65536;
        }
        return uint64(size);
    }
}

contract ArbWasmCacheMock {
    mapping(bytes32 => bool) public codehashIsCached;
    uint256 public numCached;
    uint256 public uselessCalls;

    function cacheProgram(address addr) external {
        bytes32 codehash = addr.codehash;
        if (codehashIsCached[codehash]) {
            uselessCalls++;
            return;
        }
        codehashIsCached[codehash] = true;
        numCached++;
    }

    function evictCodehash(bytes32 codehash) external {
        if (!codehashIsCached[codehash]) {
            uselessCalls++;
            return;
        }
        codehashIsCached[codehash] = false;
        numCached--;
    }
}
