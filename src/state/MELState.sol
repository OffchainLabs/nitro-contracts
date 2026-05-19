// Copyright 2021-2026, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

struct MELState {
    // Versioning struct for the state, starting at 0.
	uint16 version;

	// Parent chain ID of the Arbitrum chain that is running MEL.
	uint64 parentChainId;
	// The latest parent chain block fields processed by MEL.
	uint64 parentChainBlockNumber;

	// Address of the contract where batches are posted to.
	address batchPostingTargetAddress;
	// Address of the contract where delayed messages are posted to.
	address delayedMessagePostingTargetAddress;

	// The latest parent chain block hash observed by MEL and the hash of its parent
	bytes32 parentChainBlockHash;
	bytes32 parentChainPreviousBlockHash;

	// Number of batches observed when extracting with MEL.
	uint64 batchCount;
	
	// Total messages extracted by MEL
	uint64 msgCount;

	// Represents messages accumulated during processing of this specific parent chain block
	bytes32 localMsgAccumulator;

	// Accumulators and numbers related to delayed messages.
	uint64 delayedMessagesRead;
	uint64 delayedMessagesSeen;
	bytes32 delayedMessageInboxAcc;
	bytes32 delayedMessageOutboxAcc;
}

/**
 * @notice Utility functions for MELState
 */
library MELStateLib {
    function hash(MELState memory state) internal pure returns (bytes32) {
        return keccak256(abi.encode(state));
    }
}
