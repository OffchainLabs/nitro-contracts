// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/nitro/blob/master/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.4;

import "./AbsBridge.sol";
import "./IERC20Bridge.sol";
import "../libraries/AddressAliasHelper.sol";
import {
    InvalidTokenSet,
    CallTargetNotAllowed,
    CallNotAllowed,
    NativeTokenDecimalsTooLarge
} from "../libraries/Error.sol";
import {DecimalsConverterHelper} from "../libraries/DecimalsConverterHelper.sol";
import {MAX_ALLOWED_NATIVE_TOKEN_DECIMALS} from "../libraries/Constants.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title Staging ground for incoming and outgoing messages
 * @notice Unlike the standard Eth bridge, native token bridge escrows the custom ERC20 token which is
 * used as native currency on L2.
 * @dev Fees are paid in this token. There are certain restrictions on the native token:
 *       - The token can't be rebasing or have a transfer fee
 *       - The token must only be transferrable via a call to the token address itself
 *       - The token must only be able to set allowance via a call to the token address itself
 *       - The token must not have a callback on transfer, and more generally a user must not be able to make a transfer to themselves revert
 *       - The token must have a max of 2^256 - 1 wei total supply unscaled
 *       - The token must have a max of 2^256 - 1 wei total supply when scaled to 18 decimals
 */
contract ERC20Bridge is AbsBridge, IERC20Bridge {
    using SafeERC20 for IERC20;

    /// @inheritdoc IERC20Bridge
    address public nativeToken;

    /// @inheritdoc IERC20Bridge
    uint8 public nativeTokenDecimals;

    /// @inheritdoc IERC20Bridge
    function initialize(IOwnable rollup_, address nativeToken_) external initializer onlyDelegated {
        if (nativeToken_ == address(0)) revert InvalidTokenSet(nativeToken_);
        nativeToken = nativeToken_;
        _activeOutbox = EMPTY_ACTIVEOUTBOX;
        rollup = rollup_;

        // store number of decimals used by native token
        try ERC20(nativeToken_).decimals() returns (uint8 decimals) {
            if (decimals > MAX_ALLOWED_NATIVE_TOKEN_DECIMALS) {
                revert NativeTokenDecimalsTooLarge(decimals);
            }
            nativeTokenDecimals = decimals;
        } catch {
            // decimal is not part of the ERC20 spec
            // assume it have 0 decimals if it does not have decimals() method
            // we do this to align with the token bridge behavior
            nativeTokenDecimals = 0;
        }
    }

    /// @notice When upgrading a custom fee chain from v1.x.x to v2.1.2, nativeTokenDecimals must be set to 18.
    ///         This is because v1.x.x contracts assume 18 decimals, but the ERC20Bridge does not have the decimals set in storage.
    function postUpgradeInit() external onlyDelegated onlyProxyOwner {
        // this zero check might save you from accidentally upgrading from v2.x.x to v2.1.2
        // it will not save you if your native token is supposed to have 0 decimals
        require(nativeTokenDecimals == 0, "NONZERO_NATIVE_TOKEN_DECIMALS");
        nativeTokenDecimals = 18;
    }

    /// @inheritdoc IERC20Bridge
    function enqueueDelayedMessage(
        uint8 kind,
        address sender,
        bytes32 messageDataHash,
        uint256 tokenFeeAmount
    ) external returns (uint256) {
        return _enqueueDelayedMessage(kind, sender, messageDataHash, tokenFeeAmount);
    }

    function _transferFunds(uint256 amount) internal override {
        // fetch native token from Inbox
        IERC20(nativeToken).safeTransferFrom(msg.sender, address(this), amount);
    }

    function _executeLowLevelCall(
        address to,
        uint256 value,
        bytes memory data
    ) internal override returns (bool success, bytes memory returnData) {
        address _nativeToken = nativeToken;

        // we don't allow outgoing calls to native token contract because it could
        // result in loss of native tokens which are escrowed by ERC20Bridge
        if (to == _nativeToken) {
            revert CallTargetNotAllowed(_nativeToken);
        }

        // first release native token
        IERC20(_nativeToken).safeTransfer(to, value);
        success = true;

        // if there's data do additional contract call. Make sure that call is not used to
        // decrease bridge contract's balance of the native token
        if (data.length > 0) {
            uint256 bridgeBalanceBefore = IERC20(_nativeToken).balanceOf(address(this));

            // solhint-disable-next-line avoid-low-level-calls
            (success, returnData) = to.call(data);

            uint256 bridgeBalanceAfter = IERC20(_nativeToken).balanceOf(address(this));
            if (bridgeBalanceAfter < bridgeBalanceBefore) {
                revert CallNotAllowed();
            }
        }
    }

    function _baseFeeToReport() internal pure override returns (uint256) {
        // ArbOs uses formula 'l1BaseFee * (1400 + 6 * calldataLengthInBytes)' to calculate retryable ticket's
        // submission fee. When custom ERC20 token is used to pay for fees, submission fee shall be 0. That's
        // why baseFee is reported as 0 here.
        return 0;
    }
}
