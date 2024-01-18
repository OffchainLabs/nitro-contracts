// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./AbsRollupEventInbox.t.sol";
import {TestUtil} from "./util/TestUtil.sol";
import {ERC20RollupEventInbox} from "../../src/rollup/ERC20RollupEventInbox.sol";
import {ERC20Bridge, IERC20Bridge, IOwnable} from "../../src/bridge/ERC20Bridge.sol";

contract ERC20RollupEventInboxTest is AbsRollupEventInboxTest {
    function setUp() public {
        rollupEventInbox =
            IRollupEventInbox(TestUtil.deployProxy(address(new ERC20RollupEventInbox())));
        bridge = IBridge(TestUtil.deployProxy(address(new ERC20Bridge())));
        IERC20Bridge(address(bridge)).initialize(IOwnable(rollup), makeAddr("nativeToken"));

        rollupEventInbox.initialize(bridge);
    }

    /* solhint-disable func-name-mixedcase */
    function test_initialize_revert_ZeroInit() public {
        ERC20RollupEventInbox rollupEventInbox =
            ERC20RollupEventInbox(TestUtil.deployProxy(address(new ERC20RollupEventInbox())));

        vm.expectRevert(HadZeroInit.selector);
        rollupEventInbox.initialize(IBridge(address(0)));
    }
}
