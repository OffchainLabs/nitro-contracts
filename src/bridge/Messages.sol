// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

library Messages {
    struct Message {
        uint8 kind;
        address sender;
        uint64 blockNumber;
        uint64 timestamp;
        uint256 inboxSeqNum;
        uint256 baseFeeL1;
        bytes32 messageDataHash;
    }

    struct InboxAccPreimage {
        bytes32 beforeAcc;
        bytes32 dataHash;
        bytes32 delayedAcc;
    }

    function messageHash(Message memory message) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    message.kind,
                    message.sender,
                    message.blockNumber,
                    message.timestamp,
                    message.inboxSeqNum,
                    message.baseFeeL1,
                    message.messageDataHash
                )
            );
    }

    function messageHash(
        uint8 kind,
        address sender,
        uint64 blockNumber,
        uint64 timestamp,
        uint256 inboxSeqNum,
        uint256 baseFeeL1,
        bytes32 messageDataHash
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    kind,
                    sender,
                    blockNumber,
                    timestamp,
                    inboxSeqNum,
                    baseFeeL1,
                    messageDataHash
                )
            );
    }

    function accumulateInboxMessage(bytes32 prevAcc, bytes32 message)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(prevAcc, message));
    }

    function accumulateSequencerInbox(InboxAccPreimage memory preimage)
        internal
        pure
        returns (bytes32)
    {
        return
            keccak256(abi.encodePacked(preimage.beforeAcc, preimage.dataHash, preimage.delayedAcc));
    }

    /// @dev   Validates an inbox accumulator preimage
    /// @param inboxAcc The inbox accumulator to validate against
    /// @param preimage The preimage to validate
    function isValidSequencerInboxAccPreimage(bytes32 inboxAcc, InboxAccPreimage memory preimage)
        internal
        pure
        returns (bool)
    {
        return inboxAcc == accumulateSequencerInbox(preimage);
    }

    /// @dev   Validates a delayed accumulator preimage
    /// @param delayedAcc The delayed accumulator to validate against
    /// @param beforeDelayedAcc The previous delayed accumulator
    /// @param message The message to validate
    function isValidDelayedAccPreimage(
        bytes32 delayedAcc,
        bytes32 beforeDelayedAcc,
        Message memory message
    ) internal pure returns (bool) {
        return delayedAcc == accumulateInboxMessage(beforeDelayedAcc, messageHash(message));
    }
}
