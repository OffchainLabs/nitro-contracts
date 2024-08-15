// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Errors.sol";

/// @notice When an auction round is resolved a new express lane controller is chosen for that round
///         An elc round stores that selected express lane controller against the round number
struct ELCRound {
    /// @notice The express lane controller for this round
    address expressLaneController;
    /// @notice The round number
    uint64 round;
}

/// @notice Latest resolved express lane controller auction rounds
//          Only the two latest resolved rounds are stored
library LatestELCRoundsLib {
    /// @notice The last resolved express lane controller round, and its index in the array
    /// @param rounds The stored resolved rounds
    /// @return The last resolved elc round
    /// @return The index of that last resolved round within the supplied array
    function latestELCRound(ELCRound[2] storage rounds)
        internal
        view
        returns (ELCRound storage, uint8)
    {
        ELCRound storage latestRound = rounds[0];
        uint8 index = 0;
        if (latestRound.round < rounds[1].round) {
            latestRound = rounds[1];
            index = 1;
        }
        return (latestRound, index);
    }

    /// @notice Finds the elc round that matches the supplied round. Reverts if no matching round found.
    /// @param latestResolvedRounds The resolved elc rounds
    /// @param round The round number to find a resolved round for
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
            // not resolved or too old
            revert RoundNotResolved(round);
        }
    }

    /// @notice Set a resolved round into the array, overwriting the oldest resolved round
    ///         in the array.
    /// @param latestResolvedRounds The resolved rounds aray
    /// @param round The round to resolve
    /// @param expressLaneController The new express lane controller for that round
    function setResolvedRound(
        ELCRound[2] storage latestResolvedRounds,
        uint64 round,
        address expressLaneController
    ) internal {
        (ELCRound storage lastRoundResolved, uint8 index) = latestELCRound(latestResolvedRounds);
        if (lastRoundResolved.round >= round) {
            revert RoundAlreadyResolved(round);
        }

        // dont replace the newest round, use the oldest slot
        uint8 oldestRoundIndex = index ^ 1;
        latestResolvedRounds[oldestRoundIndex] = ELCRound(expressLaneController, round);
    }
}
