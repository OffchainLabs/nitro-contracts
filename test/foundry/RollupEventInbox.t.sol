// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./AbsRollupEventInbox.t.sol";
import {TestUtil} from "./util/TestUtil.sol";
import {RollupEventInbox, IRollupEventInbox} from "../../src/rollup/RollupEventInbox.sol";
import {Bridge, IOwnable, IEthBridge} from "../../src/bridge/Bridge.sol";
import "../../src/libraries/MessageTypes.sol";

contract RollupEventInboxTest is AbsRollupEventInboxTest {
    function setUp() public {
        rollupEventInbox = IRollupEventInbox(TestUtil.deployProxy(address(new RollupEventInbox())));

        bridge = IBridge(TestUtil.deployProxy(address(new Bridge())));
        IEthBridge(address(bridge)).initialize(IOwnable(rollup));

        vm.prank(rollup);
        bridge.setDelayedInbox(address(rollupEventInbox), true);

        rollupEventInbox.initialize(bridge);
    }

    /* solhint-disable func-name-mixedcase */
    function test_initialize_revert_ZeroInit() public {
        RollupEventInbox rollupEventInbox =
            RollupEventInbox(TestUtil.deployProxy(address(new RollupEventInbox())));

        vm.expectRevert(HadZeroInit.selector);
        rollupEventInbox.initialize(IBridge(address(0)));
    }

    function test_rollupInitialized_NonArbitrumHosted() public {
        uint256 chainId = 123;
        string memory chainConfig = "chainConfig";

        // 80 gwei basefee
        uint256 basefee = 80_000_000_000;
        vm.fee(basefee);

        uint8 expectedInitMsgVersion = 1;
        uint256 expectedCurrentDataCost = basefee;
        bytes memory expectedInitMsg =
            abi.encodePacked(chainId, expectedInitMsgVersion, expectedCurrentDataCost, chainConfig);

        // expect event
        vm.expectEmit(true, true, true, true);
        emit MessageDelivered(
            0,
            bytes32(0),
            address(rollupEventInbox),
            INITIALIZATION_MSG_TYPE,
            address(0),
            keccak256(expectedInitMsg),
            basefee,
            uint64(block.timestamp)
        );

        vm.expectEmit(true, true, true, true);
        emit InboxMessageDelivered(0, expectedInitMsg);

        vm.prank(rollup);
        rollupEventInbox.rollupInitialized(chainId, chainConfig);
    }

    function test_rollupInitialized_ArbitrumHosted() public {
        uint256 chainId = 1234;
        string memory chainConfig = "chainConfig2";

        // 0.35 gwei basefee
        uint256 l2Fee = 350_000_000;
        vm.fee(l2Fee);

        // 50 gwei L1 basefee
        uint256 l1Fee = 50_000_000_000;
        vm.mockCall(
            address(0x6c), abi.encodeWithSignature("getL1BaseFeeEstimate()"), abi.encode(l1Fee)
        );

        uint8 expectedInitMsgVersion = 1;
        uint256 expectedCurrentDataCost = l2Fee + l1Fee;
        bytes memory expectedInitMsg =
            abi.encodePacked(chainId, expectedInitMsgVersion, expectedCurrentDataCost, chainConfig);

        /// this will result in 'hostChainIsArbitrum = true'
        vm.mockCall(
            address(100),
            abi.encodeWithSelector(ArbSys.arbOSVersion.selector),
            abi.encode(uint256(11))
        );

        // expect event
        vm.expectEmit(true, true, true, true);
        emit MessageDelivered(
            0,
            bytes32(0),
            address(rollupEventInbox),
            INITIALIZATION_MSG_TYPE,
            address(0),
            keccak256(expectedInitMsg),
            l2Fee,
            uint64(block.timestamp)
        );

        vm.expectEmit(true, true, true, true);
        emit InboxMessageDelivered(0, expectedInitMsg);

        vm.prank(rollup);
        rollupEventInbox.rollupInitialized(chainId, chainConfig);
    }
}
