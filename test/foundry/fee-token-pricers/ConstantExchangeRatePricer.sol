// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IFeeTokenPricer} from "../../../src/bridge/ISequencerInbox.sol";

/**
 * @title Test implementation of a fee token pricer that returns a constant exchange rate
 * @notice Exchange rate is set in constructor and cannot be changed
 */
contract ConstantExchangeRatePricer is IFeeTokenPricer {
    uint256 immutable exchangeRate;

    constructor(
        uint256 _exchangeRate
    ) {
        exchangeRate = _exchangeRate;
    }

    // @inheritdoc IFeeTokenPricer
    function getExchangeRate() external view returns (uint256) {
        return exchangeRate;
    }
}
