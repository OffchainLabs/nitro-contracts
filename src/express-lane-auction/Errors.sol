// CHRIS: TODO: update license
// SPDX-License-Identifier: UNLICENSED
// CHRIS: TODO: choose sol version
pragma solidity ^0.8.9;

import {RoundStage} from "./Structs.sol";

// CHRIS: TODO: docs and see if al these are actually used
error InsufficientBalance(uint256 amountRequested, uint256 balance);
error NothingToWithdraw();
error ZeroAmount();
error WithdrawalInProgress(uint256 amountInWithdrawal);
error RoundAlreadyResolved(uint64 round);
error SameBidder();
error BidsWrongOrder();
// CHRIS: TODO: should be the RoundStage enums
error InvalidStage(RoundStage currentStage, RoundStage requiredStage);
error ReservePriceTooLow(uint256 reservePrice, uint256 minReservePrice);
error ReservePriceNotMet(uint256 bidAmount, uint256 reservePrice);
error ReserveBlackoutPeriod();
error RoundTooOld();
