// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import {InvalidDelayedAccPreimage, UnexpectedDelay} from "../libraries/Error.sol";
import "./Messages.sol";
import "./DelayBufferTypes.sol";

/**
 * @title   Manages the delay buffer for the sequencer (SequencerInbox.sol)
 * @notice  Messages are expected to be delayed up to a threshold, beyond which they are unexpected
 *          and deplete a delay buffer. Buffer depletion is preveneted from decreasing too quickly by only
 *          depleting by as many blocks as elapsed in the delayed message queue.
 */
library DelayBuffer {
    uint256 public constant BASIS = 10000;

    /// @dev    Depletion is limited by the elapsed blocks in the delayed message queue to avoid double counting and potential L2 reorgs.
    //          Eg. 2 simultaneous batches sequencing multiple delayed messages with the same 100 blocks delay each
    //          should count once as a single 100 block delay, not twice as a 200 block delay. This also prevents L2 reorg risk in edge cases.
    //          Eg. If the buffer is 300 blocks, decrementing the buffer when processing the first batch would allow the second delay message to be force included before the sequencer could add the second batch.
    //          Buffer depletion also saturates at the threshold instead of zero to allow a recovery margin.
    //          Eg. when the sequencer recovers from an outage, it is able to wait threshold > finality time before queueing delayed messages to avoid L1 reorgs.
    /// @notice Decrements the delay buffer saturating at the threshold
    /// @param start The beginning reference point (prev delay)
    /// @param end The ending reference point (current message)
    /// @param buffer The buffer to be decremented
    /// @param prevDelay The delay to be applied
    /// @param threshold The threshold to saturate at
    function deplete(
        uint256 start,
        uint256 end,
        uint256 buffer,
        uint256 prevDelay,
        uint256 threshold
    ) internal pure returns (uint256) {
        uint256 elapsed = end > start ? end - start : 0;
        uint256 unexpectedDelay = prevDelay > threshold ? prevDelay - threshold : 0;
        if (unexpectedDelay > elapsed) {
            unexpectedDelay = elapsed;
        }
        // decrease the buffer saturating at the threshold
        if (buffer > unexpectedDelay) {
            buffer = buffer - unexpectedDelay;
            if (buffer > threshold) {
                return buffer;
            }
        }
        return threshold;
    }

    /// @notice Replenishes the delay buffer saturating at max
    /// @param start The beginning reference point
    /// @param end The ending reference point
    /// @param buffer The buffer to be replenished
    /// @param max The maximum buffer
    /// @param replenishRateInBasis The amount to replenish the buffer per block in basis points.
    function replenish(
        uint256 start,
        uint256 end,
        uint256 buffer,
        uint256 max,
        uint256 replenishRateInBasis
    ) internal pure returns (uint256) {
        uint256 elapsed = end > start ? end - start : 0;
        // rounds down for simplicity
        uint256 replenishAmount = (elapsed * replenishRateInBasis) / BASIS;
        if (max - buffer > replenishAmount) {
            buffer += replenishAmount;
        } else {
            // saturate
            buffer = max;
        }
        return buffer;
    }

    /// @notice Conditionally updates the buffer. Depletes if the delay is unexpected, otherwise replenishes if the buffer is depleted.
    /// @param start The beginning reference point
    /// @param end The ending reference point
    /// @param buffer The buffer to be updated
    /// @param prevDelay The delay to be applied
    /// @param threshold The threshold to saturate at
    /// @param max The maximum buffer
    /// @param replenishRateInBasis The amount to replenish the buffer per block in basis points.
    function bufferUpdate(
        uint256 start,
        uint256 end,
        uint256 buffer,
        uint256 prevDelay,
        uint256 threshold,
        uint256 max,
        uint256 replenishRateInBasis
    ) internal pure returns (uint256) {
        if (threshold < prevDelay) {
            // deplete due to unexpected delay
            buffer = deplete(start, end, buffer, prevDelay, threshold);
        } else if (buffer < max) {
            // replenish depleted buffer
            buffer = replenish(start, end, buffer, max, replenishRateInBasis);
        }
        return buffer;
    }

    /// @notice Applies full update to buffer data (buffer, sync validity, and prev delay)
    /// @param self The delay buffer data
    /// @param blockNumber The update block number
    function update(BufferData storage self, uint64 blockNumber) internal {
        // The prevDelay stores the delay of the previous batch which is
        // used as a starting reference point to calculate an elapsed amount using the current
        // message as the ending reference point.

        self.bufferBlocks = pendingBufferUpdate(self, blockNumber);

        // store a new starting reference point
        // any buffer updates will be applied retroactively in the next batch post
        self.prevBlockNumber = blockNumber;
        self.prevDelay = uint64(block.number) - blockNumber;

        if (uint64(block.number) - blockNumber <= self.threshold) {
            updateSyncValidity(self, blockNumber);
        }
    }

    /// @dev    The delay buffer can change due to pending depletion / replenishment due to previous delays.
    ///         This function applies pending buffer changes to calculate buffer updates.
    /// @notice Calculates the buffer changes up to the requested block number
    /// @param self The delay buffer data
    /// @param blockNumber The block number to process the delay up to
    function pendingBufferUpdate(BufferData storage self, uint64 blockNumber)
        internal
        view
        returns (uint64)
    {
        return
            uint64(
                bufferUpdate({
                    start: self.prevBlockNumber,
                    end: blockNumber,
                    buffer: self.bufferBlocks,
                    threshold: self.threshold,
                    prevDelay: self.prevDelay,
                    max: self.max,
                    replenishRateInBasis: self.replenishRateInBasis
                })
            );
    }

    /// @dev    Calculates the margin a sequenced message is below the delay threshold
    ///         defining a `sync validity` window during which no delay proofs are required.
    /// @notice Updates the time / block until no delay proofs are required.
    /// @param blockNumber The block number when the synced message was created.
    function updateSyncValidity(BufferData storage self, uint64 blockNumber) internal {
        // saturating at uint64 max handles large threshold settings
        self.syncExpiry = self.threshold > type(uint64).max - blockNumber
            ? type(uint64).max
            : blockNumber + self.threshold;
    }

    /// @dev    This is the `sync validity window` during which no proofs are required.
    /// @notice Returns true if the inbox is in a synced state (no unexpected delays are possible)
    function isSynced(BufferData storage self) internal view returns (bool) {
        return block.number <= self.syncExpiry;
    }

    function isUpdatable(BufferData storage self) internal view returns (bool) {
        // if synced, the buffer can't be depleted
        // if full, the buffer can't be replenished
        // if neither synced nor full, the buffer updatable (depletable / replenishable)
        return !isSynced(self) || self.bufferBlocks < self.max;
    }

    function isValidBufferConfig(BufferConfig memory config) internal pure returns (bool) {
        return
            config.threshold != 0 &&
            config.max != 0 &&
            config.replenishRateInBasis <= BASIS &&
            config.threshold <= config.max;
    }
}
