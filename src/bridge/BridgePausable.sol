// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/nitro/blob/master/LICENSE
// SPDX-License-Identifier: BUSL-1.1
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {
    OutboxExecutionPaused,
    OutboxExecutionNotPaused,
    SequencerInboxMsgsPaused,
    SequencerInboxMsgsNotPaused,
    DelayedMessagesEnqueuePaused,
    DelayedMessagesEnqueueNotPaused
} from "../libraries/Error.sol";
pragma solidity ^0.8.4;

contract BridgePausable is AccessControlUpgradeable {
    bool internal _outboxExecutionPaused;
    bool internal _sequencerInboxMsgsPaused;
    bool internal _delayedMessageEnqueuePaused;

    bytes32 public constant PAUSE_OUTBOX_EXECUTION_ROLE = keccak256("PAUSE_OUTBOX_EXECUTION_ROLE");
    bytes32 public constant UNPAUSE_OUTBOX_EXECUTION_ROLE =
        keccak256("UNPAUSE_OUTBOX_EXECUTION_ROLE");

    bytes32 public constant PAUSE_SEQUENCER_INBOX_MSGS_ROLE =
        keccak256("PAUSE_SEQUENCER_INBOX_MSGS_ROLE");
    bytes32 public constant UNPAUSE_SEQUENCER_INBOX_MSGS_ROLE =
        keccak256("UNPAUSE_SEQUENCER_INBOX_MSGS_ROLE");

    bytes32 public constant PAUSE_DELAYED_MESSAGE_ENQUEUE_ROLE =
        keccak256("PAUSE_DELAYED_MESSAGE_ENQUEUE_ROLE");
    bytes32 public constant UNPAUSE_DELAYED_MESSAGE_ENQUEUE_ROLE =
        keccak256("UNPAUSE_DELAYED_MESSAGE_ENQUEUE_ROLE");

    modifier whenOutboxExecutionNotPaused() {
        if (_outboxExecutionPaused) {
            revert OutboxExecutionPaused();
        }
        _;
    }

    modifier whenOutboxExecutionPaused() {
        if (!_outboxExecutionPaused) {
            revert OutboxExecutionNotPaused();
        }
        _;
    }

    modifier whenSequencerInboxMsgsNotPaused() {
        if (_sequencerInboxMsgsPaused) {
            revert SequencerInboxMsgsPaused();
        }
        _;
    }

    modifier whenSequencerInboxMsgsPaused() {
        if (!_sequencerInboxMsgsPaused) {
            revert SequencerInboxMsgsNotPaused();
        }
        _;
    }

    modifier whenDelayedMessageEnqueueNotPaused() {
        if (_delayedMessageEnqueuePaused) {
            revert DelayedMessagesEnqueuePaused();
        }
        _;
    }

    modifier whenDelayedMessageEnqueuePaused() {
        if (!_delayedMessageEnqueuePaused) {
            revert DelayedMessagesEnqueueNotPaused();
        }
        _;
    }

    function _grantAllPauseRolesTo(address owner) internal {
        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(PAUSE_OUTBOX_EXECUTION_ROLE, owner);
        _grantRole(UNPAUSE_OUTBOX_EXECUTION_ROLE, owner);
        _grantRole(PAUSE_SEQUENCER_INBOX_MSGS_ROLE, owner);
        _grantRole(UNPAUSE_SEQUENCER_INBOX_MSGS_ROLE, owner);
        _grantRole(PAUSE_DELAYED_MESSAGE_ENQUEUE_ROLE, owner);
        _grantRole(UNPAUSE_DELAYED_MESSAGE_ENQUEUE_ROLE, owner);
    }

    function pauseOutboxExecution()
        external
        onlyRole(PAUSE_OUTBOX_EXECUTION_ROLE)
        whenOutboxExecutionNotPaused
    {
        _outboxExecutionPaused = true;
    }

    function unpauseOutboxExecution()
        external
        onlyRole(UNPAUSE_OUTBOX_EXECUTION_ROLE)
        whenOutboxExecutionPaused
    {
        _outboxExecutionPaused = false;
    }

    function pauseSequencerInboxMsgs()
        external
        onlyRole(PAUSE_SEQUENCER_INBOX_MSGS_ROLE)
        whenSequencerInboxMsgsNotPaused
    {
        _sequencerInboxMsgsPaused = true;
    }

    function unpauseSequencerInboxMsgs()
        external
        onlyRole(UNPAUSE_SEQUENCER_INBOX_MSGS_ROLE)
        whenSequencerInboxMsgsPaused
    {
        _sequencerInboxMsgsPaused = false;
    }

    function pauseDelayedMsgsEnque()
        external
        onlyRole(PAUSE_DELAYED_MESSAGE_ENQUEUE_ROLE)
        whenDelayedMessageEnqueueNotPaused
    {
        _delayedMessageEnqueuePaused = true;
    }

    function unpauseDelayedMsgsEnque()
        external
        onlyRole(UNPAUSE_DELAYED_MESSAGE_ENQUEUE_ROLE)
        whenDelayedMessageEnqueuePaused
    {
        _delayedMessageEnqueuePaused = false;
    }
}
