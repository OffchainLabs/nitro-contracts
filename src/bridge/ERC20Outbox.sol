// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.4;

import "./AbsOutbox.sol";
import {IERC20Bridge} from "./IERC20Bridge.sol";
import {DecimalsConverterHelper} from "../libraries/DecimalsConverterHelper.sol";

contract ERC20Outbox is AbsOutbox {
    function l2ToL1WithdrawalAmount() external view returns (uint256) {
        return contextWithdrawalAmount;
    }

    /// @inheritdoc AbsOutbox
    function _getAmountToUnlock(
        uint256 value
    ) internal view override returns (uint256) {
        uint8 nativeTokenDecimals = IERC20Bridge(address(bridge)).nativeTokenDecimals();
        // this might revert due to overflow, but we assume the token supply is less than 2^256
        return DecimalsConverterHelper.adjustDecimals(value, 18, nativeTokenDecimals);
    }

    /// @inheritdoc AbsOutbox
    function _amountToSetInContext(
        uint256 value
    ) internal pure override returns (uint256) {
        // native token withdrawal amount which can be fetched from context
        return value;
    }
}
