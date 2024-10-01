// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IFeeTokenPricer} from "../../../src/bridge/ISequencerInbox.sol";
import "@uniswap/v2-core/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/interfaces/IUniswapV2Pair.sol";
import "@uniswap/lib/libraries/FixedPoint.sol";

/**
 * @title Test implementation of a fee token pricer that returns a constant exchange rate
 * @notice Exchange rate is set in constructor and cannot be changed
 */
contract UniswapV2TwapPricer is IFeeTokenPricer {
    uint256 public constant TWAP_WINDOW = 1 hours;

    IUniswapV2Pair immutable pair;
    address public immutable token0;
    address public immutable token1;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint32 public pricerUpdatedAt;

    FixedPoint.uq112x112 public price0Average;
    FixedPoint.uq112x112 public price1Average;

    constructor(IUniswapV2Pair _pair) {
        pair = _pair;
        token0 = _pair.token0();
        token1 = _pair.token1();
        price0CumulativeLast = _pair.price0CumulativeLast();
        price1CumulativeLast = _pair.price1CumulativeLast();
        uint112 reserve0;
        uint112 reserve1;
        (reserve0, reserve1, pricerUpdatedAt) = _pair.getReserves();
        require(reserve0 != 0 && reserve1 != 0, "No reserves"); // ensure that there's liquidity in the pair
    }

    // @inheritdoc IFeeTokenPricer
    function getExchangeRate() external view returns (uint256) {
        uint32 currentBlockTimestamp = uint32(block.timestamp);
        uint32 timeElapsed = currentBlockTimestamp - pricerUpdatedAt;

        if (timeElapsed >= TWAP_WINDOW) {
            _update();
        }

        // calculate exchange rate

        return 0;
    }

    function update() external {
        uint32 currentBlockTimestamp = uint32(block.timestamp);
        uint32 timeElapsed = currentBlockTimestamp - pricerUpdatedAt;
        require(timeElapsed >= TWAP_WINDOW, "Minimum TWAP window not elapsed");

        _update();
    }

    function _update() internal {
        uint32 currentBlockTimestamp = uint32(block.timestamp);
        uint32 timeElapsed = currentBlockTimestamp - pricerUpdatedAt;

        // fetch latest cumulative price accumulators
        IUniswapV2Pair _pair = pair;
        uint256 price0Cumulative = _pair.price0CumulativeLast();
        uint256 price1Cumulative = _pair.price1CumulativeLast();

        // add the current price if prices haven't been updated in this block
        (uint112 reserve0, uint112 reserve1, uint32 pairUpdatedAt) =
            IUniswapV2Pair(pair).getReserves();
        if (pairUpdatedAt != currentBlockTimestamp) {
            uint256 delta = currentBlockTimestamp - pairUpdatedAt;
            unchecked {
                price0Cumulative += uint256(FixedPoint.fraction(reserve1, reserve0)._x) * delta;
                price1Cumulative += uint256(FixedPoint.fraction(reserve0, reserve1)._x) * delta;
            }
        }

        // overflow is desired, casting never truncates
        // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
        price0Average =
            FixedPoint.uq112x112(uint224((price0Cumulative - price0CumulativeLast) / timeElapsed));
        price1Average =
            FixedPoint.uq112x112(uint224((price1Cumulative - price1CumulativeLast) / timeElapsed));

        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        pricerUpdatedAt = currentBlockTimestamp;
    }
}
