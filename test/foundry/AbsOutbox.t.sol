// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "./util/TestUtil.sol";
import "../../src/bridge/AbsOutbox.sol";
import "../../src/bridge/IBridge.sol";

abstract contract AbsOutboxTest is Test {
    IOutbox public outbox;
    IBridge public bridge;

    address public user = address(100);
    address public rollup = address(1000);
    address public seqInbox = address(1001);

    /* solhint-disable func-name-mixedcase */
    function test_initialize() public {
        assertEq(address(outbox.bridge()), address(bridge), "Invalid bridge ref");
        assertEq(address(outbox.rollup()), rollup, "Invalid rollup ref");

        assertEq(outbox.l2ToL1Sender(), address(0), "Invalid l2ToL1Sender");
        assertEq(outbox.l2ToL1Block(), 0, "Invalid l2ToL1Block");
        assertEq(outbox.l2ToL1EthBlock(), 0, "Invalid l2ToL1EthBlock");
        assertEq(outbox.l2ToL1Timestamp(), 0, "Invalid l2ToL1Timestamp");
        assertEq(outbox.l2ToL1OutputId(), bytes32(0), "Invalid l2ToL1OutputId");
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
        outbox.updateRollupAddress();
        assertEq(address(outbox.rollup()), address(1337), "Invalid rollup");
    }

    function test_updateRollupAddress_revert_NotOwner() public {
        vm.mockCall(
            address(rollup),
            0,
            abi.encodeWithSelector(IOwnable.owner.selector),
            abi.encode(address(1337))
        );
        vm.expectRevert(abi.encodeWithSelector(NotOwner.selector, address(this), address(1337)));
        outbox.updateRollupAddress();
    }

    function test_executeTransactionSimulation(
        address from
    ) public {
        address outboxProxyAdmin = address(
            uint160(
                uint256(
                    vm.load(
                        address(outbox),
                        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103
                    )
                )
            )
        );
        vm.assume(from != address(0) && from != address(this) && from != outboxProxyAdmin);
        vm.prank(from);
        vm.expectRevert(SimulationOnlyEntrypoint.selector);
        outbox.executeTransactionSimulation(
            0, from, address(1337), 0, 0, 0, 0, abi.encodePacked("some msg")
        );
    }
}
