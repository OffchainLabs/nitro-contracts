// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../../src/rollup/transition/IRollupUserTransition.sol";
import "../../../src/rollup/transition/IRollupAdminTransition.sol";

/// @notice The transitional entrypoints exist so pre-MEL callers keep working, so their selectors
///         are pinned to the values the pre-MEL contracts exposed. Dispatch through the proxy is
///         covered by RollupTransition.t.sol.
contract TransitionAbiTest is Test {
    string constant LEGACY_INPUTS =
        "((bytes32,bytes32,(bytes32,uint256,address,uint64,uint64)),((bytes32[2],uint64[2]),uint8,bytes32),((bytes32[2],uint64[2]),uint8,bytes32))";

    function testLegacyUserSelectorsPinned() public {
        _assertSelector(IRollupUserTransition.stakeOnNewAssertion.selector, 0x3b86de19);
        _assertSelector(IRollupUserTransition.fastConfirmNewAssertion.selector, 0x6420fb9f);
        _assertSelector(IRollupUserTransition.confirmAssertion.selector, 0x10b98a35);
        _assertSelector(
            _selector("newStakeOnNewAssertion(uint256,", LEGACY_INPUTS, ",bytes32)"), 0x7300201c
        );
        _assertSelector(
            _selector("newStakeOnNewAssertion(uint256,", LEGACY_INPUTS, ",bytes32,address)"),
            0x50f32f68
        );
    }

    function testLegacyValidateConfigSelectorPinned() public {
        _assertSelector(IAssertionChainTransition.validateConfig.selector, 0x04972af9);
    }

    function testLegacyForceCreateAssertionSelectorPinned() public {
        _assertSelector(IRollupAdminTransition.forceCreateAssertion.selector, 0x9a7b4556);
    }

    // Unlike the selectors above this is not the pre-MEL event: that one carried a uint256
    // inboxMaxCount where this carries the bytes32 parent chain pin. Pinned so any change is
    // deliberate, since nitro parses it.
    function testTransitionalAssertionCreatedEventPinned() public {
        assertEq(
            keccak256(
                abi.encodePacked(
                    "AssertionCreated(bytes32,bytes32,",
                    LEGACY_INPUTS,
                    ",bytes32,bytes32,bytes32,uint256,address,uint64)"
                )
            ),
            bytes32(0xb59d3830618879267e8336eefb56e7a24ea84e444d5472721e556ee7ec6729ec)
        );
    }

    function _selector(
        string memory prefix,
        string memory inputs,
        string memory suffix
    ) internal pure returns (bytes4) {
        return bytes4(keccak256(abi.encodePacked(prefix, inputs, suffix)));
    }

    function _assertSelector(
        bytes4 actual,
        bytes4 expected
    ) internal {
        assertEq(bytes32(actual), bytes32(expected));
    }
}
