// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

/// @notice Information about the timings of auction round. All timings measured in seconds
///         Bids can be submitted to the offchain autonomous auctioneer until the auction round closes
///         after which the auctioneer can submit the two highest bids to the auction contract to resolve the auction
struct RoundTimingInfo {
    /// @notice The timestamp when round 0 starts
    uint64 offsetTimestamp;
    /// @notice The total duration (in seconds) of the round
    uint64 roundDurationSeconds;
    /// @notice The number of seconds before the end of the round that the auction round closes
    uint64 auctionClosingSeconds;
    /// @notice A reserve setter account has the rights to set a reserve for a round,
    ///         however they cannot do this within a reserve blackout period.
    ///         The blackout period starts at RoundDuration - AuctionClosingSeconds - ReserveSubmissionSeconds,
    ///         and ends when the auction round is resolved, or the round ends.
    uint64 reserveSubmissionSeconds;
}

library RoundTimingInfoLib {
    /// @notice The current round, given the current timestamp, the offset and the round duration
    function currentRound(RoundTimingInfo memory info) internal view returns (uint64) {
        if (info.offsetTimestamp > block.timestamp) {
            return 0;
        }

        return (uint64(block.timestamp) - info.offsetTimestamp) / info.roundDurationSeconds;
    }

    /// @notice Has the current auction round closed
    function isAuctionRoundClosed(RoundTimingInfo memory info) internal view returns (bool) {
        if (block.timestamp < info.offsetTimestamp) {
            return false;
        }

        uint64 timeInRound = timeIntoRound(info);
        // round closes at AuctionClosedSeconds before the end of the round
        return timeInRound >= info.roundDurationSeconds - info.auctionClosingSeconds;
    }

    /// @notice How far (in seconds) are we throught the current round. Can be 0 at the start of the current round
    function timeIntoRound(RoundTimingInfo memory info) internal view returns (uint64) {
        uint64 timeSinceOffset = (uint64(block.timestamp) - info.offsetTimestamp);
        return timeSinceOffset % info.roundDurationSeconds;
    }

    /// @notice The reserve cannot be set during the blackout period
    ///         This period runs from ReserveSubmissionSeconds before the auction closes and ends when the round resolves, or when the round ends.
    /// @param info Round timing info
    /// @param latestResolvedRound The last auction round number that was resolved
    function isReserveBlackout(RoundTimingInfo memory info, uint64 latestResolvedRound)
        internal
        view
        returns (bool)
    {
        if (block.timestamp < info.offsetTimestamp) {
            // no rounds have started, can't be in blackout
            return false;
        }

        // if we're in round r, we are selling the rights for r+1
        // if the latest round is r+1 that means we've already resolved the auction in r
        // so we are no longer in the blackout period
        uint64 curRound = currentRound(info);
        if (latestResolvedRound == curRound + 1) {
            return false;
        }

        // the round in question hasnt been resolved
        // therefore if we're within ReserveSubmissionSeconds of the auction close then we're in blackout
        // otherwise we're not
        uint64 timeInRound = timeIntoRound(info);
        return timeInRound
            >= (info.roundDurationSeconds - info.auctionClosingSeconds - info.reserveSubmissionSeconds);
    }

    /// @notice Gets the start and end timestamps (seconds) of a specified round
    /// @param info Round timing info
    /// @param round The specified round
    /// @return The timestamp at which the round starts
    /// @return The timestamp at which the round ends
    function roundTimestamps(RoundTimingInfo memory info, uint64 round)
        internal
        pure
        returns (uint64, uint64)
    {
        uint64 roundStart = info.offsetTimestamp + info.roundDurationSeconds * round;
        uint64 roundEnd = roundStart + info.roundDurationSeconds - 1;
        return (roundStart, roundEnd);
    }
}
