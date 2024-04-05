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
    ///         It is called by the sequencer inbox when a delayed message is sequenced, proving
    ///         any delays and updating the delay buffers. This function should only be called when the
    ///         sequencer inbox has been unexpectedly delayed (unhappy case) and the buffer is depleting or replenishing.
    /// @notice Synchronizes the sequencer inbox with the delayed inbox.
    /// @param self The delay buffer data
    /// @param bufferConfig The delay buffer settings
    /// @param delayedAcc The delayed accumulator of the first delayed message sequenced
    /// @param delayProof The proof that the delayed message is valid
    function delay(
        BufferData storage self,
        BufferConfig memory bufferConfig,
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
        updateBuffers(
            self,
            bufferConfig,
            delayProof.delayedMessage.blockNumber,
            delayProof.delayedMessage.timestamp
        );
        if (
            isOnTime(
                delayProof.delayedMessage.blockNumber,
                delayProof.delayedMessage.timestamp,
                bufferConfig.thresholdBlocks,
                bufferConfig.thresholdSeconds
            )
        ) {
            updateSyncValidity(
                self,
                bufferConfig,
                delayProof.delayedMessage.blockNumber,
                delayProof.delayedMessage.timestamp
            );
        }
    }

    /// @dev    This function syncs the sequencer inbox with the delayed inbox.
    ///         It is called by the sequencer inbox when a delayed message is sequenced, proving
    ///         the message is on-time and updating the sync validity window. This function is called
    ///         called periodically to renew the sync validity window.
    /// @notice Synchronizes the sequencer inbox with the delayed inbox.
    /// @param beforeAcc The inbox accumulator before the current batch
    /// @param bufferProof The proof that the delayed message is valid
    function sync(
        BufferData storage self,
        BufferConfig memory bufferConfig,
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
        if (
            !isOnTime(
                bufferProof.delayedMessage.blockNumber,
                bufferProof.delayedMessage.timestamp,
                bufferConfig.thresholdBlocks,
                bufferConfig.thresholdSeconds
            )
        ) {
            revert UnexpectedDelay(
                bufferProof.delayedMessage.blockNumber,
                bufferProof.delayedMessage.timestamp
            );
        }

        // calculate the margin of the delay message below the delay threshold
        // no sync / delay proofs are required in this margin `sync validity` period.
        updateSyncValidity(
            self,
            bufferConfig,
            bufferProof.delayedMessage.blockNumber,
            bufferProof.delayedMessage.timestamp
        );
    }

    /// @dev    Calculates the margin a sequenced message is below the delay threshold
    ///         defining a `sync validity` window during which no delay proofs are required.
    /// @notice Updates the time / block until no delay proofs are required.
    /// @param blockNumber The block number when the synced message was created.
    /// @param timestamp The timestamp when the synced message was created.
    function updateSyncValidity(
        BufferData storage self,
        BufferConfig memory bufferConfig,
        uint64 blockNumber,
        uint64 timestamp
    ) internal {
        // saturating at uint64 max gracefully handles large threshold settings
        self.syncExpiryBlockNumber = bufferConfig.thresholdBlocks > type(uint64).max - blockNumber
            ? type(uint64).max
            : blockNumber + bufferConfig.thresholdBlocks;
        self.syncExpiryTimestamp = bufferConfig.thresholdSeconds > type(uint64).max - timestamp
            ? type(uint64).max
            : timestamp + bufferConfig.thresholdSeconds;
    }

    function isOnTime(
        uint64 blockNumber,
        uint64 timestamp,
        uint64 thresholdBlocks,
        uint64 thresholdSeconds
    ) internal view returns (bool) {
        return ((uint64(block.number) - blockNumber <= thresholdBlocks) &&
            (uint64(block.timestamp) - timestamp <= thresholdSeconds));
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
        uint64 prevDelay,
        uint64 threshold,
        uint64 buffer
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

    /// @notice Replenishes the delay buffer saturating at maxBuffer
    /// @param start The beginning reference point
    /// @param end The ending reference point
    /// @param buffer The buffer to be replenished
    /// @param maxBuffer The maximum buffer
    /// @param period The replenish period
    function replenish(
        uint64 start,
        uint64 end,
        uint64 buffer,
        uint64 maxBuffer,
        uint64 period
    ) internal pure returns (uint64) {
        // add the replenish round off from the last replenish
        uint64 elapsed = end > start ? end - start : 0;
        // purposely ignores rounds down for simplicity
        uint64 replenishAmount = elapsed / period;
        if (maxBuffer - buffer > replenishAmount) {
            buffer += replenishAmount;
        } else {
            // saturate
            buffer = maxBuffer;
        }
        return buffer;
    }

    /// @notice Decrements or replenishes the delay buffer conditionally
    /// @param start The beginning reference point (delayPrev)
    /// @param end The ending reference point (current message)
    /// @param prevDelay The delay to be applied
    /// @param threshold The threshold to saturate at
    /// @param buffer The buffer to be decremented
    /// @param maxBuffer The maximum buffer
    /// @param period The replenish period
    function update(
        uint64 start,
        uint64 end,
        uint64 prevDelay,
        uint64 threshold,
        uint64 buffer,
        uint64 maxBuffer,
        uint64 period
    ) internal pure returns (uint64) {
        if (threshold < prevDelay) {
            // unexpected delay
            return deplete(start, end, prevDelay, threshold, buffer);
        } else if (buffer < maxBuffer) {
            // replenish buffer if depleted
            return replenish(start, end, buffer, maxBuffer, period);
        }
        return buffer;
    }

    /// @notice Updates both block number and time buffers.
    /// @param self The delay buffer data
    /// @param bufferConfig The delay buffer settings
    /// @param blockNumber The update block number
    /// @param timestamp The update timestamp
    function updateBuffers(
        BufferData storage self,
        BufferConfig memory bufferConfig,
        uint64 blockNumber,
        uint64 timestamp
    ) internal {
        // The prevDelay stores the delay of the previous batch which is
        // used as a starting reference point to calculate an elapsed amount using the current
        // message as the ending reference point.
        self.bufferBlocks = update({
            start: self.prevDelay.blockNumber,
            end: blockNumber,
            prevDelay: self.prevDelay.delayBlocks,
            threshold: bufferConfig.thresholdBlocks,
            buffer: self.bufferBlocks,
            maxBuffer: bufferConfig.maxBufferBlocks,
            period: bufferConfig.periodBlocks
        });

        self.bufferSeconds = update({
            start: self.prevDelay.timestamp,
            end: timestamp,
            prevDelay: self.prevDelay.delaySeconds,
            threshold: bufferConfig.thresholdSeconds,
            buffer: self.bufferSeconds,
            maxBuffer: bufferConfig.maxBufferSeconds,
            period: bufferConfig.periodSeconds
        });

        // store a new starting reference point
        // any buffer updates will be applied retroactively in the next batch post
        self.prevDelay = DelayHistory({
            blockNumber: blockNumber,
            timestamp: timestamp,
            delayBlocks: uint64(block.number) - blockNumber,
            delaySeconds: uint64(block.timestamp) - timestamp
        });
    }

    /// @dev    The delay buffer can change due to pending depletion in the delay history cache.
    ///         This function applies pending buffer changes to proactively calculate the force inclusion deadline.
    ///         This is only relevant when the bufferBlocks or bufferSeconds are less than delayBlocks or delaySeconds.
    /// @notice Calculates the upper bounds of the delay buffer
    /// @param blockNumber The block number to process the delay up to
    /// @param thresholdBlocks The maximum amount of blocks that a message is expected to be delayed
    /// @param timestamp The timestamp to process the delay up to
    /// @param thresholdSeconds The maximum amount of seconds that a message is expected to be delayed
    function pendingDelay(
        BufferData storage self,
        uint64 blockNumber,
        uint64 timestamp,
        uint64 thresholdBlocks,
        uint64 thresholdSeconds
    ) internal view returns (uint64, uint64) {
        uint64 bufferBlocks = deplete(
            self.prevDelay.blockNumber,
            blockNumber,
            self.prevDelay.delayBlocks,
            thresholdBlocks,
            self.bufferBlocks
        );
        uint64 bufferSeconds = deplete(
            self.prevDelay.timestamp,
            timestamp,
            self.prevDelay.delaySeconds,
            thresholdSeconds,
            self.bufferSeconds
        );
        return (bufferBlocks, bufferSeconds);
    }

    /// @dev    This is the `sync validity window` during which no proofs are required.
    /// @notice Returns true if the inbox is in a synced state (no unexpected delays are possible)
    function isSynced(BufferData storage self) internal view returns (bool) {
        return (block.number <= self.syncExpiryBlockNumber &&
            block.timestamp <= self.syncExpiryTimestamp);
    }

    function isValidBufferConfig(BufferConfig memory bufferConfig) internal pure returns (bool) {
        return
            bufferConfig.thresholdBlocks != 0 &&
            bufferConfig.thresholdSeconds != 0 &&
            bufferConfig.maxBufferBlocks != 0 &&
            bufferConfig.maxBufferSeconds != 0 &&
            bufferConfig.periodSeconds != 0 &&
            bufferConfig.periodBlocks != 0 &&
            bufferConfig.thresholdBlocks <= bufferConfig.maxBufferBlocks &&
            bufferConfig.thresholdSeconds <= bufferConfig.maxBufferSeconds;
    }
}
