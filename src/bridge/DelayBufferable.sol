// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import {
    InvalidDelayedAccPreimage,
    InvalidSequencerInboxAccPreimage,
    UnexpectedDelay
} from "../libraries/Error.sol";
import "./DelayBuffer.sol";
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

    // see IDelayBufferable.DelayConfig
    uint64 internal immutable thresholdBlocks;
    uint64 internal immutable thresholdSeconds;
    uint64 internal immutable maxBufferBlocks;
    uint64 internal immutable maxBufferSeconds;

    // see IDelayBufferable.ReplenishRate
    uint64 internal immutable secondsPerPeriod;
    uint64 internal immutable blocksPerPeriod;
    uint64 internal immutable periodSeconds;
    uint64 internal immutable periodBlocks;

    using DelayBuffer for DelayBuffer.DelayBufferData;
    DelayBuffer.DelayBufferData public delayBufferData;

    /// @dev    When messages are sequenced a margin below the delay threshold, that margin defines
    ///         a sync state during which no delay proofs are required.
    /// @notice The block number until delay proofs are not required.
    uint64 public syncExpiryBlockNumber;

    /// @dev    When messages are sequenced a margin below the delay threshold, that margin defines
    ///         a sync state during which no delay proofs are required.
    /// @notice The timestamp until delay proofs are not required.
    uint64 public syncExpiryTimestamp;

    constructor(
        ISequencerInbox.MaxTimeVariation memory maxTimeVariation_,
        IDelayBufferable.ReplenishRate memory replenishRate_,
        IDelayBufferable.Config memory config_
    ) {
        delayBlocks = maxTimeVariation_.delayBlocks;
        delaySeconds = maxTimeVariation_.delaySeconds;
        futureBlocks = maxTimeVariation_.futureBlocks;
        futureSeconds = maxTimeVariation_.futureSeconds;
        blocksPerPeriod = replenishRate_.blocksPerPeriod;
        secondsPerPeriod = replenishRate_.secondsPerPeriod;
        periodBlocks = replenishRate_.periodBlocks;
        periodSeconds = replenishRate_.periodSeconds;
        thresholdBlocks = config_.thresholdBlocks;
        thresholdSeconds = config_.thresholdSeconds;
        maxBufferBlocks = config_.maxBufferBlocks;
        maxBufferSeconds = config_.maxBufferSeconds;
        // initially full buffer
        delayBufferData.bufferBlocks = maxBufferBlocks;
        delayBufferData.bufferSeconds = maxBufferSeconds;
    }

    /// @dev    This function handles synchronizing the sequencer inbox with the delayed inbox.
    ///         It is called by the sequencer inbox when a delayed message is sequenced, proving
    ///         any delays and updating the delay buffers. This function is only called when the
    ///         sequencer inbox has been unexpectedly delayed (rare case)
    /// @notice Synchronizes the sequencer inbox with the delayed inbox.
    /// @param delayedAcc The most recent delayed accumulator sequenced / read
    /// @param beforeDelayedAcc The delayed accumulator before the delayedAcc
    /// @param delayedMessage The delayed message to validate
    function sync(
        bytes32 delayedAcc,
        bytes32 beforeDelayedAcc,
        Messages.Message memory delayedMessage
    ) internal {
        if (!Messages.isValidDelayedAccPreimage(delayedAcc, beforeDelayedAcc, delayedMessage)) {
            revert InvalidDelayedAccPreimage(delayedAcc, beforeDelayedAcc, delayedMessage);
        }

        updateBuffers(delayedMessage.blockNumber, delayedMessage.timestamp);

        if (isOnTime(delayedMessage.blockNumber, delayedMessage.timestamp)) {
            updateSyncValidity(delayedMessage.blockNumber, delayedMessage.timestamp);
        }
    }

    /// @dev    This function handles resynchronizing the sequencer inbox with the delayed inbox.
    ///         It is called by the sequencer inbox when a delayed message is sequenced, proving
    ///         the message is on-time and updating the sync validity window. This function is called
    ///         called periodically to renew the sync validity window.
    /// @notice Synchronizes the sequencer inbox with the delayed inbox.
    /// @param beforeDelayedAcc The delayed accumulator before the delayedAcc
    /// @param delayedMessage The delayed message to validate
    /// @param beforeAcc The inbox accumulator before the delayedAcc
    /// @param preimage The preimage to validate
    function resync(
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
            revert InvalidSequencerInboxAccPreimage(beforeAcc, preimage);
        }
        if (
            !Messages.isValidDelayedAccPreimage(
                preimage.delayedAcc,
                beforeDelayedAcc,
                delayedMessage
            )
        ) {
            revert InvalidDelayedAccPreimage(preimage.delayedAcc, beforeDelayedAcc, delayedMessage);
        }
        if (!isOnTime(delayedMessage.blockNumber, delayedMessage.timestamp)) {
            revert UnexpectedDelay(delayedMessage.blockNumber, delayedMessage.timestamp);
        }

        // calculate the margin of the delay message below the delay threshold
        // no sync / delay proofs are required in this margin `sync validity` period.
        updateSyncValidity(delayedMessage.blockNumber, delayedMessage.timestamp);
    }

    /// @dev    Calculates the margin a sequenced message is below the delay threshold
    ///         defining a `sync validity` window during which no delay proofs are required.
    /// @notice Updates the time / block until no delay proofs are required.
    /// @param blockNumber The block number when the synced message was created.
    /// @param timestamp The timestamp when the synced message was created.
    function updateSyncValidity(uint64 blockNumber, uint64 timestamp) internal {
        assert(blockNumber <= uint64(block.number));
        assert(timestamp <= uint64(block.timestamp));
        // update the sync proof validity window
        if (syncExpiryBlockNumber < blockNumber + thresholdBlocks) {
            syncExpiryBlockNumber = blockNumber + thresholdBlocks;
        }
        if (syncExpiryTimestamp < timestamp + thresholdSeconds) {
            syncExpiryTimestamp = timestamp + thresholdSeconds;
        }
        // as a gas opt, cache the sync expiry for full buffer state packed with
        // batch poster authentication so no extra storage reads are required
        if (
            isFullBufferSyncCacheValid() ||
            (delayBufferData.bufferBlocks == maxBufferBlocks &&
                delayBufferData.bufferSeconds == maxBufferSeconds)
        ) {
            cacheFullBufferSyncExpiry(blockNumber + thresholdBlocks, timestamp + thresholdSeconds);
        }
    }

    function updateBuffers(uint64 blockNumber, uint64 timestamp) internal {
        delayBufferData.updateBuffers(
            blockNumber,
            thresholdBlocks,
            maxBufferBlocks,
            blocksPerPeriod,
            periodBlocks,
            timestamp,
            thresholdSeconds,
            maxBufferSeconds,
            secondsPerPeriod,
            periodSeconds
        );
    }

    function maxTimeVariationBufferable(uint64 bufferBlocks, uint64 bufferSeconds)
        internal
        view
        returns (
            uint64,
            uint64,
            uint64,
            uint64
        )
    {
        return (
            bufferBlocks < delayBlocks ? bufferBlocks : delayBlocks,
            futureBlocks,
            bufferSeconds < delaySeconds ? bufferSeconds : delaySeconds,
            futureSeconds
        );
    }

    function isOnTime(uint64 blockNumber, uint64 timestamp) internal view returns (bool) {
        return ((uint64(block.number) - blockNumber <= thresholdBlocks) &&
            (uint64(block.timestamp) - timestamp <= thresholdSeconds));
    }

    /// @dev    This is the `sync validity window` during which no proofs are required.
    /// @notice Returns true if the inbox is in a synced state (no unexpected delays are possible)
    function isSynced() internal view returns (bool) {
        return (isFullBufferSyncCacheValid() ||
            (block.number < syncExpiryBlockNumber && block.timestamp < syncExpiryTimestamp));
    }

    /// @inheritdoc IDelayBufferable
    function replenishRate()
        public
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

    /// @inheritdoc IDelayBufferable
    function delayConfig()
        public
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

    /// @inheritdoc IDelayBufferable
    function forceInclusionDeadline(uint64 blockNumber, uint64 timestamp)
        external
        view
        returns (uint64, uint64)
    {
        return
            delayBufferData.forceInclusionDeadline(
                blockNumber,
                timestamp,
                thresholdBlocks,
                thresholdSeconds,
                delayBlocks,
                delaySeconds
            );
    }

    /// @dev Inheriting contracts must implement this function to cache the full buffer expiry state.
    function isFullBufferSyncCacheValid() internal view virtual returns (bool);

    /// @dev Inheriting contracts must implement this function to fetch the cached full buffer expiry state.
    function cacheFullBufferSyncExpiry(uint64, uint64) internal virtual;
}
