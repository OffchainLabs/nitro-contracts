// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import {BytesLib} from "./BytesLib.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

library DecimalsConverterHelper {
    /// @notice generic function for mapping amount from one decimal denomination to another
    /// @dev Ie. let's say amount is 752. If token has 16 decimals and is being adjusted to
    ///      18 decimals then amount will be 75200. If token has 20 decimals adjusted amount
    ///      is 7. If token uses no decimals converted amount is 752*10^18.
    ///      When amount is adjusted from 18 decimals back to native token decimals, opposite
    ///      process is performed.
    /// @param amount amount to convert
    /// @param decimalsIn current decimals
    /// @param decimalsOut target decimals
    /// @return amount converted to 'decimalsOut' decimals
    function adjustDecimals(
        uint256 amount,
        uint8 decimalsIn,
        uint8 decimalsOut
    ) internal pure returns (uint256) {
        if (decimalsIn < decimalsOut) {
            return amount * 10**(decimalsOut - decimalsIn);
        } else if (decimalsOut < decimalsIn) {
            return amount / 10**(decimalsIn - decimalsOut);
        } else {
            return amount;
        }
    }

    /// @notice use static call to get number of decimals used by token.
    /// @param token address of the token
    /// @return number of decimals used by token. Returns 0 if static call is unsuccessful.
    function getDecimals(address token) internal view returns (uint8) {
        (bool success, bytes memory decimalsData) = token.staticcall(
            abi.encodeWithSelector(ERC20.decimals.selector)
        );
        if (success && decimalsData.length == 32) {
            // decimals() returns uint8
            return BytesLib.toUint8(decimalsData, 31);
        }

        return 0;
    }
}
