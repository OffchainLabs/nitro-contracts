// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Errors.sol";

/// @notice Account balance and the round at which it can be withdrawn
///         Balances are withdrawn as part of a two step process - initiation and finalization
///         This is so that a bidder can't withdraw their balance after making a bid
///         Instead, if they initiate their withdrawal in round r, they must wait until the beginning of
///         round r+2 before they can withdraw the balance. In the mean time their balance can be used to
///         resolve an auction if it is part of a valid bid, however the auctioneer may choose to
///         reject bids from accounts with an initiated balance withdrawal
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
    /// @notice The available balance at the supplied round. Returns 0 if a withdrawal has been initiated and has
    ///         past the withdrawal round.
    /// @param bal The balance to query
    /// @param round The round to check the balance in
    function balanceAtRound(Balance storage bal, uint64 round) internal view returns (uint256) {
        return bal.balance - withdrawableBalanceAtRound(bal, round);
    }

    /// @notice The withdrawable balance at the supplied round. If a withdrawal has been initiated, the
    ///         supplied round is past the withdrawal round and has yet to be finalized, then the balance
    ///         of this account is returned. Otherwise 0.
    /// @param bal The balance to query
    /// @param round The round to check the withdrawable balance in
    function withdrawableBalanceAtRound(
        Balance storage bal,
        uint64 round
    ) internal view returns (uint256) {
        return round >= bal.withdrawalRound ? bal.balance : 0;
    }

    /// @notice Increase a balance by a specified amount
    ///         Will cancel a withdrawal if called after a withdrawal has been initiated
    /// @param bal The balance info
    /// @param amount The amount to increase the balance by
    function increase(Balance storage bal, uint256 amount) internal {
        // no point increasing if no amount is being supplied
        if (amount == 0) {
            revert ZeroAmount();
        }

        // if the balance have never been used before then balance and withdrawal round will be 0
        // in this case we initialize the balance by setting the withdrawal round into the future
        // if a withdrawal for the balance has been initialized (withdrawal round != 0 and != max)
        // then we cancel that initiated withdrawal. We do this since if a increase is being made that
        // means a user wishes to increase their balance, not withdraw it.
        if (bal.withdrawalRound != type(uint64).max) {
            bal.withdrawalRound = type(uint64).max;
        }

        bal.balance += amount;
    }

    /// @notice Reduce a balance immediately. The balance must already be greater than the amount
    ///         and a withdrawal has been initiated for this balance it must be occuring in
    ///         a round after the supplied round. Withdrawals earlier than that will block this reduce.
    /// @param bal The balance to reduce
    /// @param amount The amount to reduce by
    /// @param round The round to check withdrawals against. A withdrawal after this round will be ignored
    ///              and the balance reduced anyway, withdrawals before or on this round will be respected
    ///              and the reduce will revert
    function reduce(Balance storage bal, uint256 amount, uint64 round) internal {
        uint256 balRnd = balanceAtRound(bal, round);
        // we add a zero check since it's possible for the amount to be zero
        // but even in that case the user must have some balance
        // to enforce that parties that havent done the deposit step cannot take part in the auction
        if (balRnd == 0 || balRnd < amount) {
            revert InsufficientBalance(amount, balRnd);
        }

        bal.balance -= amount;
    }

    /// @notice Initiate a withdrawal. A withdrawal is a reduction of the full amount.
    ///         Withdrawal is a two step process initialization and finalization. Finalization is only
    ///         after the supplied round parameter. The expected usage is to specify a round that is 2
    ///         in the future to ensure that the balance cannot be reduced unexpectedly without notice.
    //          An external observer can see that a withdrawal has been initiated, and will therefore
    ///         be able to take it into account and not rely on the balance being there.
    ///         In the case of the auction contract this allows the bidders to withdraw their
    ///         balance, but an auctioneer will know not to accept there bids in the mean time
    /// @param bal The balance to iniate a reduction on
    /// @param round The round that the withdrawal will be available in. Cannot be specified as the max round
    function initiateWithdrawal(Balance storage bal, uint64 round) internal {
        if (bal.balance == 0) {
            revert ZeroAmount();
        }

        if (round == type(uint64).max) {
            // we use max round to specify that a withdrawal is not taking place
            // so we dont allow it as a withdrawal round. In practice max round should never
            // be reached so this isnt an issue, we just put this here as an additional
            // safety check
            revert WithdrawalMaxRound();
        }

        if (bal.withdrawalRound != type(uint64).max) {
            revert WithdrawalInProgress();
        }

        bal.withdrawalRound = round;
    }

    /// @notice Finalize an already initialized withdrawal. Reduces the balance to 0.
    ///         Can only be called two round after the withdrawal was initiated.
    /// @param bal The balance to finalize
    /// @param round The round to check whether withdrawal is valid in. Usually the current round. Cannot be max round.
    function finalizeWithdrawal(Balance storage bal, uint64 round) internal returns (uint256) {
        if (round == type(uint64).max) {
            // we use max round to specify that a withdrawal is not taking place
            // so we dont allow it as a withdrawal round. In practice max round should never
            // be reached so this isnt an issue, we just put this here as an additional
            // safety check
            revert WithdrawalMaxRound();
        }

        uint256 withdrawableBalance = withdrawableBalanceAtRound(bal, round);
        if (withdrawableBalance == 0) {
            revert NothingToWithdraw();
        }

        bal.balance = 0;
        return withdrawableBalance;
    }
}
