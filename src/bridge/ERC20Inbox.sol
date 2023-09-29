// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/nitro/blob/master/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.4;

import "./AbsInbox.sol";
import "./IERC20Inbox.sol";
import "./IERC20Bridge.sol";
import "../libraries/AddressAliasHelper.sol";
import {L1MessageType_ethDeposit} from "../libraries/MessageTypes.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AmountTooLarge, NativeTokenDecimalsTooLarge} from "../libraries/Error.sol";
import {DecimalsConverterHelper} from "../libraries/DecimalsConverterHelper.sol";

/**
 * @title Inbox for user and contract originated messages
 * @notice Messages created via this inbox are enqueued in the delayed accumulator
 * to await inclusion in the SequencerInbox
 */
contract ERC20Inbox is AbsInbox, IERC20Inbox {
    using SafeERC20 for IERC20;

    /// @dev number of decimals used by native token
    uint8 public nativeTokenDecimals;

    /// @dev If nativeTokenDecimals is different than 18 decimals, bridge will inflate or deflate token amounts
    ///      when depositing to child chain to match 18 decimal denomination. Opposite process happens when
    ///      amount is withdrawn back to parent chain. In order to avoid uint256 overflows we restrict max number
    ///      of decimals to 36 which should be enough for most practical use-cases.
    uint8 public constant MAX_ALLOWED_NATIVE_TOKEN_DECIMALS = uint8(36);

    /// @dev Max amount that can be moved from parent chain to child chain. Also the max amount that can be
    ///      claimed on parent chain after withdrawing it from child chain. Amounts higher than this would
    ///      risk uint256 overflows. This amount is derived from the fact that we have set MAX_ALLOWED_NATIVE_TOKEN_DECIMALS
    ///      to 36 which means that in the worst case we are inflating by 18 decimals points. This constant
    ///      equals to ~1.1*10^59 tokens
    uint256 public constant MAX_BRIDGEABLE_AMOUNT = type(uint256).max / 10**18;

    /// @inheritdoc IInboxBase
    function initialize(IBridge _bridge, ISequencerInbox _sequencerInbox)
        external
        initializer
        onlyDelegated
    {
        __AbsInbox_init(_bridge, _sequencerInbox);

        // inbox holds native token in transit used to pay for retryable tickets, approve bridge to use it
        address nativeToken = IERC20Bridge(address(bridge)).nativeToken();
        IERC20(nativeToken).approve(address(bridge), type(uint256).max);

        // store number of decimals used by native token
        nativeTokenDecimals = DecimalsConverterHelper.getDecimals(nativeToken);
        if (nativeTokenDecimals > MAX_ALLOWED_NATIVE_TOKEN_DECIMALS) {
            revert NativeTokenDecimalsTooLarge(nativeTokenDecimals);
        }
    }

    /// @inheritdoc IERC20Inbox
    function depositERC20(uint256 amount) public whenNotPaused onlyAllowed returns (uint256) {
        address dest = msg.sender;

        // solhint-disable-next-line avoid-tx-origin
        if (AddressUpgradeable.isContract(msg.sender) || tx.origin != msg.sender) {
            // isContract check fails if this function is called during a contract's constructor.
            dest = AddressAliasHelper.applyL1ToL2Alias(msg.sender);
        }

        uint256 amountToMintOnL2 = _fromNativeTo18Decimals(amount);
        return
            _deliverMessage(
                L1MessageType_ethDeposit,
                msg.sender,
                abi.encodePacked(dest, amountToMintOnL2),
                amount
            );
    }

    /// @inheritdoc IERC20Inbox
    function createRetryableTicket(
        address to,
        uint256 l2CallValue,
        uint256 maxSubmissionCost,
        address excessFeeRefundAddress,
        address callValueRefundAddress,
        uint256 gasLimit,
        uint256 maxFeePerGas,
        uint256 tokenTotalFeeAmount,
        bytes calldata data
    ) external whenNotPaused onlyAllowed returns (uint256) {
        return
            _createRetryableTicket(
                to,
                l2CallValue,
                maxSubmissionCost,
                excessFeeRefundAddress,
                callValueRefundAddress,
                gasLimit,
                maxFeePerGas,
                tokenTotalFeeAmount,
                data
            );
    }

    /// @inheritdoc IERC20Inbox
    function unsafeCreateRetryableTicket(
        address to,
        uint256 l2CallValue,
        uint256 maxSubmissionCost,
        address excessFeeRefundAddress,
        address callValueRefundAddress,
        uint256 gasLimit,
        uint256 maxFeePerGas,
        uint256 tokenTotalFeeAmount,
        bytes calldata data
    ) public whenNotPaused onlyAllowed returns (uint256) {
        return
            _unsafeCreateRetryableTicket(
                to,
                l2CallValue,
                maxSubmissionCost,
                excessFeeRefundAddress,
                callValueRefundAddress,
                gasLimit,
                maxFeePerGas,
                tokenTotalFeeAmount,
                data
            );
    }

    /// @inheritdoc IInboxBase
    function calculateRetryableSubmissionFee(uint256, uint256)
        public
        pure
        override(AbsInbox, IInboxBase)
        returns (uint256)
    {
        // retryable ticket's submission fee is not charged when ERC20 token is used to pay for fees
        return 0;
    }

    function _deliverToBridge(
        uint8 kind,
        address sender,
        bytes32 messageDataHash,
        uint256 tokenAmount
    ) internal override returns (uint256) {
        // Fetch native token from sender if inbox doesn't already hold enough tokens to pay for fees.
        // Inbox might have been pre-funded in prior call, ie. as part of token bridging flow.
        address nativeToken = IERC20Bridge(address(bridge)).nativeToken();
        uint256 inboxNativeTokenBalance = IERC20(nativeToken).balanceOf(address(this));
        if (inboxNativeTokenBalance < tokenAmount) {
            uint256 diff = tokenAmount - inboxNativeTokenBalance;
            IERC20(nativeToken).safeTransferFrom(msg.sender, address(this), diff);
        }

        return
            IERC20Bridge(address(bridge)).enqueueDelayedMessage(
                kind,
                AddressAliasHelper.applyL1ToL2Alias(sender),
                messageDataHash,
                tokenAmount
            );
    }

    /// @inheritdoc AbsInbox
    function _fromNativeTo18Decimals(uint256 value) internal view override returns (uint256) {
        // In order to keep compatibility of child chain's native currency with external 3rd party tooling we
        // expect 18 decimals to be always used for native currency. If native token uses different number of
        // decimals then here it will be normalized to 18. Keep in mind, when withdrawing from child chain back
        // to parent chain then the amount has to match native token's granularity, otherwise it will be rounded
        // down.

        // Also make sure that inflated amount does not overflow uint256
        if (nativeTokenDecimals < 18) {
            if (value > MAX_BRIDGEABLE_AMOUNT) {
                revert AmountTooLarge(value);
            }
        }
        return DecimalsConverterHelper.adjustDecimals(value, nativeTokenDecimals, 18);
    }
}
