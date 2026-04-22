// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

struct GlobalState {
    // BlockHash and SendRoot
    bytes32[2] bytes32Vals;
    // Deprecated after MEL: Batch (InboxPosition) and PositionInBatch (PositionInMessage)
    uint64[2] u64Vals;

    // MELState hash and NextMsg hash
    bytes32[2] melBytes32Vals;
    // MsgCount and ExecutedMsgCount
    uint64[2] melU64Vals;
}

library GlobalStateLib {
    using GlobalStateLib for GlobalState;

    uint16 internal constant BYTES32_VALS_NUM = 2;
    uint16 internal constant U64_VALS_NUM = 2;

    function hash(
        GlobalState memory state
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                "Global state:",
                state.bytes32Vals[0],
                state.bytes32Vals[1],
                state.u64Vals[0],
                state.u64Vals[1],
                state.melBytes32Vals[0],
                state.melBytes32Vals[1],
                state.melU64Vals[0],
                state.melU64Vals[1]
            )
        );
    }

    function getBlockHash(
        GlobalState memory state
    ) internal pure returns (bytes32) {
        return state.bytes32Vals[0];
    }

    function getSendRoot(
        GlobalState memory state
    ) internal pure returns (bytes32) {
        return state.bytes32Vals[1];
    }

    function getInboxPosition(
        GlobalState memory state
    ) internal pure returns (uint64) {
        return state.u64Vals[0];
    }

    function getPositionInMessage(
        GlobalState memory state
    ) internal pure returns (uint64) {
        return state.u64Vals[1];
    }

    function getMELStateHash(
        GlobalState memory state
    ) internal pure returns (bytes32) {
        return state.melBytes32Vals[0];
    }

    function getMELNextMsgHash(
        GlobalState memory state
    ) internal pure returns (bytes32) {
        return state.melBytes32Vals[1];
    }

    function getMELMsgCount(
        GlobalState memory state
    ) internal pure returns (uint64) {
        return state.melU64Vals[0];
    }

    function getMELExecutedMsgCount(
        GlobalState memory state
    ) internal pure returns (uint64) {
        return state.melU64Vals[1];
    }

    function isEmpty(
        GlobalState calldata state
    ) internal pure returns (bool) {
        return (
            state.bytes32Vals[0] == bytes32(0) && state.bytes32Vals[1] == bytes32(0)
                && state.u64Vals[0] == 0 && state.u64Vals[1] == 0
        );
    }

    function comparePositions(
        GlobalState calldata a,
        GlobalState calldata b
    ) internal pure returns (int256) {
        uint64 aPos = a.getInboxPosition();
        uint64 bPos = b.getInboxPosition();
        if (aPos < bPos) {
            return -1;
        } else if (aPos > bPos) {
            return 1;
        } else {
            uint64 aMsg = a.getPositionInMessage();
            uint64 bMsg = b.getPositionInMessage();
            if (aMsg < bMsg) {
                return -1;
            } else if (aMsg > bMsg) {
                return 1;
            } else {
                return 0;
            }
        }
    }

    function comparePositionsAgainstStartOfBatch(
        GlobalState calldata a,
        uint256 bPos
    ) internal pure returns (int256) {
        uint64 aPos = a.getInboxPosition();
        if (aPos < bPos) {
            return -1;
        } else if (aPos > bPos) {
            return 1;
        } else {
            if (a.getPositionInMessage() > 0) {
                return 1;
            } else {
                return 0;
            }
        }
    }

    function compareExecutedMessages(
        GlobalState calldata a,
        GlobalState calldata b
    ) internal pure returns (int256) {
        uint64 aPos = a.getMELExecutedMsgCount();
        uint64 bPos = b.getMELExecutedMsgCount();
        if (aPos < bPos) {
            return -1;
        } else if (aPos > bPos) {
            return 1;
        } else {
            return 0;
        }
    }
}
