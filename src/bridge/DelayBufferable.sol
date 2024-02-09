// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./ISequencerInbox.sol";
import "./IDelayBufferable.sol";

abstract contract DelayBufferable is IDelayBufferable {
    /// @notice The previously proven and sequenced delay message
    DelayCache private prevDelay;

    /// @notice The delay buffer for blocks
    uint64 private bufferBlocks;

    /// @notice The delay buffer for seconds
    uint64 private bufferSeconds;

    /// @notice The block number until delay proofs are required.
    uint64 private syncExpiryBlockNumber;

    /// @notice The timestamp until delay proofs are required.
    uint64 private syncExpiryTimestamp;

    /// @notice The round off errors due to delay buffer replenishment, used for internal accounting.
    uint64 private roundOffBlocks;

    /// @notice The round off errors due to delay buffer replenishment, used for internal accounting.
    uint64 private roundOffTime;

    // see ISequencerInbox.MaxTimeVariation
    uint64 private immutable delayBlocks;
    uint64 private immutable futureBlocks;
    uint64 private immutable delaySeconds;
    uint64 private immutable futureSeconds;

    // see IDelayBufferable.ReplenishRate
    uint64 private immutable secondsPerPeriod;
    uint64 private immutable blocksPerPeriod;
    uint64 private immutable periodSeconds;
    uint64 private immutable periodBlocks;

    // see IDelayBufferable.DelayConfig
    uint64 private immutable thresholdBlocks;
    uint64 private immutable thresholdSeconds;
    uint64 private immutable maxBufferSeconds;
    uint64 private immutable maxBufferBlocks;

    // true if the delay buffer is enabled
    bool public immutable isDelayBufferable;

    uint256 private immutable deployTimeChainId = block.chainid;

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
        // if the delay buffer is disabled, the threshold is set to the maximum value
        isDelayBufferable =
            delayConfig_.thresholdBlocks != type(uint64).max &&
            delayConfig_.thresholdSeconds != type(uint64).max;
        if (isDelayBufferable) {
            bufferBlocks = delayConfig_.maxBufferBlocks;
            bufferSeconds = delayConfig_.maxBufferSeconds;
            syncExpiryBlockNumber = uint64(block.number) + delayConfig_.thresholdBlocks;
            syncExpiryTimestamp = uint64(block.timestamp) + delayConfig_.thresholdSeconds;
        }
    }

    /// @dev This proves the current batch is not delayed.
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
            (uint64(block.number) - delayedMessage.blockNumber <= thresholdBlocks) &&
            (uint64(block.timestamp) - delayedMessage.timestamp <= thresholdSeconds));
    }

    /// @notice Updates the time / block until no delay proofs are required.
    function updateSyncValidity(
        bool cacheFullBuffer,
        uint64 blockNumber,
        uint64 timestamp
    ) internal {
        // update the sync proof validity window
        syncExpiryBlockNumber = uint64(block.number) + thresholdBlocks - blockNumber;
        syncExpiryTimestamp = uint64(block.timestamp) + thresholdSeconds - timestamp;
        // as a gas opt, optionally cache the sync expiry for full buffer state
        // this state is packed with batch poster authentication so no extra storage reads are required
        if (
            cacheFullBuffer && bufferBlocks == maxBufferBlocks && bufferSeconds == maxBufferSeconds
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
        // first check the happy case where the buffer is full
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

    /// @dev    This is the `happy path` where no extra proofs are required.
    /// @notice Returns true if the inbox is in a synced state (no unexpectedly delayed messages)
    function isSynced() internal view returns (bool isSynced_) {
        isSynced_ = false;

        // first check if the synced state is cached
        (uint64 expiryBlockNumber, uint64 expiryTimestamp) = cachedFullBufferExpiry();
        // within the fullBufferExpiry window, the inbox is in a synced state
        if (block.number < expiryBlockNumber && block.timestamp < expiryTimestamp) {
            isSynced_ = true;
        } else if (block.number < syncExpiryBlockNumber && block.timestamp < syncExpiryTimestamp) {
            // otherwise check the sync proof validity window
            isSynced_ = true;
        }
    }

    /// @dev    The prevDelay stores the delay of the previous batch which is
    ///         used as a starting reference point to calculate an elapsed amount
    ///         using the current message as the ending reference point. The buffer
    ///         saturates at the threshold which saves the sequencer margin to catch up.
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
    /// @param repelenishRoundoff The roundoff from the last replenish
    /// @param replenishPeriod The replenish period
    /// @param replenishAmountPerPeriod The amount to replenish per period
    /// @param buffer The buffer to be replenished
    /// @param maxBuffer The maximum buffer
    function replenish(
        uint64 start,
        uint64 end,
        uint64 buffer,
        uint64 maxBuffer,
        uint64 replenishAmountPerPeriod,
        uint64 replenishPeriod,
        uint64 repelenishRoundoff
    ) internal pure returns (uint64, uint64) {
        // add the replenish round off from the last replenish
        uint64 elapsed = end > start ? end - start + repelenishRoundoff : 0;
        uint64 replenishAmount = (elapsed / replenishPeriod) * replenishAmountPerPeriod;
        repelenishRoundoff = elapsed % replenishPeriod;
        buffer += replenishAmount;
        // saturate
        if (buffer > maxBuffer) {
            buffer = maxBuffer;
            repelenishRoundoff = 0;
        }
        return (buffer, repelenishRoundoff);
    }

    /// @notice Updates the delay buffers
    function updateBuffers(uint64 blockNumber, uint64 timestamp) internal {
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
        (bufferSeconds, roundOffTime) = updateBuffer(
            prevDelay.timestamp,
            timestamp,
            prevDelay.delaySeconds,
            thresholdSeconds,
            bufferSeconds,
            maxBufferSeconds,
            secondsPerPeriod,
            periodSeconds,
            roundOffTime
        );

        // store a new starting reference point
        prevDelay = DelayCache({
            blockNumber: blockNumber,
            timestamp: timestamp,
            delayBlocks: uint64(block.number) - blockNumber,
            delaySeconds: uint64(block.timestamp) - timestamp
        });
    }

    /// @dev    The prevDelay stores the delay of the previous batch.
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
        if (delay > threshold) {
            // unsynced: prev batch is late
            // deplete delay buffers due previous batch
            buffer = deplete(start, end, delay, threshold, buffer);
            roundOff = 0;
        } else if (buffer < maxBuffer) {
            // replenish delay buffer if depleted
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

    /// @dev    The delay buffer can change due to pending depletion in the delay cache.
    ///         This function applies pending buffer changes to calculate the force inclusion deadline.
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

    function delayBuffer() public view override returns (uint64, uint64) {
        return (bufferBlocks, bufferSeconds);
    }

    function syncExpiry() public view override returns (uint64, uint64) {
        return (syncExpiryBlockNumber, syncExpiryTimestamp);
    }

    function cachedFullBufferExpiry() internal view virtual returns (uint64, uint64);

    function cacheFullBufferExpiry(uint64, uint64) internal virtual;
}
