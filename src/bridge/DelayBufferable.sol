// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import {InvalidDelayProof, InvalidSyncProof} from "../libraries/Error.sol";
import "./DelayBuffer.sol";
import "./ISequencerInbox.sol";
import "./IDelayBufferable.sol";

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

    DelayBuffer.DelayBufferData public delayBufferData;
    using DelayBuffer for DelayBuffer.DelayBufferData;

    /// @dev    When messages are sequenced a margin below the delay threshold, that margin defines
    ///         a sync state during which no delay proofs are required.
    /// @notice The block number until delay proofs are required.
    uint64 public syncExpiryBlockNumber;

    /// @dev    When messages are sequenced a margin below the delay threshold, that margin defines
    ///         a sync state during which no delay proofs are required.
    /// @notice The timestamp until delay proofs are required.
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

    function sync(
        bytes32 delayedAcc,
        bytes32 beforeDelayedAcc,
        Messages.Message memory delayedMessage
    ) internal {
        if (!Messages.isValidDelayedAccPreimage(delayedAcc, beforeDelayedAcc, delayedMessage)) {
            revert InvalidDelayProof();
        }

        updateBuffers(delayedMessage.blockNumber, delayedMessage.timestamp);

        if (isSynced(delayedMessage.blockNumber, delayedMessage.timestamp)) {
            updateSyncValidity(delayedMessage.blockNumber, delayedMessage.timestamp);
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
        if (!isValidSyncProof(beforeDelayedAcc, delayedMessage, beforeAcc, preimage)) {
            revert InvalidSyncProof();
        }

        // calculate the margin of the delay message below the delay threshold
        // no sync / delay proofs are required in this margin `sync validity` period.
        updateSyncValidity(delayedMessage.blockNumber, delayedMessage.timestamp);
    }

    /// @dev    Calculates the margin a sequenced message is below the delay threshold
    ///         defining a `sync validity` window during which no delay proofs are required.
    ///         The caching mechanism saves gas when the same batch poster posts multiple batches.
    ///         However, in a round robin scenario, the cache might not be used.
    /// @notice Updates the time / block until no delay proofs are required.
    /// @param blockNumber The block number when the synced message was created.
    /// @param timestamp The timestamp when the synced message was created.
    function updateSyncValidity(uint64 blockNumber, uint64 timestamp) internal {
        assert(blockNumber <= uint64(block.number));
        assert(timestamp <= uint64(block.timestamp));
        // update the sync proof validity window
        syncExpiryBlockNumber = blockNumber + thresholdBlocks;
        syncExpiryTimestamp = timestamp + thresholdSeconds;
        // as a gas opt, optionally cache the sync expiry for full buffer state
        // this state is packed with batch poster authentication so no extra storage reads
        // are required when the same batch poster posts again during the sync validity window

        // first check if the full buffer state is cached
        if (
            isFullBufferCached() ||
            (delayBufferData.bufferBlocks == maxBufferBlocks &&
                delayBufferData.bufferSeconds == maxBufferSeconds)
        ) {
            cacheFullBufferSyncExpiry(blockNumber + thresholdBlocks, timestamp + thresholdSeconds);
        }
    }

    function maxTimeVariationBufferable(
        uint64 bufferBlocks,
        uint64 bufferSeconds
    ) internal view returns (uint64, uint64, uint64, uint64) {
        return (
            bufferBlocks < delayBlocks ? bufferBlocks : delayBlocks,
            futureBlocks,
            bufferSeconds < delaySeconds ? bufferSeconds : delaySeconds,
            futureSeconds
        );
    }

    /// @dev    This is the `sync validity window` during which no proofs are required.
    /// @notice Returns true if the inbox is in a synced state (no unexpected delays are possible)
    function isFullBufferCached() internal view returns (bool) {
        (
            uint256 _fullBufferSyncBlockNumber,
            uint256 _fullBufferSyncExpiryTimestamp
        ) = cachedFullBufferSyncExpiry();
        // first check if the full buffer state is cached
        if (
            block.number < _fullBufferSyncBlockNumber &&
            block.timestamp < _fullBufferSyncExpiryTimestamp
        ) {
            return true;
        } else {
            return false;
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

    /// @dev    This is the `sync validity window` during which no proofs are required.
    /// @notice Returns true if the inbox is in a synced state (no unexpected delays are possible)
    function isSynced() internal view returns (bool isSynced_) {
        // first check if the synced state is cached
        (uint64 expiryBlockNumber, uint64 expiryTimestamp) = cachedFullBufferSyncExpiry();
        // within the fullBufferExpiry window, the inbox is in a synced state
        if (block.number < expiryBlockNumber && block.timestamp < expiryTimestamp) {
            isSynced_ = true;
        } else if (block.number < syncExpiryBlockNumber && block.timestamp < syncExpiryTimestamp) {
            // otherwise check the sync validity window
            isSynced_ = true;
        }
    }

    function replenishRate() public view returns (uint64, uint64, uint64, uint64) {
        return (secondsPerPeriod, blocksPerPeriod, periodSeconds, periodBlocks);
    }

    function delayConfig() public view returns (uint64, uint64, uint64, uint64) {
        return (thresholdBlocks, thresholdSeconds, maxBufferBlocks, maxBufferSeconds);
    }

    function forceInclusionDeadline(
        uint64 blockNumber,
        uint64 timestamp
    ) external view returns (uint64, uint64) {
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
    function cachedFullBufferSyncExpiry() internal view virtual returns (uint64, uint64);

    /// @dev Inheriting contracts must implement this function to fetch the cached full buffer expiry state.
    function cacheFullBufferSyncExpiry(uint64, uint64) internal virtual;
}
