// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Errors.sol";

/// @notice Account balance and the round at which it can be withdrawn
///         Balances are withdrawn as part of a two step process - intiation and finalization
///         This is so that a bidder can't withdraw their balance after making a bid
///         Instead, if they initiate their withdrawal in round r, they must wait until the beginning of
///         round r+2 before they can withdraw the balance. In the mean time their balance can be used to
///         resolve an auction if it is within a valid bid, however the auctioneer may choose to
///         reject bids from accounts with an initiated balance withdrawal
///         Once a withdrawal has been initiated no more balance can be deposited until
///         after the withdrawal has been finalized
struct Balance {
    /// @notice The amount of balance in the account
    uint256 balance;
    /// @notice The round at which all of the balance can be withdrawn
    ///         Is set to uint64.max when no withdrawal has been intiated
    uint64 withdrawalRound;
}

/// @notice Balance mutation and view functionality. This is in it's own library so that we can
//          reason about and test how the different ways balance mutations interact with each other
library BalanceLib {
    /// @notice Has this balance initiated a withdrawal that has yet to be finalized
    function hasInitiatedWithdrawal(Balance storage bal) internal view returns (bool) {
        // since rounds are multiples of seconds they cannot reach uint64.max
        return bal.withdrawalRound != type(uint64).max;
    }

    /// @notice Reset an initiated withdrawal. If a balance has been initiated for withdrawal
    ///         this function cancels it.
    ///         Should be called the first time a balance struct is created
    function resetInitiatedWithdrawal(Balance storage bal) internal {
        if (bal.withdrawalRound != type(uint64).max) {
            bal.withdrawalRound = type(uint64).max;
        }
    }

    /// @notice Check whether the full balance is withdrawable at a specified round
    /// @param bal The balance to check
    /// @param round The round to check withdrawal in
    function isWithdrawnAtRound(Balance storage bal, uint64 round) internal view returns (bool) {
        return round >= bal.withdrawalRound;
    }

    /// @notice The available balance at the supplied round. 0 if a withdrawal has been initiated and has
    ///         past the withdrawal round.
    /// @param bal The balance to query
    /// @param round The round to check the balance in
    function balanceAtRound(Balance storage bal, uint64 round) internal view returns (uint256) {
        return isWithdrawnAtRound(bal, round) ? 0 : bal.balance;
    }

    /// @notice The withdrawable balance at the supplied round. If a withdrawal has been initiated, the
    ///         supplied round is past the withdrawal round and has yet to be finalized, then the balance
    ///         of this account is returned. Otherwise 0.
    /// @param bal The balance to query
    /// @param round The round to check the withdrawable balance in
    function withdrawableBalanceAtRound(Balance storage bal, uint64 round)
        internal
        view
        returns (uint256)
    {
        return isWithdrawnAtRound(bal, round) ? bal.balance : 0;
    }

    /// @notice Increase a balance by a specified amount
    ///         Cannot be called if a withdrawal has been initiated
    /// @param bal The balance info
    /// @param amount The amount to increase the balance by
    function increase(Balance storage bal, uint256 amount) internal {
        // no point increasing if no amount is being supplied
        if (amount == 0) {
            revert ZeroAmount();
        }

        // withdrawal round can only be zero if a balance has never been used
        // since nowhere can a withdrawal round be set to zero
        // we need to initialize a new balance by setting the withdrawal round to max
        if (bal.withdrawalRound == 0) {
            resetInitiatedWithdrawal(bal);
        }

        if (hasInitiatedWithdrawal(bal)) {
            revert WithdrawalInProgress();
        }

        bal.balance += amount;
    }

    /// @notice Reduce a balance immediately. The balance must already be greater than the amount
    ///         and if there a withdrawal has been initiated for this balance it must be occuring in
    ///         a round after the supplied round
    /// @param bal The balance to reduce
    /// @param amount The amount to reduce by
    /// @param round The round to check withdrawals against. A withdrawal after this round will be ignored
    ///              and the balance reduced anyway, withdrawals before or on this round will be respected
    ///              and the reduce will revert
    function reduce(Balance storage bal, uint256 amount, uint64 round) internal {
        if (balanceAtRound(bal, round) < amount) {
            revert InsufficientBalance(amount, balanceAtRound(bal, round));
        }

        // is there a withdrawal in progress
        bal.balance -= amount;

        // if there is currently a pending withdrawal but the balance has been reduce to 0
        // then we should cancel the pending withdrawal as there's no longer anything to withdraw
        if (bal.balance == 0) {
            resetInitiatedWithdrawal(bal);
        }
    }

    /// @notice Initiate a withdrawal. A withdrawal is a reduction of the full amount.
    ///         Withdrawal is a two step process initialization and finalization. Finalization is only
    ///         possible two rounds after the supplied round parameter. This is
    ///         so that balance cannot be reduced unexpectedly without notice. An external
    ///         observer can see that a withdrawal has been initiated, and will therefore
    ///         be able to take it into account and not rely on the balance being there.
    ///         In the case of the auction contract this allows the bidders to withdraw their
    ///         balance, but an auctioneer will know not to accept there bids in the mean time
    /// @param bal The balance to iniate a reduction on
    /// @param round The round that the initiation is occuring within. Withdrawal can then be finalized
    ///              two rounds after this supplied round.
    function initiateWithdrawal(Balance storage bal, uint64 round) internal {
        if (bal.balance == 0) {
            revert ZeroAmount();
        }

        if (hasInitiatedWithdrawal(bal)) {
            revert WithdrawalInProgress();
        }

        // We dont make it round + 1 in case the iniation were to occur right at the
        // end of a round. Doing round + 2 ensure observer always have at least one full round
        // to become aware of the future balance change.
        bal.withdrawalRound = round + 2;
    }

    /// @notice Finalize an already initialized withdrawal. Reduces the balance to 0.
    ///         Can only be called two round after the withdrawal was initiated.
    /// @param bal The balance to finalize
    /// @param round The round to check whether withdrawal is valid in. Usually the current round.
    function finalizeWithdrawal(Balance storage bal, uint64 round) internal returns (uint256) {
        uint256 withdrawableBalance = withdrawableBalanceAtRound(bal, round);
        if (withdrawableBalance == 0) {
            revert NothingToWithdraw();
        }

        // CHRIS: TODO: double storage pull again
        resetInitiatedWithdrawal(bal);
        bal.balance = 0;
        return withdrawableBalance;
    }
}

// CHRIS: TODO: balance testing and todos:
// CHRIS: TODO: add a doc about the difference between bidding for round and bidding in round
// CHRIS: TODO: list gurantee of the balance lib
//              1. withdrawal round is 0 only if the balance has never been initialized, otherwise it is 2 or more
//              2. both withdrawable balance and available balance cannot be 0
// CHRIS: TODO: one thing to test is what these functions do before round 0, also what about unitialised balances - should we test that?
// CHRIS: TODO: it should be possible to call any of these in any order - particularly the updating functions. How can we test for this
//              we would need to first define an inconsistent state and then go from there
// CHRIS: TODO: we wanna make sure we're not in a state where we can get trapped, either with funds in there, or with a zero balance or something - those are inconsistent states
//              another inconsistent state is when the balance in there doesnt match what we expect from external reduces etc
