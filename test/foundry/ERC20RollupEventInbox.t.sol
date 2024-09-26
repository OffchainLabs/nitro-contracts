// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./AbsRollupEventInbox.t.sol";
import {TestUtil} from "./util/TestUtil.sol";
import {ERC20RollupEventInbox} from "../../src/rollup/ERC20RollupEventInbox.sol";
import {ERC20Bridge, IERC20Bridge, IOwnable} from "../../src/bridge/ERC20Bridge.sol";
import {
    SequencerInbox,
    ISequencerInbox,
    IReader4844,
    IFeeTokenPricer
} from "../../src/bridge/SequencerInbox.sol";
import {ERC20PresetMinterPauser} from
    "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract ERC20RollupEventInboxTest is AbsRollupEventInboxTest {
    function setUp() public {
        rollupEventInbox =
            IRollupEventInbox(TestUtil.deployProxy(address(new ERC20RollupEventInbox())));
        bridge = IBridge(TestUtil.deployProxy(address(new ERC20Bridge())));
        address nativeToken = address(new ERC20PresetMinterPauser("Appchain Token", "App"));
        IERC20Bridge(address(bridge)).initialize(IOwnable(rollup), nativeToken);

        vm.prank(rollup);
        bridge.setDelayedInbox(address(rollupEventInbox), true);

        rollupEventInbox.initialize(bridge);
    }

    /* solhint-disable func-name-mixedcase */
    function test_initialize_revert_ZeroInit() public {
        ERC20RollupEventInbox rollupEventInbox =
            ERC20RollupEventInbox(TestUtil.deployProxy(address(new ERC20RollupEventInbox())));

        vm.expectRevert(HadZeroInit.selector);
        rollupEventInbox.initialize(IBridge(address(0)));
    }

    function test_rollupInitialized_ArbitrumHosted() public {
        _setSequencerInbox(true);

        uint256 chainId = 400;
        string memory chainConfig = "chainConfig";

        uint8 expectedInitMsgVersion = 1;
        uint256 exchangeRate = 3.15e18;
        uint256 expectedCurrentDataCost = _calculateExpectedCurrentDataCost(exchangeRate, true);
        bytes memory expectedInitMsg =
            abi.encodePacked(chainId, expectedInitMsgVersion, expectedCurrentDataCost, chainConfig);

        /// expect event
        vm.expectEmit(true, true, true, true);
        emit MessageDelivered(
            0,
            bytes32(0),
            address(rollupEventInbox),
            INITIALIZATION_MSG_TYPE,
            address(0),
            keccak256(expectedInitMsg),
            uint256(0),
            uint64(block.timestamp)
        );

        vm.expectEmit(true, true, true, true);
        emit InboxMessageDelivered(0, expectedInitMsg);

        /// this will result in 'hostChainIsArbitrum = true'
        vm.mockCall(
            address(100),
            abi.encodeWithSelector(ArbSys.arbOSVersion.selector),
            abi.encode(uint256(11))
        );

        vm.prank(rollup);
        rollupEventInbox.rollupInitialized(chainId, chainConfig);
    }

    function test_rollupInitialized_NonArbitrumHosted() public {
        _setSequencerInbox(false);

        uint256 chainId = 500;
        string memory chainConfig = "chainConfig2";

        uint8 expectedInitMsgVersion = 1;
        uint256 expectedCurrentDataCost = _calculateExpectedCurrentDataCost(3e18, false);
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
            uint256(0),
            uint64(block.timestamp)
        );

        vm.expectEmit(true, true, true, true);
        emit InboxMessageDelivered(0, expectedInitMsg);

        vm.prank(rollup);
        rollupEventInbox.rollupInitialized(chainId, chainConfig);
    }

    function _calculateExpectedCurrentDataCost(uint256 exchangeRate, bool isArbHosted)
        internal
        returns (uint256)
    {
        // 7 gwei basefee
        uint256 l2Fee = 7_000_000_000;
        vm.fee(l2Fee);

        uint256 l1Fee = 0;
        if (isArbHosted) {
            // 80 gwei L1 basefee
            l1Fee = 80_000_000_000;
            vm.mockCall(
                address(0x6c), abi.encodeWithSignature("getL1BaseFeeEstimate()"), abi.encode(l1Fee)
            );
        }

        // convert from eth to fee token
        vm.mockCall(
            address(ISequencerInbox(rollupEventInbox.bridge().sequencerInbox()).feeTokenPricer()),
            abi.encodeWithSelector(IFeeTokenPricer.getExchangeRate.selector),
            abi.encode(exchangeRate)
        );

        uint256 expectedCurrentDataCost = ((l2Fee + l1Fee) * exchangeRate) / 1e18;

        return expectedCurrentDataCost;
    }

    function _setSequencerInbox(bool isArbHosted) internal {
        IReader4844 reader = IReader4844(makeAddr("reader"));
        if (isArbHosted) {
            reader = IReader4844(address(0));
            vm.mockCall(
                address(100),
                abi.encodeWithSelector(ArbSys.arbOSVersion.selector),
                abi.encode(uint256(11))
            );
        }

        SequencerInbox si =
            SequencerInbox(TestUtil.deployProxy(address(new SequencerInbox(10_000, reader, true))));
        si.initialize(
            bridge,
            ISequencerInbox.MaxTimeVariation({
                delayBlocks: 10,
                futureBlocks: 10,
                delaySeconds: 100,
                futureSeconds: 100
            }),
            IFeeTokenPricer(makeAddr("feeTokenPricer"))
        );

        vm.prank(rollup);
        bridge.setSequencerInbox(address(si));
    }
}
