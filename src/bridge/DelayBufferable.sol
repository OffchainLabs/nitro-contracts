// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./ISequencerInbox.sol";
import "./IDelayBufferable.sol";

/**
 * @title   Manages the delay buffer for the sequencer (SequencerInbox.sol)
 * @notice  Messages are expected to be delayed up to a threshold, beyond which they are unexpected
 *          and deplete a delay buffer. Buffer depletion is preveneted from decreasing too fast by only
 *          depleting by as many seconds / blocks has elapsed in the delayed message queue.
 */
abstract contract DelayBufferable is IDelayBufferable {
    // see ISequencerInbox.MaxTimeVariation
    uint64 internal immutable delayBlocks;
    uint64 internal immutable futureBlocks;
    uint64 internal immutable delaySeconds;
    uint64 internal immutable futureSeconds;

    // see IDelayBufferable.ReplenishRate
    uint64 internal immutable secondsPerPeriod;
    uint64 internal immutable blocksPerPeriod;
    uint64 internal immutable periodSeconds;
    uint64 internal immutable periodBlocks;

    // see IDelayBufferable.DelayConfig
    uint64 internal immutable thresholdBlocks;
    uint64 internal immutable thresholdSeconds;
    uint64 internal immutable maxBufferSeconds;
    uint64 internal immutable maxBufferBlocks;

    // true if the delay buffer is enabled
    bool public immutable isDelayBufferable;

    uint256 internal immutable deployTimeChainId = block.chainid;

    /// @dev This struct stores a beginning reference point to apply
    ///      buffer updates retroactively in the next batch post.
    /// @notice The previously proven and sequenced delay message
    DelayCache internal prevDelay;

    /// @dev Once this buffer is less than delayBlocks, the force inclusion threshold decreases
    /// @notice The delay buffer for blocks
    uint64 internal bufferBlocks;

    /// @dev Once this buffer is less than delaySeconds, the force inclusion threshold decreases
    /// @notice The delay buffer for seconds
    uint64 internal bufferSeconds;

    /// @dev    When messages are sequenced a margin below the delay threshold, that margin defines
    ///         a sync state during which no delay proofs are required.
    /// @notice The block number until delay proofs are required.
    uint64 internal syncExpiryBlockNumber;

    /// @dev    When messages are sequenced a margin below the delay threshold, that margin defines
    ///         a sync state during which no delay proofs are required.
    /// @notice The timestamp until delay proofs are required.
    uint64 internal syncExpiryTimestamp;

    /// @dev    Used for internal accounting.
    /// @notice The round off errors due to delay buffer replenishment
    uint64 internal roundOffBlocks;

    /// @dev    Used for internal accounting.
    /// @notice The round off errors due to delay buffer replenishment
    uint64 internal roundOffSeconds;

    constructor(
        ISequencerInbox.MaxTimeVariation memory maxTimeVariation_,
        ReplenishRate memory replenishRate_,
        DelayConfig memory delayConfig_
    ) {
        delayBlocks = maxTimeVariation_.delayBlocks;
        futureBlocks = maxTimeVariation_.futureBlocks;
        delaySeconds = maxTimeVariation_.delaySeconds;
        futureSeconds = maxTimeVariation_.futureSeconds;
        blocksPerPeriod = replenishRate_.blocksPerPeriod;
        secondsPerPeriod = replenishRate_.secondsPerPeriod;
        periodBlocks = replenishRate_.periodBlocks;
        periodSeconds = replenishRate_.periodSeconds;
        thresholdBlocks = delayConfig_.thresholdBlocks;
        thresholdSeconds = delayConfig_.thresholdSeconds;
        maxBufferBlocks = delayConfig_.maxBufferBlocks;
        maxBufferSeconds = delayConfig_.maxBufferSeconds;
        // if the threshold is set to the maximum value, then the delay buffer is disabled
        isDelayBufferable =
            delayConfig_.thresholdBlocks != type(uint64).max &&
            delayConfig_.thresholdSeconds != type(uint64).max;
        if (isDelayBufferable) {
            // initially the buffers are full
            bufferBlocks = delayConfig_.maxBufferBlocks;
            bufferSeconds = delayConfig_.maxBufferSeconds;
        }
    }

    /// @dev    Proves delayedMessage is not unexpectedly delayed.
    /// @notice Validates a delayed message against a past inbox acc and
    ///         proves the delayed message is not delayed beyond the threshold.
    function isValidSyncProof(
        bytes32 beforeDelayedAcc,
        Messages.Message memory delayedMessage,
        bytes32 beforeAcc,
        Messages.InboxAccPreimage memory preimage
    ) internal view returns (bool) {
        return (Messages.isValidSequencerInboxAccPreimage(beforeAcc, preimage) &&
            Messages.isValidDelayedAccPreimage(
                preimage.delayedAcc,
                beforeDelayedAcc,
                delayedMessage
            ) &&
            isSynced(delayedMessage.blockNumber, delayedMessage.timestamp));
    }

    function isSynced(uint64 blockNumber, uint64 timestamp) internal view returns (bool) {
        return ((uint64(block.number) - blockNumber <= thresholdBlocks) &&
            (uint64(block.timestamp) - timestamp <= thresholdSeconds));
    }

    /// @dev    Calculates the margin a sequenced message is below the delay threshold
    ///         defining a `sync validity` window during which no delay proofs are required.
    ///         The caching mechanism saves gas when the same batch poster posts multiple batches.
    ///         However, in a round robin scenario, the cache might not be used.
    /// @notice Updates the time / block until no delay proofs are required.
    /// @param isCachingRequested Optionally checks if the buffer is full and caches the indicator for gas savings.
    /// @param blockNumber The block number when the synced message was created.
    /// @param timestamp The timestamp when the synced message was created.
    function updateSyncValidity(
        bool isCachingRequested,
        uint64 blockNumber,
        uint64 timestamp
    ) internal {
        assert(blockNumber <= uint64(block.number));
        assert(timestamp <= uint64(block.timestamp));
        // update the sync proof validity window
        syncExpiryBlockNumber = blockNumber + thresholdBlocks;
        syncExpiryTimestamp = timestamp + thresholdSeconds;
        // as a gas opt, optionally cache the sync expiry for full buffer state
        // this state is packed with batch poster authentication so no extra storage reads
        // are required when the same batch poster posts again during the sync validity window
        if (
            isCachingRequested &&
            bufferBlocks == maxBufferBlocks &&
            bufferSeconds == maxBufferSeconds
        ) {
            cacheFullBufferExpiry(blockNumber + thresholdBlocks, timestamp + thresholdSeconds);
        }
    }

    function _chainIdChanged() internal view returns (bool) {
        return deployTimeChainId != block.chainid;
    }

    function maxTimeVariationInternal()
        internal
        view
        returns (
            uint64,
            uint64,
            uint64,
            uint64
        )
    {
        if (_chainIdChanged()) {
            return (1, 1, 1, 1);
        } else if (isDelayBufferable) {
            return maxTimeVariationBufferable();
        } else {
            return (delayBlocks, futureBlocks, delaySeconds, futureSeconds);
        }
    }

    function maxTimeVariationBufferable()
        internal
        view
        returns (
            uint64,
            uint64,
            uint64,
            uint64
        )
    {
        // first check the cache for the full buffer expiry
        (uint64 expiryBlockNumber, uint64 expiryTimestamp) = cachedFullBufferExpiry();
        if (block.number < expiryBlockNumber && block.timestamp < expiryTimestamp) {
            return (delayBlocks, futureBlocks, delaySeconds, futureSeconds);
        } else {
            // otherwise read the buffer state
            return (
                bufferBlocks < delayBlocks ? bufferBlocks : delayBlocks,
                futureBlocks,
                bufferSeconds < delaySeconds ? bufferSeconds : delaySeconds,
                futureSeconds
            );
        }
    }

    /// @dev    This is the `sync validity window` during which no proofs are required.
    /// @notice Returns true if the inbox is in a synced state (no unexpected delays are possible)
    function isSynced() internal view returns (bool isSynced_) {
        // first check if the synced state is cached
        (uint64 expiryBlockNumber, uint64 expiryTimestamp) = cachedFullBufferExpiry();
        // within the fullBufferExpiry window, the inbox is in a synced state
        if (block.number < expiryBlockNumber && block.timestamp < expiryTimestamp) {
            isSynced_ = true;
        } else if (block.number < syncExpiryBlockNumber && block.timestamp < syncExpiryTimestamp) {
            // otherwise check the sync validity window
            isSynced_ = true;
        }
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
    ) internal pure returns (uint64) {
        uint64 elapsed = end > start ? end - start : 0;
        uint64 unexpectedDelay = delay > threshold ? delay - threshold : 0;
        uint64 decrease = unexpectedDelay > elapsed ? elapsed : unexpectedDelay;
        // decrement the buffer saturating at zero
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
    ) internal pure returns (uint64, uint64) {
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
    function updateBuffer(
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

    /// @dev    Updates both the block and time buffers.
    /// @notice Updates the delay buffers
    function updateBuffers(uint64 blockNumber, uint64 timestamp) internal {
        // The prevDelay stores the delay of the previous batch which is
        // used as a starting reference point to calculate an elapsed amount using the current
        // message as the ending reference point.
        (bufferBlocks, roundOffBlocks) = updateBuffer(
            prevDelay.blockNumber,
            blockNumber,
            prevDelay.delayBlocks,
            thresholdBlocks,
            bufferBlocks,
            maxBufferBlocks,
            blocksPerPeriod,
            periodBlocks,
            roundOffBlocks
        );
        (bufferSeconds, roundOffSeconds) = updateBuffer(
            prevDelay.timestamp,
            timestamp,
            prevDelay.delaySeconds,
            thresholdSeconds,
            bufferSeconds,
            maxBufferSeconds,
            secondsPerPeriod,
            periodSeconds,
            roundOffSeconds
        );

        // store a new starting reference point
        // any buffer updates will be applied retroactively in the next batch post
        prevDelay = DelayCache({
            blockNumber: blockNumber,
            timestamp: timestamp,
            delayBlocks: uint64(block.number) - blockNumber,
            delaySeconds: uint64(block.timestamp) - timestamp
        });
    }

    /// @dev    The delay buffer can change due to pending depletion in the delay cache.
    ///         This function applies pending buffer changes to proactively calculate the force inclusion deadline.
    ///         This is only relevant when the bufferBlocks or bufferSeconds are less than delayBlocks or delaySeconds.
    /// @notice Calculates the upper bounds of the delay buffer
    function forceInclusionDeadline(uint64 blockNumber, uint64 timestamp)
        external
        view
        returns (uint64, uint64)
    {
        uint64 _bufferBlocks = deplete(
            prevDelay.blockNumber,
            blockNumber,
            prevDelay.delayBlocks,
            thresholdBlocks,
            bufferBlocks
        );
        uint64 _bufferSeconds = deplete(
            prevDelay.timestamp,
            timestamp,
            prevDelay.delaySeconds,
            thresholdSeconds,
            bufferSeconds
        );
        uint64 _delayBlocks = _bufferBlocks < delayBlocks ? _bufferBlocks : delayBlocks;
        uint64 _delaySeconds = _bufferSeconds < delaySeconds ? _bufferSeconds : delaySeconds;
        return (blockNumber + _delayBlocks, timestamp + _delaySeconds);
    }

    function replenishRate()
        external
        view
        returns (
            uint64,
            uint64,
            uint64,
            uint64
        )
    {
        return (secondsPerPeriod, blocksPerPeriod, periodSeconds, periodBlocks);
    }

    function delayConfig()
        external
        view
        returns (
            uint64,
            uint64,
            uint64,
            uint64
        )
    {
        return (thresholdBlocks, thresholdSeconds, maxBufferBlocks, maxBufferSeconds);
    }

    function delayBuffer() external view override returns (uint64, uint64) {
        return (bufferBlocks, bufferSeconds);
    }

    /// @dev Exposes the synxExpiry state so the sequencer can decide when to renew the sync period.
    function syncExpiry() external view override returns (uint64, uint64) {
        return (syncExpiryBlockNumber, syncExpiryTimestamp);
    }

    /// @dev Inheriting contracts must implement this function to cache the full buffer expiry state.
    function cachedFullBufferExpiry() internal view virtual returns (uint64, uint64);

    /// @dev Inheriting contracts must implement this function to fetch the cached full buffer expiry state.
    function cacheFullBufferExpiry(uint64, uint64) internal virtual;
}
