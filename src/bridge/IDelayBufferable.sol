// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

// solhint-disable-next-line compiler-version
pragma solidity ^0.8.0;

import "../libraries/IGasRefunder.sol";
import "./IBridge.sol";
import "./Messages.sol";

interface IDelayBufferable {
    /// @notice The rate at which the delay buffer is replenished.
    /// @param blocksPerPeriod The amount of blocks that is added to the delay buffer every period
    /// @param secondsPerPeriod The amount of time in seconds that is added to the delay buffer every period
    /// @param periodBlocks The amount of blocks that is waited between replenishing the delay buffer
    /// @param periodSeconds The amount of time in seconds that is waited between replenishing the delay buffer
    struct ReplenishRate {
        uint64 blocksPerPeriod;
        uint64 secondsPerPeriod;
        uint64 periodBlocks;
        uint64 periodSeconds;
    }

    /// @notice Delay buffer and delay threshold settings
    /// @param thresholdBlocks The maximum amount of blocks that a message is expected to be delayed
    /// @param thresholdSeconds The maximum amount of time in seconds that a message is expected to be delayed
    /// @param maxBufferBlocks The maximum the delay blocks seconds can be
    /// @param maxBufferSeconds The maximum the delay buffer seconds can be
    struct Config {
        uint64 thresholdBlocks;
        uint64 thresholdSeconds;
        uint64 maxBufferBlocks;
        uint64 maxBufferSeconds;
    }

    /// @notice The cached data of a sequenced delayed message.
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

    /// @notice The data for proving a delayed message against a delayed accumulator
    struct DelayAccPreimage {
        bytes32 beforeDelayedAcc;
        Messages.Message message;
    }

    /// @notice The data for proving a delayed message against an inbox accumulator
    struct InboxAccPreimage {
        bytes32 beforeAccBeforeAcc;
        bytes32 beforeAccDataHash;
        bytes32 beforeAccDelayedAcc;
        DelayAccPreimage delayedAccPreimage;
    }

    function replenishRate()
        external
        view
        returns (
            uint64 secondsPerPeriod,
            uint64 blocksPerPeriod,
            uint64 periodSeconds,
            uint64 periodBlocks
        );

    function delayConfig()
        external
        view
        returns (
            uint64 thresholdSeconds,
            uint64 thresholdBlocks,
            uint64 maxBufferSeconds,
            uint64 maxBufferBlocks
        );

    function forceInclusionDeadline(uint64 blockNumber, uint64 timestamp)
        external
        view
        returns (uint64 blocks, uint64 time);
}
