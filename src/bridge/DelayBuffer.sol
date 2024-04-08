// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import {
    InvalidDelayedAccPreimage,
    InvalidSequencerInboxAccPreimage,
    UnexpectedDelay
} from "../libraries/Error.sol";
import "./Messages.sol";
import "./DelayBufferTypes.sol";

/**
 * @title   Manages the delay buffer for the sequencer (SequencerInbox.sol)
 * @notice  Messages are expected to be delayed up to a threshold, beyond which they are unexpected
 *          and deplete a delay buffer. Buffer depletion is preveneted from decreasing too fast by only
 *          depleting by as many seconds / blocks has elapsed in the delayed message queue.
 */
library DelayBuffer {
    /// @dev    This function proves delays (or lack thereof) and updates the buffer.
    /// @param self The delay buffer data
    /// @param config The delay buffer settings
    /// @param delayedAcc The delayed accumulator of the first delayed message sequenced
    /// @param delayProof The proof of the delay of the first delayed message sequenced
    function delay(
        BufferData storage self,
        BufferConfig memory config,
        bytes32 delayedAcc,
        DelayProof memory delayProof
    ) internal {
        if (
            !Messages.isValidDelayedAccPreimage(
                delayedAcc,
                delayProof.beforeDelayedAcc,
                delayProof.delayedMessage
            )
        ) {
            revert InvalidDelayedAccPreimage();
        }
        update(self, config, delayProof.delayedMessage.blockNumber);
        if (isOnTime(delayProof.delayedMessage.blockNumber, config.threshold)) {
            updateSyncValidity(self, config, delayProof.delayedMessage.blockNumber);
        }
    }

    /// @dev    This function is called by the sequencer inbox when a delayed message is sequenced, 
    ///         proving the message is on-time and updating the sync validity window. 
    /// @notice Synchronizes the sequencer inbox with the delayed inbox.
    /// @param beforeAcc The inbox accumulator before the current batch
    /// @param bufferProof The proof that the delayed message is valid
    function sync(
        BufferData storage self,
        BufferConfig memory config,
        bytes32 beforeAcc,
        BufferProof memory bufferProof
    ) internal {
        // validates the delayed message against the inbox accumulator
        // and proves the delayed message is synced within the delay threshold
        // this is a sufficient condition to prove that any delayed messages sequenced
        // in the current batch are also synced within the delay threshold
        if (!Messages.isValidSequencerInboxAccPreimage(beforeAcc, bufferProof.preimage)) {
            revert InvalidSequencerInboxAccPreimage();
        }
        if (
            !Messages.isValidDelayedAccPreimage(
                bufferProof.preimage.delayedAcc,
                bufferProof.beforeDelayedAcc,
                bufferProof.delayedMessage
            )
        ) {
            revert InvalidDelayedAccPreimage();
        }
        if (!isOnTime(bufferProof.delayedMessage.blockNumber, config.threshold)) {
            revert UnexpectedDelay(bufferProof.delayedMessage.blockNumber);
        }

        // calculate the margin of the delay message below the delay threshold
        // no sync / delay proofs are required in this margin `sync validity` period.
        updateSyncValidity(self, config, bufferProof.delayedMessage.blockNumber);
    }

    /// @dev    Calculates the margin a sequenced message is below the delay threshold
    ///         defining a `sync validity` window during which no delay proofs are required.
    /// @notice Updates the time / block until no delay proofs are required.
    /// @param blockNumber The block number when the synced message was created.
    function updateSyncValidity(
        BufferData storage self,
        BufferConfig memory config,
        uint64 blockNumber
    ) internal {
        // saturating at uint64 max handles large threshold settings
        self.syncExpiry = config.threshold > type(uint64).max - blockNumber
            ? type(uint64).max
            : blockNumber + config.threshold;
    }

    /// @dev    Depletion is limited by the elapsed time / blocks in the delayed message queue to avoid double counting and potential L2 reorgs.
    //          Eg. 2 simultaneous batches sequencing multiple delayed messages with the same 20 min / 100 blocks delay each
    //          should count once as 20 min / 100 block delay, not twice as 40 min / 200 block delay. This also prevents L2 reorg risk in edge cases.
    //          Eg. If the buffer is 30 min, decrementing the buffer when processing the first batch would allow the second delay message to be force included before the sequencer could add the second batch.
    //          Buffer depletion also saturates at the threshold instead of zero to allow a recovery margin.
    //          Eg. when the sequencer recovers from an outage, it is able to wait threshold > finality time before queueing delayed messages to avoid L1 reorgs.
    /// @notice Decrements the delay buffer saturating at the threshold
    /// @param start The beginning reference point (prev delay)
    /// @param end The ending reference point (current message)
    /// @param prevDelay The delay to be applied
    /// @param threshold The threshold to saturate at
    /// @param buffer The buffer to be decremented
    function deplete(
        uint64 start,
        uint64 end,
        uint64 buffer,
        uint64 prevDelay,
        uint64 threshold
    ) internal pure returns (uint64) {
        uint64 elapsed = end > start ? end - start : 0;
        uint64 unexpectedDelay = prevDelay > threshold ? prevDelay - threshold : 0;
        if (unexpectedDelay > elapsed) {
            unexpectedDelay = elapsed;
        }
        // decrease the buffer saturating at zero
        buffer = buffer > unexpectedDelay ? buffer - unexpectedDelay : 0;
        // saturate at threshold
        buffer = buffer > threshold ? buffer : threshold;
        return buffer;
    }

    /// @notice Replenishes the delay buffer saturating at max
    /// @param start The beginning reference point
    /// @param end The ending reference point
    /// @param buffer The buffer to be replenished
    /// @param max The maximum buffer
    /// @param period The replenish period
    function replenish(
        uint64 start,
        uint64 end,
        uint64 buffer,
        uint64 max,
        uint64 period
    ) internal pure returns (uint64) {
        // add the replenish round off from the last replenish
        uint64 elapsed = end > start ? end - start : 0;
        // purposely ignores rounding for simplicity
        uint64 replenishAmount = elapsed / period;
        if (max - buffer > replenishAmount) {
            buffer += replenishAmount;
        } else {
            // saturate
            buffer = max;
        }
        return buffer;
    }

    function update(
        uint64 start,
        uint64 end,
        uint64 buffer,
        uint64 prevDelay,
        uint64 threshold,
        uint64 max,
        uint64 period
    ) internal pure returns (uint64) {
        if (threshold < prevDelay) {
            // unexpected delay
            buffer = deplete(start, end, buffer, prevDelay, threshold);
        } else if (buffer < max) {
            buffer = replenish(start, end, buffer, max, period);
        }
        return buffer;
    }

    /// @notice Updates buffer and prevDelay
    /// @param self The delay buffer data
    /// @param config The delay buffer settings
    /// @param blockNumber The update block number
    function update(
        BufferData storage self,
        BufferConfig memory config,
        uint64 blockNumber
    ) internal {
        // The prevDelay stores the delay of the previous batch which is
        // used as a starting reference point to calculate an elapsed amount using the current
        // message as the ending reference point.

        self.buffer = pendingUpdate(self, config, blockNumber);

        // store a new starting reference point
        // any buffer updates will be applied retroactively in the next batch post
        self.prevBlockNumber = blockNumber;
        self.prevDelay = uint64(block.number) - blockNumber;
    }

    /// @dev    The delay buffer can change due to pending depletion / replenishment due to previous delays.
    ///         This function applies pending buffer changes to proactively calculate the buffer changes.
    ///         This is only relevant when the bufferBlocks is less than delayBlocks.
    /// @notice Proactively calculates the buffer changes up to the requested block number
    /// @param self The delay buffer data
    /// @param config The delay buffer settings
    /// @param blockNumber The block number to process the delay up to
    function pendingUpdate(
        BufferData storage self,
        BufferConfig memory config,
        uint64 blockNumber
    ) internal view returns (uint64) {
        return
            update({
                start: self.prevBlockNumber,
                end: blockNumber,
                buffer: self.buffer,
                threshold: config.threshold,
                prevDelay: self.prevDelay,
                max: config.max,
                period: config.period
            });
    }

    /// @dev    This is the `sync validity window` during which no proofs are required.
    /// @notice Returns true if the inbox is in a synced state (no unexpected delays are possible)
    function isSynced(BufferData storage self) internal view returns (bool) {
        return block.number <= self.syncExpiry;
    }

    function isOnTime(uint64 blockNumber, uint64 thresholdBlocks) internal view returns (bool) {
        return uint64(block.number) - blockNumber <= thresholdBlocks;
    }

    function isValidBufferConfig(BufferConfig memory config) internal pure returns (bool) {
        return
            config.threshold != 0 &&
            config.max != 0 &&
            config.period != 0 &&
            config.threshold <= config.max;
    }

    function isMutable(BufferData storage self, BufferConfig memory config)
        internal
        view
        returns (bool)
    {
        return isDelayable(self) || isReplenishable(self, config);
    }

    function isDelayable(BufferData storage self) internal view returns (bool) {
        return !isSynced(self);
    }

    function isReplenishable(BufferData storage self, BufferConfig memory config)
        internal
        view
        returns (bool)
    {
        return self.buffer < config.max;
    }
}
