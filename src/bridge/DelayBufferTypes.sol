// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity >=0.6.9 <0.9.0;

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
