// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {AmmTradeTracker, IUniswapV2Router01, IERC20} from "./AmmTradeTracker.sol";
import "../../../../src/bridge/SequencerInbox.sol";
import {ERC20Bridge} from "../../../../src/bridge/ERC20Bridge.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

import "../../util/TestUtil.sol";

contract AmmTradeTrackerForkTest is Test {
    AmmTradeTracker public tradeTracker;
    address public owner = makeAddr("tradeTrackerOwner");
    address public batchPosterOperator = makeAddr("batchPosterOperator");

    address public constant V2_ROUTER_ARB1 = address(0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24);
    address public constant USDC_ARB1 = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    uint256 public constant DEFAULT_EXCHANGE_RATE = 2500e18;
    uint256 public constant DEFAULT_CALLDATA_COST = 12;

    function setUp() public {
        string memory arbRpc = vm.envString("ARB_RPC");
        vm.createSelectFork(arbRpc, 261_666_155);

        vm.prank(owner);
        tradeTracker = new AmmTradeTracker(
            IUniswapV2Router01(V2_ROUTER_ARB1),
            USDC_ARB1,
            DEFAULT_EXCHANGE_RATE,
            DEFAULT_CALLDATA_COST
        );
    }

    function testFork_CanSwapTokenToEth() public {
        uint256 usdcAmount = 250e6;
        uint256 minEthReceived = 0.1 ether;

        uint256 ethReceived = _swapTokenToEth(usdcAmount, minEthReceived);

        assertGe(ethReceived, minEthReceived);
        assertEq(tradeTracker.ethAccumulatorPerSpender(batchPosterOperator), ethReceived);
        assertEq(tradeTracker.tokenAccumulatorPerSpender(batchPosterOperator), usdcAmount);
    }

    function testFork_GetExchangeRate() public {
        assertEq(tradeTracker.getExchangeRate(), DEFAULT_EXCHANGE_RATE);

        uint256 usdcAmount = 250e6;
        uint256 minEthReceived = 0.1 ether;
        uint256 ethReceived = _swapTokenToEth(usdcAmount, minEthReceived);

        vm.prank(batchPosterOperator, batchPosterOperator);
        uint256 actualExchangeRate = tradeTracker.getExchangeRate();
        uint256 expectedExchangeRate = (usdcAmount * 1e30) / ethReceived;
        assertEq(actualExchangeRate, expectedExchangeRate);
    }

    function testFork_postBatch() public {
        (SequencerInbox seqInbox,) = _deployFeeTokenRollup();
        vm.prank(owner);
        tradeTracker.allowCaller(address(seqInbox), true);

        // swap some tokens
        uint256 usdcAmount = 250e6;
        uint256 minEthReceived = 0.1 ether;
        _swapTokenToEth(usdcAmount, minEthReceived);

        // snapshot values before batch has been posted
        uint256 ethAccBefore = tradeTracker.ethAccumulatorPerSpender(batchPosterOperator);
        uint256 tokenAccBefore = tradeTracker.tokenAccumulatorPerSpender(batchPosterOperator);
        vm.prank(batchPosterOperator, batchPosterOperator);
        uint256 exchangeRateBefore = tradeTracker.getExchangeRate();

        // set 0.1 gwei basefee and 30 gwei TX L1 fees
        uint256 basefee = 100_000_000;
        vm.fee(basefee);
        uint256 l1Fees = 30_000_000_000;
        vm.mockCall(
            address(0x6c), abi.encodeWithSignature("getCurrentTxL1GasFees()"), abi.encode(l1Fees)
        );

        // post batch
        address feeTokenPricer = address(seqInbox.feeTokenPricer());
        bytes memory batchData = hex"80567890";
        vm.prank(batchPosterOperator, batchPosterOperator);
        seqInbox.addSequencerL2BatchFromOrigin(0, batchData, 0, IGasRefunder(feeTokenPricer), 0, 1);

        // snapshot values after batch has been posted
        uint256 ethAccAfter = tradeTracker.ethAccumulatorPerSpender(batchPosterOperator);
        uint256 tokenAccAfter = tradeTracker.tokenAccumulatorPerSpender(batchPosterOperator);
        vm.prank(batchPosterOperator, batchPosterOperator);
        uint256 exchangeRateAfter = tradeTracker.getExchangeRate();

        // checks
        assertTrue(ethAccAfter < ethAccBefore);
        assertTrue(tokenAccAfter < tokenAccBefore);
        assertTrue(exchangeRateAfter != exchangeRateBefore);
    }

    // function testFork_postMultipleBatches() public {
    //     (SequencerInbox seqInbox,) = _deployFeeTokenRollup();
    //     vm.prank(owner);
    //     tradeTracker.allowCaller(address(seqInbox), true);

    //     // swap some tokens
    //     uint256 usdcAmount = 250e6;
    //     uint256 minEthReceived = 0.1 ether;
    //     uint256 ethReceived = _swapTokenToEth(usdcAmount, minEthReceived);

    //     console.log("Swapped 250e6 USDC for ", ethReceived, " ETH");

    //     // snapshot values before batch has been posted
    //     uint256 ethAccBefore = tradeTracker.ethAccumulatorPerSpender(batchPosterOperator);
    //     uint256 tokenAccBefore = tradeTracker.tokenAccumulatorPerSpender(batchPosterOperator);
    //     vm.prank(batchPosterOperator, batchPosterOperator);
    //     uint256 exchangeRateBefore = tradeTracker.getExchangeRate();

    //     console.log("ethAccBefore: ", ethAccBefore);
    //     console.log("tokenAccBefore: ", tokenAccBefore);
    //     console.log("exchangeRateBefore: ", exchangeRateBefore);

    //     // set 0.1 gwei basefee and 30 gwei TX L1 fees
    //     uint256 basefee = 100_000_000;
    //     vm.fee(basefee);
    //     uint256 l1Fees = 30_000_000_000;
    //     vm.mockCall(
    //         address(0x6c), abi.encodeWithSignature("getCurrentTxL1GasFees()"), abi.encode(l1Fees)
    //     );

    //     // post batch
    //     address feeTokenPricer = address(seqInbox.feeTokenPricer());
    //     bytes memory batchData = hex"80567890";
    //     vm.prank(batchPosterOperator, batchPosterOperator);
    //     seqInbox.addSequencerL2BatchFromOrigin(0, batchData, 0, IGasRefunder(feeTokenPricer), 0, 1);

    //     // snapshot values after batch has been posted
    //     uint256 ethAccAfter = tradeTracker.ethAccumulatorPerSpender(batchPosterOperator);
    //     uint256 tokenAccAfter = tradeTracker.tokenAccumulatorPerSpender(batchPosterOperator);
    //     vm.prank(batchPosterOperator, batchPosterOperator);
    //     uint256 exchangeRateAfter = tradeTracker.getExchangeRate();

    //     console.log("-----------");
    //     console.log("ethAccAfter: ", ethAccAfter);
    //     console.log("tokenAccAfter: ", tokenAccAfter);
    //     console.log("exchangeRateAfter: ", exchangeRateAfter);

    //     vm.prank(batchPosterOperator, batchPosterOperator);
    //     seqInbox.addSequencerL2BatchFromOrigin(1, batchData, 0, IGasRefunder(feeTokenPricer), 0, 1);

    //     uint256 ethAccEnd = tradeTracker.ethAccumulatorPerSpender(batchPosterOperator);
    //     uint256 tokenAccEnd = tradeTracker.tokenAccumulatorPerSpender(batchPosterOperator);
    //     vm.prank(batchPosterOperator, batchPosterOperator);
    //     uint256 exchangeRateEnd = tradeTracker.getExchangeRate();

    //     console.log("-----------");
    //     console.log("ethAccEnd: ", ethAccEnd);
    //     console.log("tokenAccEnd: ", tokenAccEnd);
    //     console.log("exchangeRateEnd: ", exchangeRateEnd);
    // }

    function _swapTokenToEth(uint256 tokenAmount, uint256 minEthReceived)
        internal
        returns (uint256 ethReceived)
    {
        deal(USDC_ARB1, batchPosterOperator, tokenAmount);

        vm.startPrank(batchPosterOperator, batchPosterOperator);
        IERC20(USDC_ARB1).approve(address(tradeTracker), tokenAmount);
        ethReceived =
            tradeTracker.swapTokenToEth(tokenAmount, minEthReceived, block.timestamp + 100);
        vm.stopPrank();
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
