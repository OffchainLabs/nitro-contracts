// SPDX-License-Identifier: UNLICENSED
// CHRIS: TODO: choose sol version and license
pragma solidity ^0.8.9;

/// @notice Information about the timings of auction round. All timings measured in seconds
///         Each round is split into a bidding stage where bids are submitted offchain to a
///         an auctioneer service, and a resolving stage where the two highest bids for that round
///         are submitted to the auction contract. 
///         Each round has total duration of bidding duration + resolving duration
struct RoundTimingInfo {
    /// @notice The timestamp when round 0 starts
    uint64 offsetTimestamp; 
    /// @notice The duration of the bidding stage in each round (seconds)
    uint64 biddingStageDuration;
    /// @notice The duration of the resolving stage in each round (seconds)
    uint64 resolvingStageDuration;
    /// @notice An reserve setter account has the rights to set a reserve for a round, 
    ///         however they cannot do this within a reserve blackout period.
    ///         The blackout period starts during the bidding stage, at the reserveBlackoutStart.
    ///         So reserveBlackoutStart must always be less than or equal bidding stage duration
    ///         The reserve blackout ends not at the end of the bidding stage, 
    ///         but when the round is resolved, or the resolving stage ends
    uint64 reserveBlackoutStart;
}

library RoundTimingInfoLib {
    /// @notice The total duration of a round. Bidding duration + resolving duration
    function roundDuration(RoundTimingInfo memory info) internal pure returns (uint64) {
        return info.biddingStageDuration + info.resolvingStageDuration;
    }

    /// @notice The current round, given the current timestamp, the offset and the round duration
    function currentRound(RoundTimingInfo memory info) internal view returns (uint64) {
        if (info.offsetTimestamp > block.timestamp) {
            return 0;
        }

        return (uint64(block.timestamp) - info.offsetTimestamp) / roundDuration(info);
    }

    /// @notice Is it currently the resolving stage in the round
    function isResolvingStage(RoundTimingInfo memory info) internal view returns (bool) {
        if (block.timestamp < info.offsetTimestamp) {
            return false;
        }

        uint64 timeInRound = timeIntoRound(info);
        return timeInRound >= info.biddingStageDuration;
    }

    /// @notice Is it currently the bidding stage. Returns true when current timestamp is before the offset
    function isBiddingStage(RoundTimingInfo memory info) internal view returns (bool) {
        return !isResolvingStage(info);
    }

    /// @notice How far (in seconds) are we throught the current round. Can be 0 at the start of the current round
    function timeIntoRound(RoundTimingInfo memory info) internal view returns(uint64) {
        uint64 timeSinceOffset = (uint64(block.timestamp) - info.offsetTimestamp);
        return timeSinceOffset % roundDuration(info);
    }

    /// @notice The reserve cannot be set during the blackout period
    ///         This period runs from reserveBlackoutPeriodStart up until the round is resolved
    /// @param info Round timing info
    /// @param latestResolvedRound The last auction round number that was resolved
    function isReserveBlackout(
        RoundTimingInfo memory info,
        uint64 latestResolvedRound
    ) internal view returns (bool) {
        if (block.timestamp < info.offsetTimestamp) {
            // no rounds have started, cant be in blackout
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
        // therefore if we're after the blackout start then we're in blackout
        // otherwise we're not
        uint64 timeInRound = timeIntoRound(info);
        return timeInRound >= info.reserveBlackoutStart;
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
        uint64 roundStart = info.offsetTimestamp + roundDuration(info) * round;
        uint64 roundEnd = roundStart + roundDuration(info) - 1;
        return (roundStart, roundEnd);
    }
}
