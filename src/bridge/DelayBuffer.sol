// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./ISequencerInbox.sol";

/**
 * @title   Manages the delay buffer for the sequencer (SequencerInbox.sol)
 * @notice  Messages are expected to be delayed up to a threshold, beyond which they are unexpected
 *          and deplete a delay buffer. Buffer depletion is preveneted from decreasing too fast by only
 *          depleting by as many seconds / blocks has elapsed in the delayed message queue.
 */
library DelayBuffer {
    struct DelayHistory {
        uint64 blockNumber;
        uint64 timestamp;
        uint64 delayBlocks;
        uint64 delaySeconds;
    }

    struct DelayBufferData {
        DelayHistory prevDelay;
        uint64 bufferBlocks;
        uint64 bufferSeconds;
        uint64 roundOffBlocks;
        uint64 roundOffSeconds;
    }

    /// @dev    Depletion is rate limited to allow the sequencer to recover properly from outages.
    ///         In the event the batch poster is offline for X hours and Y blocks, when is comes back
    ///         online, and sequences delayed messages, the buffer will not be immediately depleted by
    ///         X hours and Y blocks. Instead, it will be depleted by the time / blocks elapsed in the
    ///         delayed message queue. The buffer saturates at the threshold which allows recovery margin.
    /// @notice Decrements the delay buffer saturating at the threshold
    /// @param start The beginning reference point (delayPrev)
    /// @param end The ending reference point (current message)
    /// @param delay The delay to be applied (delayPrev)
    /// @param threshold The threshold to saturate at
    /// @param buffer The buffer to be decremented
    function deplete(
        uint64 start,
        uint64 end,
        uint64 delay,
        uint64 threshold,
        uint64 buffer
    ) public pure returns (uint64) {
        uint64 elapsed = end > start ? end - start : 0;
        uint64 unexpectedDelay = delay > threshold ? delay - threshold : 0;
        uint64 decrease = unexpectedDelay > elapsed ? elapsed : unexpectedDelay;
        // decrease the buffer saturating at zero
        buffer = decrease > buffer ? 0 : buffer - decrease;
        // saturate at threshold
        buffer = buffer > threshold ? buffer : threshold;
        return buffer;
    }

    /// @dev    The prevDelay stores the delay of the previous batch which is
    ///         used as a starting reference point to calculate an elapsed amount
    ///         using the current message as the ending reference point.
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
    ) public pure returns (uint64, uint64) {
        // add the replenish round off from the last replenish
        uint64 elapsed = end > start ? end - start + roundOff : 0;
        uint64 replenishAmount = (elapsed / period) * amountPerPeriod;
        roundOff = elapsed % period;
        buffer += replenishAmount;
        // saturate
        if (buffer > maxBuffer) {
            buffer = maxBuffer;
            roundOff = 0;
        }
        return (buffer, roundOff);
    }

    /// @notice Conditionally depletes or replenishes the delay buffer
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
    ) public pure returns (uint64, uint64) {
        assert(start <= end);
        if (delay > threshold) {
            // unexpected delay
            buffer = deplete(start, end, delay, threshold, buffer);
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
    function updateBlockNumber(
        DelayBufferData storage self,
        uint64 blockNumber,
        uint64 thresholdBlocks,
        uint64 maxBufferBlocks,
        uint64 blocksPerPeriod,
        uint64 periodBlocks
    ) public {
        // The prevDelay stores the delay of the previous batch which is
        // used as a starting reference point to calculate an elapsed amount using the current
        // message as the ending reference point.
        (self.bufferBlocks, self.roundOffBlocks) = update(
            self.prevDelay.blockNumber,
            blockNumber,
            self.prevDelay.delayBlocks,
            thresholdBlocks,
            self.bufferBlocks,
            maxBufferBlocks,
            blocksPerPeriod,
            periodBlocks,
            self.roundOffBlocks
        );

        // store a new starting reference point
        // any buffer updates will be applied retroactively in the next batch post
        self.prevDelay.blockNumber = blockNumber;
        self.prevDelay.delayBlocks = uint64(block.number) - blockNumber;
    }

    /// @notice Updates the time buffer.
    function updateTimestamp(
        DelayBufferData storage self,
        uint64 timestamp,
        uint64 thresholdSeconds,
        uint64 maxBufferSeconds,
        uint64 secondsPerPeriod,
        uint64 periodSeconds
    ) public {
        // The prevDelay stores the delay of the previous batch which is
        // used as a starting reference point to calculate an elapsed amount using the current
        // message as the ending reference point.
        (self.bufferSeconds, self.roundOffSeconds) = update(
            self.prevDelay.timestamp,
            timestamp,
            self.prevDelay.delaySeconds,
            thresholdSeconds,
            self.bufferSeconds,
            maxBufferSeconds,
            secondsPerPeriod,
            periodSeconds,
            self.roundOffSeconds
        );

        // store a new starting reference point
        // any buffer updates will be applied retroactively in the next batch post
        self.prevDelay.timestamp = timestamp;
        self.prevDelay.delaySeconds = uint64(block.timestamp) - timestamp;
    }

    /// @notice Updates the block number buffer.
    function updateBuffers(
        DelayBufferData storage self,
        uint64 blockNumber,
        uint64 thresholdBlocks,
        uint64 maxBufferBlocks,
        uint64 blocksPerPeriod,
        uint64 periodBlocks,
        uint64 timestamp,
        uint64 thresholdSeconds,
        uint64 maxBufferSeconds,
        uint64 secondsPerPeriod,
        uint64 periodSeconds
    ) public {
        updateTimestamp(
            self,
            timestamp,
            thresholdSeconds,
            maxBufferSeconds,
            secondsPerPeriod,
            periodSeconds
        );
        updateBlockNumber(
            self,
            blockNumber,
            thresholdBlocks,
            maxBufferBlocks,
            blocksPerPeriod,
            periodBlocks
        );
    }

    /// @dev    The delay buffer can change due to pending depletion in the delay cache.
    ///         This function applies pending buffer changes to proactively calculate the force inclusion deadline.
    ///         This is only relevant when the bufferBlocks or bufferSeconds are less than delayBlocks or delaySeconds.
    /// @notice Calculates the upper bounds of the delay buffer
    function forceInclusionDeadline(
        DelayBufferData storage self,
        uint64 blockNumber,
        uint64 timestamp,
        uint64 thresholdBlocks,
        uint64 thresholdSeconds,
        uint64 delayBlocks,
        uint64 delaySeconds
    ) external view returns (uint64, uint64) {
        uint64 _bufferBlocks = deplete(
            self.prevDelay.blockNumber,
            blockNumber,
            self.prevDelay.delayBlocks,
            thresholdBlocks,
            self.bufferBlocks
        );
        uint64 _bufferSeconds = deplete(
            self.prevDelay.timestamp,
            timestamp,
            self.prevDelay.delaySeconds,
            thresholdSeconds,
            self.bufferSeconds
        );
        uint64 _delayBlocks = _bufferBlocks < delayBlocks ? _bufferBlocks : delayBlocks;
        uint64 _delaySeconds = _bufferSeconds < delaySeconds ? _bufferSeconds : delaySeconds;
        return (blockNumber + _delayBlocks, timestamp + _delaySeconds);
    }
}
