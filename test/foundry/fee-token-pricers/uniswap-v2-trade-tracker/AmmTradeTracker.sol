// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IFeeTokenPricer} from "../../../../src/bridge/ISequencerInbox.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Test implementation of a fee token pricer that trades on AMM and keeps track of trades
 */
contract AmmTradeTracker is IFeeTokenPricer, Ownable {
    IUniswapV2Router01 public immutable router;
    address public immutable token;
    address public immutable weth;

    uint256 public totalEthReceived;
    uint256 public totalTokenSpent;

    constructor(IUniswapV2Router01 _router, address _token) Ownable() {
        router = _router;
        token = _token;
        weth = _router.WETH();

        IERC20(token).approve(address(router), type(uint256).max);
    }

    // @inheritdoc IFeeTokenPricer
    function getExchangeRate() external view returns (uint256) {
        // todo - scale for decimals to get 1e18 denominator
        return totalTokenSpent * 1e18 / totalEthReceived;
    }

    function swapTokenToEth(uint256 tokenAmount) external onlyOwner {
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = weth;

        // todo - properly calculate slippage
        uint256 amountOutMin = 1;
        uint256[] memory amounts = router.swapExactTokensForETH({
            amountIn: tokenAmount,
            amountOutMin: amountOutMin,
            path: path,
            to: msg.sender,
            deadline: block.timestamp
        });
        uint256 ethReceived = amounts[amounts.length - 1];

        totalEthReceived += ethReceived;
        totalTokenSpent += tokenAmount;
    }
}

interface IUniswapV2Router01 {
    function WETH() external pure returns (address);
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface IERC20 {
    function approve(address spender, uint256 value) external returns (bool);
}
