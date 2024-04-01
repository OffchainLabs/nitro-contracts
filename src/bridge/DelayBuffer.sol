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
    /// @dev    This function handles synchronizing the sequencer inbox with the delayed inbox.
    ///         It is called by the sequencer inbox when a delayed message is sequenced, proving
    ///         any delays and updating the delay buffers. This function is only called when the
    ///         sequencer inbox has been unexpectedly delayed (unhappy case)
    /// @notice Synchronizes the sequencer inbox with the delayed inbox.
    /// @param self The delay buffer data
    /// @param bufferConfig The delay buffer settings
    /// @param delayedAcc The delayed accumulator of the first delayed message sequenced
    /// @param delayProof The proof that the delayed message is valid
    function sync( // @review maybe rename this to `delay` and `resync`->`sync`?
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

    /// @dev    This function handles resyncing the sequencer inbox with the delayed inbox.
    ///         It is called by the sequencer inbox when a delayed message is sequenced, proving
    ///         the message is on-time and updating the sync validity window. This function is called
    ///         called periodically to renew the sync validity window.
    /// @notice Synchronizes the sequencer inbox with the delayed inbox.
    /// @param beforeAcc The inbox accumulator before the current batch
    /// @param syncProof The proof that the delayed message is valid
    function resync(
        BufferData storage self,
        BufferConfig memory bufferConfig,
        bytes32 beforeAcc,
        SyncProof memory syncProof
    ) internal {
        // validates the delayed message against the inbox accumulator
        // and proves the delayed message is synced within the delay threshold
        // this is a sufficient condition to prove that any delayed messages sequenced
        // in the current batch are also synced within the delay threshold
        if (!Messages.isValidSequencerInboxAccPreimage(beforeAcc, syncProof.preimage)) {
            revert InvalidSequencerInboxAccPreimage();
        }
        if (
            !Messages.isValidDelayedAccPreimage(
                syncProof.preimage.delayedAcc,
                syncProof.beforeDelayedAcc,
                syncProof.delayedMessage
            )
        ) {
            revert InvalidDelayedAccPreimage();
        }
        if (
            !isOnTime(
                syncProof.delayedMessage.blockNumber,
                syncProof.delayedMessage.timestamp,
                bufferConfig.thresholdBlocks,
                bufferConfig.thresholdSeconds
            )
        ) {
            revert UnexpectedDelay(
                syncProof.delayedMessage.blockNumber,
                syncProof.delayedMessage.timestamp
            );
        }

        // calculate the margin of the delay message below the delay threshold
        // no sync / delay proofs are required in this margin `sync validity` period.
        updateSyncValidity(
            self,
            bufferConfig,
            syncProof.delayedMessage.blockNumber,
            syncProof.delayedMessage.timestamp
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
        // @review we can also prevent this by limiting the value you can set as threshold
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

    // @review  I think a better explaination is capping the depletion to time elasped avoid double counting delays
    //          For example, 2 consecutive batches with 20 minutes delay is still 20 minutes delay, not 40 minutes
    //          Capping the depletion to delayed time elasped allow us track incremental delay properly
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
        if (unexpectedDelay > elapsed) {
            unexpectedDelay = elapsed;
        }
        // decrease the buffer saturating at zero
        buffer = buffer > unexpectedDelay ? buffer - unexpectedDelay : 0;
        // saturate at threshold
        if(buffer < threshold){
            buffer = threshold;
        }
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
        // @review would rather blend (amountPerPeriod, period) together to a fixed unit
        // instead of needing to keep track of 3 terms (amountPerPeriod, period, roundOff)
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

    // @review it might be better we refactor everything to uint256 in this library
    ///         and only cast (and clamp) when we need to return a uint64 for storage
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

    /// @notice Updates both the block number and timestamp buffer.
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
        (self.bufferBlocks, self.roundOffBlocks) = update({
            start: self.prevDelay.blockNumber,
            end: blockNumber,
            delay: self.prevDelay.delayBlocks,
            threshold: bufferConfig.thresholdBlocks,
            buffer: self.bufferBlocks,
            maxBuffer: bufferConfig.maxBufferBlocks,
            amountPerPeriod: bufferConfig.replenishRate.blocksPerPeriod,
            period: bufferConfig.replenishRate.periodBlocks,
            roundOff: self.roundOffBlocks
        });

        (self.bufferSeconds, self.roundOffSeconds) = update({
            start: self.prevDelay.timestamp,
            end: timestamp,
            delay: self.prevDelay.delaySeconds,
            threshold: bufferConfig.thresholdSeconds,
            buffer: self.bufferSeconds,
            maxBuffer: bufferConfig.maxBufferSeconds,
            amountPerPeriod: bufferConfig.replenishRate.secondsPerPeriod,
            period: bufferConfig.replenishRate.periodSeconds,
            roundOff: self.roundOffSeconds
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
