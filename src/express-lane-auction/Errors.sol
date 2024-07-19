// CHRIS: TODO: update license
// SPDX-License-Identifier: UNLICENSED
// CHRIS: TODO: choose sol version
pragma solidity ^0.8.9;

// CHRIS: TODO: docs and see if al these are actually used
error InsufficientBalance(uint256 amountRequested, uint256 balance);
error InsufficientBalanceAcc(address acount, uint256 amountRequested, uint256 balance);
error RoundDurationTooShort();
error NothingToWithdraw();
error ZeroAmount();
error ZeroBiddingToken();
error WithdrawalInProgress(uint256 amountInWithdrawal);
error RoundAlreadyResolved(uint64 round);
error SameBidder();
error BidsWrongOrder();
error TieBidsWrongOrder();
error AuctionNotClosed();
error ReservePriceTooLow(uint256 reservePrice, uint256 minReservePrice);
error ReservePriceNotMet(uint256 bidAmount, uint256 reservePrice);
error ReserveBlackout();
error RoundTooOld(uint256 round, uint256 currentRound);
error RoundNotResolved(uint256 round);
error NotExpressLaneController(uint64 round, address controller, address sender);
