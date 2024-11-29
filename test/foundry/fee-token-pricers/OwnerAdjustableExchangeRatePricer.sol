// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IFeeTokenPricer} from "../../../src/bridge/ISequencerInbox.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Test implementation of a fee token pricer that returns an exchange rate set by the owner
 * @notice Exchange rate can be changed by the owner at any time, without any restrictions
 */
contract OwnerAdjustableExchangeRatePricer is IFeeTokenPricer, Ownable {
    uint256 public exchangeRate;

    event ExchangeRateSet(uint256 newExchangeRate);

    constructor(
        uint256 initialExchangeRate
    ) Ownable() {
        exchangeRate = initialExchangeRate;
        emit ExchangeRateSet(initialExchangeRate);
    }

    function setExchangeRate(
        uint256 _exchangeRate
    ) external onlyOwner {
        exchangeRate = _exchangeRate;
        emit ExchangeRateSet(_exchangeRate);
    }

    // @inheritdoc IFeeTokenPricer
    function getExchangeRate() external view returns (uint256) {
        return exchangeRate;
    }
}
