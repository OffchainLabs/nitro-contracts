// SPDX-License-Identifier: UNLICENSED
// CHRIS: TODO: choose sol version and license
pragma solidity ^0.8.9;

import "./Errors.sol";

struct Balance2 {
    uint256 balance;
    uint64 withdrawalRound;
}

library Balance2Lib {
    function increase(Balance2 storage bal, uint256 amount) internal {
        if (amount == 0) {
            revert ZeroAmount();
        }

        // there is no balance in this account
        // initialize the round to show that the before balance is the correct one
        if (bal.balance == 0) {
            bal.withdrawalRound = type(uint64).max;
        }

        if (bal.withdrawalRound != type(uint64).max) {
            // should be revert WithdrawalInProgress()
            revert ZeroAmount();
        }

        // always increase the balance before
        bal.balance += amount;
    }

    // CHRIS: TODO: this whole interplay is complicated, it should be really should it?
    function reduce(Balance2 storage bal, uint256 amount, uint64 round) internal {
        if (balanceAtRound(bal, round) < amount) {
            // CHRIS: TODO: could just check both before and after and then we dont require the round?
            revert InsufficientBalance(amount, balanceAtRound(bal, round));
        }

        // is there a withdrawal in progress
        bal.balance -= amount;

        if (bal.withdrawalRound != type(uint64).max) {
            // pending withdrawal in progress, rest it if we hit zero
            if (bal.balance == 0) {
                bal.withdrawalRound = type(uint64).max;
            }
        }
    }

    function initiateReduce(Balance2 storage bal, uint256 amount, uint64 round) internal {
        if (amount == 0) {
            revert ZeroAmount();
        }

        if (bal.withdrawalRound != type(uint64).max) {
            // revert bool
            revert WithdrawalInProgress(0);
        }

        if (bal.balance < amount) {
            revert InsufficientBalance(amount, bal.balance);
        }

        // it will show up in the next round, and be withdrawable at round + 2
        bal.withdrawalRound = round + 2;
    }

    function finalizeReduce(Balance2 storage bal, uint64 round) internal returns (uint256) {
        uint256 withdrawableBal = withdrawableBalanceAtRound(bal, round);
        if (withdrawableBal == 0) {
            // should be WithdrawalNotInProgress
            revert NothingToWithdraw();
        }

        // CHRIS: TODO: double storage pull again
        bal.withdrawalRound = type(uint64).max;
        bal.balance = 0;

        return withdrawableBal;
    }

    function balanceAtRound(Balance2 storage bal, uint64 round) internal view returns (uint256) {
        if (bal.withdrawalRound != type(uint64).max && round >= bal.withdrawalRound) {
            return bal.balance;
        } else {
            return 0;
        }
    }

    function withdrawableBalanceAtRound(Balance2 storage bal, uint64 round) internal view returns (uint256) {
        if (bal.withdrawalRound != type(uint64).max && round > bal.withdrawalRound) {
            return bal.balance;
        } else {
            return 0;
        }
    }
}

// this system only works if we're happy to do 3 lookups for empty val
// actually, in this case we can, we dont really want this huh
struct Balance {
    // CHRIS: TODO: set to uint64
    uint256 balanceBeforeRound;
    uint64 round;
    uint256 balanceAfterRound;
}

// Do we forsee a world where the bidding round and the controlling round have different lengths?
// bidding round < controlling round - this is fine and can be enforced by the auctioneer offchain
// controlling round < bidding round - this is more awkward.
// CHRIS: TODO: raise this in the tx-ordering channel. Will we ever want controlling round < bidding round. Where the bidding rounds would now be overlapping.

// CHRIS: TODO: we should set the controlling round to be r, and the bidding round to be r-1
// CHRIS: TODO: lets separate the two. The controlling round is r. The bidding period happens to correspond to a r
// CHRIS: TODO: "The controlling round r is sold during the bidding round r-1."
// CHRIS: TODO: "In round r-1 parties bid for control of round r".

// CHRIS: TODO: docs for these and at least the overall logic as to why this is a separate lib
// CHRIS: TODO: what guarantees should be held here?
// CHRIS: TODO: one thing to test is what these functions do before round 0, also what about unitialised balances
// CHRIS: TODO: we can recognise an unitialised balance as it has 0,0,0 - which is something that an intiialized balance never has

// we collect these balance related functions together so that we can see the possible ways in which a
// balance can be updated

// ordering
// it should be possible to call any of these in any order - particularly the updating functions
// and never end up in an inconsistent state so we keep them all together so we can reason about that

library BalanceLib {
    function isPendingReduction(Balance storage bal) internal view returns (bool, uint64) {
        uint64 reductionRound = bal.round;
        return (reductionRound != type(uint64).max, reductionRound);
    }

    function increase(Balance storage bal, uint256 amount) internal {
        if (amount == 0) {
            revert ZeroAmount();
        }

        // there is no balance in this account
        // initialize the round to show that the before balance is the correct one
        if (bal.balanceBeforeRound == 0) {
            bal.round = type(uint64).max;
        }

        // always increase the balance before
        bal.balanceBeforeRound += amount;

        // a withdrawal may be pending, in this case adding funds
        // should increase the balance before and the balance after
        (bool isPendingR,) = isPendingReduction(bal);
        if (isPendingR) {
            // CHRIS:TODO: could this be a bit trickier than it looks? increasing the after value at an arbitrary time?
            bal.balanceAfterRound += amount;
        }
    }

    // CHRIS: TODO: this whole interplay is complicated, it should be really should it?
    function reduce(Balance storage bal, uint256 amount, uint64 round) internal {
        if (balanceAtRound(bal, round) < amount) {
            // CHRIS: TODO: could just check both before and after and then we dont require the round?
            revert InsufficientBalance(amount, balanceAtRound(bal, round));
        }

        // is there a withdrawal in progress
        uint256 balRound = bal.round;
        if (balRound != type(uint64).max) {
            // reduce the before amount
            bal.balanceBeforeRound -= amount;

            // update the balance after, this determines how much we'll later be able to withdraw
            if (bal.balanceAfterRound >= amount) {
                bal.balanceAfterRound -= amount;
            } else {
                bal.balanceAfterRound = 0;
            }

            // if we ever get to 0 it means the pending withdrawal was wiped out
            // so this cancels the pending withdrawal completely
            if (bal.balanceBeforeRound == 0) {
                bal.round = type(uint64).max;
            }
        } else {
            // no withdrawal in progress
            bal.balanceBeforeRound -= amount;
        }
    }

    function initiateReduce(Balance storage bal, uint256 amount, uint64 round) internal {
        if (amount == 0) {
            revert ZeroAmount();
        }

        if (bal.round != type(uint64).max) {
            revert WithdrawalInProgress(bal.balanceBeforeRound - bal.balanceAfterRound);
        }

        if (bal.balanceBeforeRound < amount) {
            revert InsufficientBalance(amount, bal.balanceBeforeRound);
        }

        // CHRIS: TODO: would be nice to put all this together into an update call, then we can test it never can be called twice
        bal.balanceAfterRound = bal.balanceBeforeRound - amount;
        // it will show up in the next round, and be withdrawable at round + 2
        bal.round = round + 2;
    }

    function finalizeReduce(Balance storage bal, uint64 round) internal returns (uint256) {
        uint256 withdrawableBal = withdrawableBalanceAtRound(bal, round);
        // CHRIS: TODO: could also check that there is no withdrawal in progress
        if (withdrawableBal == 0) {
            // should be WithdrawalNotInProgress
            revert NothingToWithdraw();
        }

        // CHRIS: TODO: double storage pull again
        bal.round = type(uint64).max;
        bal.balanceBeforeRound = bal.balanceAfterRound;
        bal.balanceAfterRound = 0;

        return withdrawableBal;
    }

    function balanceAtRound(Balance storage bal, uint64 round) internal view returns (uint256) {
        if (bal.round != type(uint64).max && round >= bal.round) {
            return bal.balanceAfterRound;
        } else {
            return bal.balanceBeforeRound;
        }
    }

    function withdrawableBalanceAtRound(Balance storage bal, uint64 round) internal view returns (uint256) {
        if (bal.round != type(uint64).max && round >= bal.round) {
            return bal.balanceBeforeRound - bal.balanceAfterRound;
        } else {
            return 0;
        }
    }
}
