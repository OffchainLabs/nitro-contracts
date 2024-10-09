// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IFeeTokenPricer} from "../../../../src/bridge/ISequencerInbox.sol";
import {IGasRefunder} from "../../../../src/libraries/IGasRefunder.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Test implementation of a fee token pricer that trades on AMM and keeps track of traded amount to calculate exchange rate
 */
contract AmmTradeTracker is IFeeTokenPricer, IGasRefunder, Ownable {
    using SafeERC20 for IERC20;

    IUniswapV2Router01 public immutable router;
    address public immutable token;
    address public immutable weth;
    uint8 public immutable tokenDecimals;

    mapping(address => uint256) public ethAccumulatorPerSpender;
    mapping(address => uint256) public tokenAccumulatorPerSpender;

    uint256 public defaultExchangeRate;
    uint256 public calldataCost;

    constructor(
        IUniswapV2Router01 _router,
        address _token,
        uint256 _defaultExchangeRate,
        uint256 _calldataCost
    ) Ownable() {
        router = _router;
        token = _token;
        weth = _router.WETH();

        defaultExchangeRate = _defaultExchangeRate;
        calldataCost = _calldataCost;
        tokenDecimals = ERC20(_token).decimals();

        IERC20(token).safeApprove(address(router), type(uint256).max);
    }

    // @inheritdoc IFeeTokenPricer
    function getExchangeRate() external view returns (uint256) {
        return _getExchangeRate();
    }

    function swapTokenToEth(uint256 tokenAmount, uint256 minEthReceived)
        external
        returns (uint256 ethReceived)
    {
        IERC20(token).safeTransferFrom(msg.sender, address(this), tokenAmount);

        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = weth;

        uint256[] memory amounts = router.swapExactTokensForETH({
            amountIn: tokenAmount,
            amountOutMin: minEthReceived,
            path: path,
            to: msg.sender,
            deadline: block.timestamp
        });
        ethReceived = amounts[amounts.length - 1];

        ethAccumulatorPerSpender[msg.sender] += ethReceived;
        tokenAccumulatorPerSpender[msg.sender] += tokenAmount;
    }

    function onGasSpent(address payable spender, uint256 gasUsed, uint256 calldataSize)
        external
        returns (bool)
    {
        // update internal state
        uint256 exchangeRateUsed = _getExchangeRate();
        if (exchangeRateUsed != 0) {
            // calculate amount of ETH spent
            gasUsed += calldataSize * calldataCost;
            uint256 ethDelta = gasUsed * block.basefee;

            // calculate amount of token spent to purchase ethDelta
            uint256 ethAcc = ethAccumulatorPerSpender[spender];
            if (ethAcc == 0) {
                return true;
            }
            uint256 tokenAcc = tokenAccumulatorPerSpender[spender];
            uint256 tokenDelta = (ethDelta * tokenAcc) / ethAcc;

            if (ethDelta > ethAcc) {
                ethAccumulatorPerSpender[spender] = 0;
            } else {
                ethAccumulatorPerSpender[spender] -= ethDelta;
            }

            if (tokenDelta > tokenAcc) {
                tokenAccumulatorPerSpender[spender] = 0;
            } else {
                tokenAccumulatorPerSpender[spender] -= tokenDelta;
            }
        }

        return true;
    }

    function setDefaultExchangeRate(uint256 _defaultExchangeRate) external onlyOwner {
        defaultExchangeRate = _defaultExchangeRate;
    }

    function setCalldataCost(uint256 _calldataCost) external onlyOwner {
        calldataCost = _calldataCost;
    }

    function _getExchangeRate() internal view returns (uint256) {
        uint256 ethAcc = ethAccumulatorPerSpender[tx.origin];
        if (ethAcc == 0) {
            return defaultExchangeRate;
        }
        uint256 tokenAcc = tokenAccumulatorPerSpender[tx.origin];

        return (_scaleTo18Decimals(tokenAcc) * 1e18) / ethAcc;
    }

    function _scaleTo18Decimals(uint256 amount) internal view returns (uint256) {
        if (tokenDecimals == 18) {
            return amount;
        } else if (tokenDecimals < 18) {
            return amount * 10 ** (18 - tokenDecimals);
        } else {
            return amount / 10 ** (tokenDecimals - 18);
        }
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
