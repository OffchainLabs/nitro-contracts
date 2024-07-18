// SPDX-License-Identifier: UNLICENSED
// CHRIS: TODO: choose sol version and license
pragma solidity ^0.8.9;

// CHRIS: TODO: docs and tests in here

struct RoundTimingInfo {
    // CHRIS: TODO: docs in here, measured in seconds
    uint64 offsetTimestamp;
    uint64 biddingStageDuration;
    uint64 resolvingStageDuration;
    uint64 reserveBlackoutStart;
}

library RoundTimingInfoLib {
    // CHRIS: TODO: should these be storage? assess at the end
    function roundDuration(RoundTimingInfo memory info) internal pure returns (uint64) {
        return info.biddingStageDuration + info.resolvingStageDuration;
    }

    function currentRound(RoundTimingInfo memory info) internal view returns (uint64) {
        if (info.offsetTimestamp > block.timestamp) {
            // CHRIS: TODO: Invariant: info.offsetTimestamp > block.timestamp only during initialization and never any other time
            return 0;
        }

        // CHRIS: TODO: test that this rounds down
        return (uint64(block.timestamp) - info.offsetTimestamp) / roundDuration(info);
    }

    // CHRIS: TODO: test boundary conditions 0, biddingStageDuration, biddingStageDuration + resolvingStageDuration
    function isResolvingStage(RoundTimingInfo memory info) internal view returns (bool) {
        if (block.timestamp < info.offsetTimestamp) {
            return false;
        }

        uint64 timeSinceOffset = (uint64(block.timestamp) - info.offsetTimestamp);
        uint64 timeIntoRound = timeSinceOffset % roundDuration(info);
        return timeIntoRound >= info.biddingStageDuration;
    }

    function isBiddingStage(RoundTimingInfo memory info) internal view returns (bool) {
        return !isResolvingStage(info);
    }

    function isReserveBlackout(
        RoundTimingInfo memory info,
        uint64 latestResolvedRound,
        uint64 biddingForRound
    ) internal view returns (bool) {
        // CHRIS: TODO: this whole func should be DRYed out
        if (block.timestamp < info.offsetTimestamp) {
            return false;
        }

        // CHRIS: TODO: we should put this check in a lib, we also have it in the resolve
        if (latestResolvedRound == biddingForRound) {
            // round has been resolved, so we can set reserve for the next round
            return false;
        }

        uint64 timeSinceOffset = (uint64(block.timestamp) - info.offsetTimestamp);
        uint64 timeIntoRound = timeSinceOffset % roundDuration(info);
        return timeIntoRound >= info.reserveBlackoutStart;
    }

    function roundTimestamps(RoundTimingInfo memory info, uint64 round)
        internal
        pure
        returns (uint64, uint64)
    {
        // CHRIS: TODO: when we include updates we need to point out that this is not
        //              accurate for timestamps after the update timestamp - that will be a bit tricky wont it?
        //              all round timing stuff needs reviewing if we include updates

        uint64 roundStart = info.offsetTimestamp + roundDuration(info) * round;
        uint64 roundEnd = roundStart + roundDuration(info) - 1;
        return (roundStart, roundEnd);
    }
}
