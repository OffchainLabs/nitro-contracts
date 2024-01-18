// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./AbsRollupEventInbox.t.sol";
import {TestUtil} from "./util/TestUtil.sol";
import {RollupEventInbox, IRollupEventInbox} from "../../src/rollup/RollupEventInbox.sol";
import {Bridge, IOwnable, IEthBridge} from "../../src/bridge/Bridge.sol";

contract RollupEventInboxTest is AbsRollupEventInboxTest {
    function setUp() public {
        rollupEventInbox = IRollupEventInbox(TestUtil.deployProxy(address(new RollupEventInbox())));
        bridge = IBridge(TestUtil.deployProxy(address(new Bridge())));
        IEthBridge(address(bridge)).initialize(IOwnable(rollup));

        rollupEventInbox.initialize(bridge);
    }

    /* solhint-disable func-name-mixedcase */
    function test_initialize_revert_ZeroInit() public {
        RollupEventInbox rollupEventInbox =
            RollupEventInbox(TestUtil.deployProxy(address(new RollupEventInbox())));

        vm.expectRevert(HadZeroInit.selector);
        rollupEventInbox.initialize(IBridge(address(0)));
    }
}
