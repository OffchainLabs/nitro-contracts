// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "../../src/rollup/AbsRollupEventInbox.sol";
import {IBridge} from "../../src/bridge/IBridge.sol";
import {IInboxBase} from "../../src/bridge/IInbox.sol";

abstract contract AbsRollupEventInboxTest is Test {
    IRollupEventInbox public rollupEventInbox;
    IBridge public bridge;

    address public rollup = makeAddr("rollup");

    uint256 public constant MAX_DATA_SIZE = 104_857;

    /* solhint-disable func-name-mixedcase */
    function test_initialize() public {
        assertEq(address(rollupEventInbox.bridge()), address(bridge), "Invalid bridge ref");
        assertEq(address(rollupEventInbox.rollup()), rollup, "Invalid rollup ref");
    }

    function test_initialize_revert_AlreadyInit() public {
        vm.expectRevert(AlreadyInit.selector);
        rollupEventInbox.initialize(bridge);
    }

    function test_updateRollupAddress() public {
        vm.prank(rollup);
        bridge.updateRollupAddress(IOwnable(address(1337)));
        vm.mockCall(
            address(rollup),
            0,
            abi.encodeWithSelector(IOwnable.owner.selector),
            abi.encode(address(this))
        );
        rollupEventInbox.updateRollupAddress();
        assertEq(address(rollupEventInbox.rollup()), address(1337), "Invalid rollup");
    }

    function test_updateRollupAddress_revert_NotOwner() public {
        vm.mockCall(
            address(rollup),
            0,
            abi.encodeWithSelector(IOwnable.owner.selector),
            abi.encode(address(1337))
        );
        vm.expectRevert(abi.encodeWithSelector(NotOwner.selector, address(this), address(1337)));
        rollupEventInbox.updateRollupAddress();
    }

    /**
     *
     * Event declarations
     *
     */
    event MessageDelivered(
        uint256 indexed messageIndex,
        bytes32 indexed beforeInboxAcc,
        address inbox,
        uint8 kind,
        address sender,
        bytes32 messageDataHash,
        uint256 baseFeeL1,
        uint64 timestamp
    );
    event InboxMessageDelivered(uint256 indexed messageNum, bytes data);
}
