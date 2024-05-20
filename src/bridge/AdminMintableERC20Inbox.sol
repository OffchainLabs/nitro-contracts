// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/nitro/blob/master/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.4;

import "./IBridge.sol";
import "./IERC20Bridge.sol";
import "./ISequencerInbox.sol";
import "./IDelayedMessageProvider.sol";

import "../libraries/AddressAliasHelper.sol";
import "../libraries/DelegateCallAware.sol";
import {NotRollupOrOwner} from "../libraries/Error.sol";
import {L1MessageType_ethDeposit} from "../libraries/MessageTypes.sol";

import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

/**
 * @title Inbox for user and contract originated messages
 * @notice Messages created via this inbox are enqueued in the delayed accumulator
 * to await inclusion in the SequencerInbox
 */
contract AdminMintableERC20Inbox is
    DelegateCallAware,
    PausableUpgradeable,
    IDelayedMessageProvider
{
    IBridge public bridge;
    ISequencerInbox public sequencerInbox;

    modifier onlyRollupOrOwner() {
        IOwnable rollup = bridge.rollup();
        if (msg.sender != address(rollup)) {
            address rollupOwner = rollup.owner();
            if (msg.sender != rollupOwner) {
                revert NotRollupOrOwner(msg.sender, address(rollup), rollupOwner);
            }
        }
        _;
    }

    function initialize(IBridge _bridge, ISequencerInbox _sequencerInbox)
        external
        initializer
        onlyDelegated
    {
        bridge = _bridge;
        sequencerInbox = _sequencerInbox;
        __Pausable_init();
    }

    function pause() external onlyRollupOrOwner {
        _pause();
    }

    function unpause() external onlyRollupOrOwner {
        _unpause();
    }

    function deposit(address dest, uint256 amount)
        public
        whenNotPaused
        onlyRollupOrOwner
        returns (uint256)
    {
        return
            _deliverMessage(
                L1MessageType_ethDeposit,
                msg.sender,
                abi.encodePacked(dest, amount), // encode the destination and amount
                0 // set amount to 0 here so the bridge will not ask for funds
            );
    }

    function _deliverMessage(
        uint8 _kind,
        address _sender,
        bytes memory _messageData,
        uint256 _amount
    ) internal returns (uint256) {
        uint256 msgNum = _deliverToBridge(_kind, _sender, keccak256(_messageData), _amount);
        emit InboxMessageDelivered(msgNum, _messageData);
        return msgNum;
    }

    function _deliverToBridge(
        uint8 kind,
        address sender,
        bytes32 messageDataHash,
        uint256 amount
    ) internal returns (uint256) {
        return
            IERC20Bridge(address(bridge)).enqueueDelayedMessage(
                kind,
                AddressAliasHelper.applyL1ToL2Alias(sender),
                messageDataHash,
                amount
            );
    }
}
