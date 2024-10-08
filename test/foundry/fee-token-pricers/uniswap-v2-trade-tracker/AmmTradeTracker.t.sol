// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {AmmTradeTracker, IUniswapV2Router01, IERC20} from "./AmmTradeTracker.sol";

contract AmmTradeTrackerTest is Test {
    AmmTradeTracker public tradeTracker;
    address public owner = makeAddr("tradeTrackerOwner");
    address public batchPosterOperator = makeAddr("batchPosterOperator");

    address public constant V2_ROUTER_ARB1 = address(0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24);
    address public constant USDC_ARB1 = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    uint256 public constant DEFAULT_EXCHANGE_RATE = 2500e18;

    function setUp() public {
        vm.createSelectFork(vm.envString("ARB"), 261_666_155);
        console.log(vm.envString("ARB"));

        vm.prank(owner);
        tradeTracker = new AmmTradeTracker(
            IUniswapV2Router01(V2_ROUTER_ARB1), USDC_ARB1, DEFAULT_EXCHANGE_RATE
        );
    }

    function testFork_CanSwapTokenToEth() public {
        uint256 usdcAmount = 250e6;
        uint256 minEthReceived = 0.1 ether;

        deal(USDC_ARB1, batchPosterOperator, usdcAmount);

        vm.startPrank(batchPosterOperator);
        IERC20(USDC_ARB1).approve(address(tradeTracker), usdcAmount);
        uint256 ethReceived = tradeTracker.swapTokenToEth(usdcAmount, minEthReceived);
        vm.stopPrank();

        assertEq(tradeTracker.ethAccumulatorPerSpender(batchPosterOperator), ethReceived);
        assertEq(tradeTracker.tokenAccumulatorPerSpender(batchPosterOperator), usdcAmount);
    }
}
