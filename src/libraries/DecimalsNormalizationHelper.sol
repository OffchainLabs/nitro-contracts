// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import {BytesLib} from "./BytesLib.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

library DecimalsNormalizationHelper {
    /// @notice normalize the amount as if token had 18 decimals.
    /// @dev Ie. let's say amount is 752. If token has 16 decimals normalized
    ///      amount is 75200. If token has 20 decimals normalized amount is 7.
    ///      If token uses no decimals normalized amount is 752*10^18.
    /// @param amount amount to normalize
    /// @return amount normalized to 18 decimals
    function normalizeAmountTo18Decimals(address token, uint256 amount)
        internal
        view
        returns (uint256)
    {
        // get decimals
        uint8 tokenDecimals = getDecimals(token);

        // normalize
        if (tokenDecimals < 18) {
            amount = amount * 10 ** (18 - tokenDecimals);
        } else if (tokenDecimals > 18) {
            amount = amount / (10 ** (tokenDecimals - 18));
        }

        return amount;
    }

    /// @notice convert the amount from normalized 18 decimals back to token's actual number of decimals.
    /// @dev This process is opposite to the one used in normalization function. It's important to notice
    ///      that amount is always rounded down when conversion is performed. 
    /// @param amount amount to convert
    /// @return amount normalized to 18 decimals
    function convertToNativeTokenDecimals(address token, uint256 amount)
        internal
        view
        returns (uint256)
    {
        // get decimals
        uint8 tokenDecimals = getDecimals(token);

        // convert back
        if (tokenDecimals < 18) {
            amount = amount / 10 ** (18 - tokenDecimals);
        } else if (tokenDecimals > 18) {
            amount = amount * (10 ** (tokenDecimals - 18));
        }

        return amount;
    }

    /// @notice use static call to get number of decimals used by token.
    /// @param token address of the token
    /// @return number of decimals used by token. Returns 0 if static call is unsuccessful.
    function getDecimals(address token) internal view returns (uint8) {
        (bool success, bytes memory decimalsData) =
            token.staticcall(abi.encodeWithSelector(ERC20.decimals.selector));
        if (success && decimalsData.length == 32) {
            // decimals() returns uint8
            return BytesLib.toUint8(decimalsData, 31);
        }

        return 0;
    }
}
