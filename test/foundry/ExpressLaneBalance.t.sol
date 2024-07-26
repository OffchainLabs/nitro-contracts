// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/express-lane-auction/Balance.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract BalanceImp {
    using BalanceLib for Balance;

    Balance tmp;
    Balance empty;

    modifier setTmp(Balance memory bal) {

        _;

    }

    function balanceAtRound(Balance memory bal, uint64 round) public returns (uint256) {
        tmp = bal;
        uint256 balance = tmp.balanceAtRound(round);
        tmp = empty;
        return balance;
    }

    // function withdrawableBalanceAtRound(Balance , uint64 round)
    //     internal
    //     view
    //     returns (uint256)
    // {
    //     return _balanceOf[accoutn].withdrawableBalanceAtRound(account, round);
    // }

    // /// @notice Increase a balance by a specified amount
    // ///         Will cancel a withdrawal if called after a withdrawal has been initiated
    // /// @param bal The balance info
    // /// @param amount The amount to increase the balance by
    // function increase(Balance storage bal, uint256 amount) internal {
    //     // no point increasing if no amount is being supplied
    //     if (amount == 0) {
    //         revert ZeroAmount();
    //     }

    //     // if the balance have never been used before then balance and withdrawal round will be 0
    //     // in this case we initialize the balance by setting the withdrawal round into the future
    //     // if a withdrawal for the balance has been initialized (withdrawal round != 0 and != max)
    //     // then we cancel that initiated withdrawal. We do this since if a increase is being made that
    //     // means a user wishes to increase their balance, not withdraw it.
    //     if (bal.withdrawalRound != type(uint64).max) {
    //         bal.withdrawalRound = type(uint64).max;
    //     }

    //     bal.balance += amount;
    // }

    // /// @notice Reduce a balance immediately. The balance must already be greater than the amount
    // ///         and a withdrawal has been initiated for this balance it must be occuring in
    // ///         a round after the supplied round. Withdrawals earlier than that will block this reduce.
    // /// @param bal The balance to reduce
    // /// @param amount The amount to reduce by
    // /// @param round The round to check withdrawals against. A withdrawal after this round will be ignored
    // ///              and the balance reduced anyway, withdrawals before or on this round will be respected
    // ///              and the reduce will revert
    // function reduce(
    //     Balance storage bal,
    //     uint256 amount,
    //     uint64 round
    // ) internal {
    //     if (amount == 0) {
    //         revert ZeroAmount();
    //     }

    //     if (balanceAtRound(bal, round) < amount) {
    //         revert InsufficientBalance(amount, balanceAtRound(bal, round));
    //     }

    //     // is there a withdrawal in progress
    //     bal.balance -= amount;
    // }

    // /// @notice Initiate a withdrawal. A withdrawal is a reduction of the full amount.
    // ///         Withdrawal is a two step process initialization and finalization. Finalization is only
    // ///         possible two rounds after the supplied round parameter. This is
    // ///         so that balance cannot be reduced unexpectedly without notice. An external
    // ///         observer can see that a withdrawal has been initiated, and will therefore
    // ///         be able to take it into account and not rely on the balance being there.
    // ///         In the case of the auction contract this allows the bidders to withdraw their
    // ///         balance, but an auctioneer will know not to accept there bids in the mean time
    // /// @param bal The balance to iniate a reduction on
    // /// @param round The round that the withdrawal will be available in
    // function initiateWithdrawal(Balance storage bal, uint64 round) internal {
    //     if (bal.balance == 0) {
    //         revert ZeroAmount();
    //     }

    //     if (bal.withdrawalRound != type(uint64).max) {
    //         revert WithdrawalInProgress();
    //     }

    //     bal.withdrawalRound = round + 2;
    // }

    // /// @notice Finalize an already initialized withdrawal. Reduces the balance to 0.
    // ///         Can only be called two round after the withdrawal was initiated.
    // /// @param bal The balance to finalize
    // /// @param round The round to check whether withdrawal is valid in. Usually the current round.
    // function finalizeWithdrawal(Balance storage bal, uint64 round) internal returns (uint256) {
    //     uint256 withdrawableBalance = withdrawableBalanceAtRound(bal, round);
    //     if (withdrawableBalance == 0) {
    //         revert NothingToWithdraw();
    //     }

    //     bal.balance = 0;
    //     return withdrawableBalance;
    // }






}


contract ExpressLaneBalanceTest is Test {


}

