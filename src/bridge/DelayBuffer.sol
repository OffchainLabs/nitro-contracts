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

/**
 * @title   Manages the delay buffer for the sequencer (SequencerInbox.sol)
 * @notice  Messages are expected to be delayed up to a threshold, beyond which they are unexpected
 *          and deplete a delay buffer. Buffer depletion is preveneted from decreasing too fast by only
 *          depleting by as many seconds / blocks has elapsed in the delayed message queue.
 */
library DelayBuffer {
    /// @notice Delay buffer and delay threshold settings
    /// @param thresholdBlocks The maximum amount of blocks that a message is expected to be delayed
    /// @param thresholdSeconds The maximum amount of time in seconds that a message is expected to be delayed
    /// @param maxBufferBlocks The maximum buffer in blocks
    /// @param maxBufferSeconds The maximum buffer in seconds
    /// @param replenishRate The rate at which the delay buffer is replenished.
    struct BufferConfig {
        uint64 thresholdBlocks;
        uint64 thresholdSeconds;
        uint64 maxBufferBlocks;
        uint64 maxBufferSeconds;
        ReplenishRate replenishRate;
    }

    /// @notice The rate at which the delay buffer is replenished.
    /// @param blocksPerPeriod The amount of blocks that is added to the delay buffer every period
    /// @param secondsPerPeriod The amount of time in seconds that is added to the delay buffer every period
    /// @param periodBlocks The period in blocks between replenishment
    /// @param periodSeconds The period in seconds between replenishment
    struct ReplenishRate {
        uint64 blocksPerPeriod;
        uint64 secondsPerPeriod;
        uint64 periodBlocks;
        uint64 periodSeconds;
    }

    /// @notice The delay buffer data.
    /// @param bufferBlocks The block buffer.
    /// @param bufferSeconds The time buffer in seconds.
    /// @param roundOffBlocks The round off in blocks since the last replenish.
    /// @param roundOffSeconds The round off in seconds since the last replenish.
    /// @param prevDelay The delay of the previous batch.
    struct BufferData {
        uint64 bufferBlocks;
        uint64 bufferSeconds;
        uint64 syncExpiryBlockNumber;
        uint64 syncExpiryTimestamp;
        uint64 roundOffBlocks;
        uint64 roundOffSeconds;
        DelayHistory prevDelay;
    }

    /// @notice The history of a sequenced delayed message.
    /// @param blockNumber The block number when the message was created.
    /// @param timestamp The timestamp when the message was created.
    /// @param delayBlocks The amount of blocks the message was delayed.
    /// @param delaySeconds The amount of seconds the message was delayed.
    struct DelayHistory {
        uint64 blockNumber;
        uint64 timestamp;
        uint64 delayBlocks;
        uint64 delaySeconds;
    }

    /// @dev    This function handles synchronizing the sequencer inbox with the delayed inbox.
    ///         It is called by the sequencer inbox when a delayed message is sequenced, proving
    ///         any delays and updating the delay buffers. This function is only called when the
    ///         sequencer inbox has been unexpectedly delayed (rare case)
    /// @notice Synchronizes the sequencer inbox with the delayed inbox.
    /// @param self The delay buffer data
    /// @param bufferConfig The delay buffer settings
    /// @param delayedAcc The delayed accumulator of the first delayed message sequenced
    /// @param beforeDelayedAcc The delayed accumulator before the delayedAcc
    /// @param delayedMessage The first delayed message sequenced
    function sync(
        BufferData storage self,
        BufferConfig memory bufferConfig,
        bytes32 delayedAcc,
        bytes32 beforeDelayedAcc,
        Messages.Message memory delayedMessage
    ) internal {
        if (!Messages.isValidDelayedAccPreimage(delayedAcc, beforeDelayedAcc, delayedMessage)) {
            revert InvalidDelayedAccPreimage();
        }
        updateBuffers(self, bufferConfig, delayedMessage.blockNumber, delayedMessage.timestamp);
        if (
            isOnTime(
                delayedMessage.blockNumber,
                delayedMessage.timestamp,
                bufferConfig.thresholdBlocks,
                bufferConfig.thresholdSeconds
            )
        ) {
            updateSyncValidity(
                self,
                bufferConfig,
                delayedMessage.blockNumber,
                delayedMessage.timestamp
            );
        }
    }

    /// @dev    This function handles resyncing the sequencer inbox with the delayed inbox.
    ///         It is called by the sequencer inbox when a delayed message is sequenced, proving
    ///         the message is on-time and updating the sync validity window. This function is called
    ///         called periodically to renew the sync validity window.
    /// @notice Synchronizes the sequencer inbox with the delayed inbox.
    /// @param beforeDelayedAcc The delayed accumulator before the delayedAcc
    /// @param delayedMessage The delayed message to validate
    /// @param beforeAcc The inbox accumulator before the delayedAcc
    /// @param preimage The preimage to validate
    function resync(
        BufferData storage self,
        BufferConfig memory bufferConfig,
        bytes32 beforeDelayedAcc,
        Messages.Message memory delayedMessage,
        bytes32 beforeAcc,
        Messages.InboxAccPreimage memory preimage
    ) internal {
        // validates the delayed message against the inbox accumulator
        // and proves the delayed message is synced within the delay threshold
        // this is a sufficient condition to prove that any delayed messages sequenced
        // in the current batch are also synced within the delay threshold
        if (!Messages.isValidSequencerInboxAccPreimage(beforeAcc, preimage)) {
            revert InvalidSequencerInboxAccPreimage();
        }
        if (
            !Messages.isValidDelayedAccPreimage(
                preimage.delayedAcc,
                beforeDelayedAcc,
                delayedMessage
            )
        ) {
            revert InvalidDelayedAccPreimage();
        }
        if (
            !isOnTime(
                delayedMessage.blockNumber,
                delayedMessage.timestamp,
                bufferConfig.thresholdBlocks,
                bufferConfig.thresholdSeconds
            )
        ) {
            revert UnexpectedDelay(delayedMessage.blockNumber, delayedMessage.timestamp);
        }

        // calculate the margin of the delay message below the delay threshold
        // no sync / delay proofs are required in this margin `sync validity` period.
        updateSyncValidity(
            self,
            bufferConfig,
            delayedMessage.blockNumber,
            delayedMessage.timestamp
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

    /// @dev    Depletion is rate limited to allow the sequencer to recover properly from outages.
    ///         In the event the batch poster is offline for X hours and Y blocks, when is comes back
    ///         online, and sequences delayed messages, the buffer will not be immediately depleted by
    ///         X hours and Y blocks. Instead, it will be depleted by the time / blocks elapsed in the
    ///         delayed message queue. The buffer saturates at the threshold which allows recovery margin.
    /// @notice Decrements the delay buffer saturating at the threshold
    /// @param start The beginning reference point (prev delay)
    /// @param end The ending reference point (current message)
    /// @param delay The delay to be applied (prev delay)
    /// @param threshold The threshold to saturate at
    /// @param buffer The buffer to be decremented
    function deplete(
        uint64 start,
        uint64 end,
        uint64 delay,
        uint64 threshold,
        uint64 buffer
    ) internal pure returns (uint64) {
        uint64 elapsed = end > start ? end - start : 0;
        uint64 unexpectedDelay = delay > threshold ? delay - threshold : 0;
        uint64 decrease = unexpectedDelay > elapsed ? elapsed : unexpectedDelay;
        // decrease the buffer saturating at zero
        buffer = buffer > decrease ? buffer - decrease : 0;
        // saturate at threshold
        buffer = buffer > threshold ? buffer : threshold;
        return buffer;
    }

    /// @notice Replenishes the delay buffer saturating at maxBuffer
    /// @param start The beginning reference point
    /// @param end The ending reference point
    /// @param buffer The buffer to be replenished
    /// @param maxBuffer The maximum buffer
    /// @param amountPerPeriod The amount to replenish per period
    /// @param period The replenish period
    /// @param roundOff The roundoff from the last replenish
    function replenish(
        uint64 start,
        uint64 end,
        uint64 buffer,
        uint64 maxBuffer,
        uint64 amountPerPeriod,
        uint64 period,
        uint64 roundOff
    ) internal pure returns (uint64, uint64) {
        // add the replenish round off from the last replenish
        uint64 elapsed = end > start ? end - start : 0;
        uint64 replenishAmount = ((elapsed + roundOff) / period) * amountPerPeriod;
        roundOff = (elapsed + roundOff) % period;
        if (maxBuffer - buffer > replenishAmount) {
            buffer += replenishAmount;
        } else {
            // saturate
            buffer = maxBuffer;
            roundOff = 0;
        }
        return (buffer, roundOff);
    }

    /// @notice Conditionally depletes or replenishes the delay buffer
    /// @notice Decrements or replenishes the delay buffer conditionally
    /// @param start The beginning reference point (delayPrev)
    /// @param end The ending reference point (current message)
    /// @param delay The delay to be applied (delayPrev)
    /// @param threshold The threshold to saturate at
    /// @param buffer The buffer to be decremented
    /// @param maxBuffer The maximum buffer
    /// @param amountPerPeriod The amount to replenish per period
    /// @param period The replenish period
    /// @param roundOff The roundoff from the last replenish
    function update(
        uint64 start,
        uint64 end,
        uint64 delay,
        uint64 threshold,
        uint64 buffer,
        uint64 maxBuffer,
        uint64 amountPerPeriod,
        uint64 period,
        uint64 roundOff
    ) internal pure returns (uint64, uint64) {
        if (threshold < delay) {
            // unexpected delay
            buffer = deplete(start, end, delay, threshold, buffer);
            // reset round off to avoid over-replenishment
            roundOff = 0;
        } else if (buffer < maxBuffer) {
            // replenish buffer if depleted
            (buffer, roundOff) = replenish(
                start,
                end,
                buffer,
                maxBuffer,
                amountPerPeriod,
                period,
                roundOff
            );
        }
        return (buffer, roundOff);
    }

    /// @notice Updates the block number buffer.
    /// @param self The delay buffer data
    /// @param bufferConfig The delay buffer settings
    /// @param blockNumber The update block number
    function updateBuffers(
        BufferData storage self,
        BufferConfig memory bufferConfig,
        uint64 blockNumber,
        uint64 timestamp
    ) internal {
        // The prevDelay stores the delay of the previous batch which is
        // used as a starting reference point to calculate an elapsed amount using the current
        // message as the ending reference point.
        (self.bufferBlocks, self.roundOffBlocks) = update(
            self.prevDelay.blockNumber,
            blockNumber,
            self.prevDelay.delayBlocks,
            bufferConfig.thresholdBlocks,
            self.bufferBlocks,
            bufferConfig.maxBufferBlocks,
            bufferConfig.replenishRate.blocksPerPeriod,
            bufferConfig.replenishRate.periodBlocks,
            self.roundOffBlocks
        );

        (self.bufferSeconds, self.roundOffSeconds) = update(
            self.prevDelay.timestamp,
            timestamp,
            self.prevDelay.delaySeconds,
            bufferConfig.thresholdSeconds,
            self.bufferSeconds,
            bufferConfig.maxBufferSeconds,
            bufferConfig.replenishRate.secondsPerPeriod,
            bufferConfig.replenishRate.periodSeconds,
            self.roundOffSeconds
        );

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

    function isValidBufferConfig(BufferConfig memory bufferConfig) internal pure returns (bool) {
        return
            bufferConfig.thresholdBlocks != 0 &&
            bufferConfig.thresholdSeconds != 0 &&
            bufferConfig.maxBufferBlocks != 0 &&
            bufferConfig.maxBufferSeconds != 0 &&
            bufferConfig.replenishRate.blocksPerPeriod != 0 &&
            bufferConfig.replenishRate.secondsPerPeriod != 0 &&
            bufferConfig.replenishRate.periodSeconds != 0 &&
            bufferConfig.replenishRate.periodBlocks != 0 &&
            bufferConfig.replenishRate.secondsPerPeriod <
            bufferConfig.replenishRate.periodSeconds &&
            bufferConfig.replenishRate.blocksPerPeriod < bufferConfig.replenishRate.periodBlocks &&
            bufferConfig.thresholdBlocks <= bufferConfig.maxBufferBlocks &&
            bufferConfig.thresholdSeconds <= bufferConfig.maxBufferSeconds;
    }
}
