// Copyright 2026, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE.md
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/rollup/RollupAdminLogic.sol";
import "../../src/precompiles/ArbSys.sol";

/// Exposes the internal helper both createNewAssertion and RollupAdminLogic.initialize use to
/// pin the terminal an assertion's child must extend from. RollupAdminLogic is concrete and
/// inherits RollupCore's `_hostChainIsArbitrum` immutable, so deploying one is enough to
/// exercise the branch without standing up a whole rollup.
contract NextParentChainBlockHashHarness is RollupAdminLogic {
    function exposedNextParentChainBlockHash() external view returns (bytes32) {
        return _nextParentChainBlockHash();
    }
}

contract RollupParentChainHashTest is Test {
    uint256 constant ARB_BLOCK = 12_345;
    bytes32 constant ARB_BLOCK_HASH = keccak256("arbBlockHash(12344)");

    /// `_hostChainIsArbitrum` is an immutable initialized from ArbitrumChecker at construction,
    /// so ArbSys has to answer before the harness is deployed, not after.
    function _mockArbitrumHost() internal {
        vm.mockCall(
            address(100),
            abi.encodeWithSelector(ArbSys.arbOSVersion.selector),
            abi.encode(uint256(11))
        );
    }

    function testUsesArbSysOnArbitrumHostChain() public {
        _mockArbitrumHost();
        NextParentChainBlockHashHarness harness = new NextParentChainBlockHashHarness();

        vm.mockCall(
            address(100),
            abi.encodeWithSelector(ArbSys.arbBlockNumber.selector),
            abi.encode(ARB_BLOCK)
        );
        vm.mockCall(
            address(100),
            abi.encodeWithSelector(ArbSys.arbBlockHash.selector, ARB_BLOCK - 1),
            abi.encode(ARB_BLOCK_HASH)
        );

        assertEq(
            harness.exposedNextParentChainBlockHash(),
            ARB_BLOCK_HASH,
            "must pin arbBlockHash(arbBlockNumber() - 1), not the L1 ring buffer"
        );
        // The bug this guards: blockhash() on an Arbitrum host resolves against the L1 ring
        // buffer, so MEL's parentChainBlockHash could never equal it.
        assertTrue(
            harness.exposedNextParentChainBlockHash() != blockhash(block.number - 1),
            "fixture must make the two sources differ, or this test proves nothing"
        );
    }

    function testUsesBlockhashOffArbitrum() public {
        NextParentChainBlockHashHarness harness = new NextParentChainBlockHashHarness();
        assertEq(
            harness.exposedNextParentChainBlockHash(),
            blockhash(block.number - 1),
            "off an Arbitrum host chain the terminal is still blockhash(block.number - 1)"
        );
    }
}
