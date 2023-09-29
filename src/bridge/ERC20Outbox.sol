// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/nitro/blob/master/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.4;

import "./AbsOutbox.sol";
import {IERC20Bridge} from "./IERC20Bridge.sol";
import {DecimalsConverterHelper} from "../libraries/DecimalsConverterHelper.sol";
import {AmountTooLarge, NativeTokenDecimalsTooLarge} from "../libraries/Error.sol";

contract ERC20Outbox is AbsOutbox {
    // number of decimals used by native token
    uint8 public nativeTokenDecimals;

    // it is assumed that arb-os never assigns this value to a valid leaf to be redeemed
    uint256 private constant AMOUNT_DEFAULT_CONTEXT = type(uint256).max;

    // If nativeTokenDecimals is different than 18 decimals, bridge will inflate or deflate token amounts
    // when depositing to child chain to match 18 decimal denomination. Opposite process happens when
    // amount is withdrawn back to parent chain. In order to avoid uint256 overflows we restrict max number
    // of decimals to 36 which should be enough for most practical use-cases.
    uint8 public constant MAX_ALLOWED_NATIVE_TOKEN_DECIMALS = uint8(36);

    // Max amount that can be moved from parent chain to child chain. Also the max amount that can be
    // claimed on parent chain after withdrawing it from child chain. Amounts higher than this would
    // risk uint256 overflows.
    uint256 public constant MAX_BRIDGEABLE_AMOUNT = type(uint256).max / 10**18;

    function initialize(IBridge _bridge) external onlyDelegated {
        __AbsOutbox_init(_bridge);

        // store number of decimals used by native token
        address nativeToken = IERC20Bridge(address(bridge)).nativeToken();
        nativeTokenDecimals = DecimalsConverterHelper.getDecimals(nativeToken);
        if (nativeTokenDecimals > MAX_ALLOWED_NATIVE_TOKEN_DECIMALS) {
            revert NativeTokenDecimalsTooLarge(nativeTokenDecimals);
        }
    }

    function l2ToL1WithdrawalAmount() external view returns (uint256) {
        uint256 amount = context.withdrawalAmount;
        if (amount == AMOUNT_DEFAULT_CONTEXT) return 0;
        return amount;
    }

    /// @inheritdoc AbsOutbox
    function _defaultContextAmount() internal pure override returns (uint256) {
        // we use type(uint256).max as representation of 0 native token withdrawal amount
        return AMOUNT_DEFAULT_CONTEXT;
    }

    /// @inheritdoc AbsOutbox
    function _getAmountToUnlock(uint256 value) internal view override returns (uint256) {
        // make sure that inflated amount does not overflow uint256
        if (nativeTokenDecimals > 18) {
            if (value > MAX_BRIDGEABLE_AMOUNT) {
                revert AmountTooLarge(value);
            }
        }

        return DecimalsConverterHelper.adjustDecimals(value, 18, nativeTokenDecimals);
    }

    /// @inheritdoc AbsOutbox
    function _amountToSetInContext(uint256 value) internal pure override returns (uint256) {
        // native token withdrawal amount which can be fetched from context
        return value;
    }
}
