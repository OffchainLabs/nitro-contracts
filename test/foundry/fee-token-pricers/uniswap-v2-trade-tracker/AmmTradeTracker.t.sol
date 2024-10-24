// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {AmmTradeTracker, IUniswapV2Router01, IERC20} from "./AmmTradeTracker.sol";
import "../../../../src/bridge/SequencerInbox.sol";
import {ERC20Bridge} from "../../../../src/bridge/ERC20Bridge.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

import "../../util/TestUtil.sol";

contract AmmTradeTrackerTest is Test {
    AmmTradeTracker public tradeTracker;
    address public owner = makeAddr("tradeTrackerOwner");
    address public batchPosterOperator = makeAddr("batchPosterOperator");

    address public constant V2_ROUTER_ARB1 = address(0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24);
    address public constant USDC_ARB1 = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    uint256 public constant DEFAULT_EXCHANGE_RATE = 2500e18;
    uint256 public constant DEFAULT_CALLDATA_COST = 12;

    function setUp() public {
        vm.prank(owner);
        tradeTracker = new AmmTradeTracker(
            IUniswapV2Router01(V2_ROUTER_ARB1),
            USDC_ARB1,
            DEFAULT_EXCHANGE_RATE,
            DEFAULT_CALLDATA_COST
        );
    }

    function testOnGasSpent() public {
        (SequencerInbox seqInbox,) = _deployFeeTokenRollup();
        vm.prank(owner);
        tradeTracker.allowCaller(address(seqInbox), true);

        uint256 gasUsed = 300_000;
        uint256 calldataSize = 10_000;
        vm.prank(address(seqInbox));
        tradeTracker.onGasSpent(payable(batchPosterOperator), gasUsed, calldataSize);
    }

    function _deployFeeTokenRollup() internal returns (SequencerInbox, ERC20Bridge) {
        RollupMock rollupMock = new RollupMock(owner);
        ERC20Bridge bridgeImpl = new ERC20Bridge();
        address proxyAdmin = makeAddr("proxyAdmin");
        ERC20Bridge bridge = ERC20Bridge(
            address(new TransparentUpgradeableProxy(address(bridgeImpl), proxyAdmin, ""))
        );
        address nativeToken = address(new ERC20PresetMinterPauser("Appchain Token", "App"));

        bridge.initialize(IOwnable(address(rollupMock)), nativeToken);
        vm.prank(owner);
        bridge.setDelayedInbox(makeAddr("inbox"), true);

        /// this will result in 'hostChainIsArbitrum = true'
        vm.mockCall(
            address(100),
            abi.encodeWithSelector(ArbSys.arbOSVersion.selector),
            abi.encode(uint256(11))
        );
        uint256 maxDataSize = 10_000;
        SequencerInbox seqInboxImpl = new SequencerInbox(maxDataSize, IReader4844(address(0)), true);
        SequencerInbox seqInbox = SequencerInbox(
            address(new TransparentUpgradeableProxy(address(seqInboxImpl), proxyAdmin, ""))
        );
        ISequencerInbox.MaxTimeVariation memory maxTimeVariation = ISequencerInbox.MaxTimeVariation({
            delayBlocks: 10,
            futureBlocks: 10,
            delaySeconds: 100,
            futureSeconds: 100
        });
        seqInbox.initialize(bridge, maxTimeVariation, IFeeTokenPricer(tradeTracker));

        vm.prank(owner);
        seqInbox.setIsBatchPoster(batchPosterOperator, true);

        vm.prank(owner);
        bridge.setSequencerInbox(address(seqInbox));

        return (seqInbox, bridge);
    }
}

contract RollupMock {
    address public immutable owner;

    constructor(address _owner) {
        owner = _owner;
    }
}
