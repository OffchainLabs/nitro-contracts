// SPDX-License-Identifier: UNLICENSED
// CHRIS: TODO: choose sol version and license
pragma solidity ^0.8.9;

import "./Errors.sol";

struct ELCRound {
    address expressLaneController;
    uint64 round;
}

// CHRIS: TODO: consider all usages of the these during initialization
// CHRIS: TODO: Invariant: not possible for the rounds in latest rounds to have the same value
library LatestELCRoundsLib {
    // CHRIS: TODO: what values do these functions have during init?


    // CHRIS: TODO: this isnt efficient to do on storage - we may need to return the index or something
    function latestELCRound(ELCRound[2] memory rounds)
        public
        pure
        returns (ELCRound memory, uint8)
    {
        ELCRound memory latestRound = rounds[0];
        uint8 index = 0;
        if (latestRound.round < rounds[1].round) {
            latestRound = rounds[1];
            index = 1;
        }
        return (latestRound, index);
    }

    function resolvedRound(ELCRound[2] storage latestResolvedRounds, uint64 round)
        internal
        view
        returns (ELCRound storage)
    {
        if (latestResolvedRounds[0].round == round) {
            return latestResolvedRounds[0];
        } else if (latestResolvedRounds[1].round == round) {
            return latestResolvedRounds[1];
        } else {
            revert RoundNotResolved(round);
        }
    }

    function setResolvedRound(
        ELCRound[2] storage latestResolvedRounds,
        uint64 round,
        address expressLaneController
    ) internal {
        (ELCRound memory lastRoundResolved, uint8 index) = latestELCRound(latestResolvedRounds);
        // Invariant: lastAuctionRound.round should never be > round if called during resolve auction except during initialization
        if (lastRoundResolved.round >= round) {
            revert RoundAlreadyResolved(round);
        }

        // dont replace the newest round, use the oldest slot
        uint8 oldestRoundIndex = index ^ 1;
        latestResolvedRounds[oldestRoundIndex] = ELCRound(expressLaneController, round);
    }
}