// SPDX-License-Identifier: UNLICENSED
// CHRIS: TODO: choose sol version
pragma solidity ^0.8.9;

import "./Errors.sol";
import "./Events.sol";
import "./Balance.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
// import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Bid} from "./Structs.sol";

interface IExpressLaneAuction {
    //     /// @notice An ERC-20 token deposit is made to the auction contract.
    //     /// @param bidder the address of the bidder
    //     /// @param amount    the amount in wei of the deposit
    //     event DepositSubmitted(address indexed bidder, uint256 amount);

    //     /// @notice An ERC-20 token withdrawal request is made to the auction contract.
    //     /// @param bidder the address of the bidder
    //     /// @param amount    the amount in wei requested to be withdrawn
    //     event WithdrawalInitiated(address indexed bidder, uint256 amount);

    //     /// @notice An existing withdrawal request is completed and the funds are transferred.
    //     /// @param bidder the address of the bidder
    //     /// @param amount    the amount in wei withdrawn
    //     event WithdrawalFinalized(address indexed bidder, uint256 amount);

    //     /// @notice An auction is resolved and a winner is declared as the express
    //     ///         lane controller for a round number.
    //     /// @param winningBidAmount        the amount in wei of the winning bid
    //     /// @param secondPlaceBidAmount    the amount in wei of the second-highest bid
    //     /// @param winningBidder           the address of the winner and designated express lane controller
    //     /// @param winnerRound             the round number for which the winner will be the express lane controller
    //     event AuctionResolved(
    //         uint256 winningBidAmount,
    //         uint256 secondPlaceBidAmount,
    //         address indexed winningBidder,
    //         uint256 indexed winnerRound
    //     );

    //     /// @notice Control of the upcoming round's express lane was delegated to another address.
    //     /// @param from the winner of the express lane that decided to delegate control to another.
    //     /// @param to   the new address in control of the express lane for a round.
    //     event ExpressLaneControlDelegated(
    //         address indexed from,
    //         address indexed to,
    //         uint64 round
    //     );

    //     /// @notice Fetches the reserved address for the express lane, used by the
    //     ///         express lane controller to submit their transactions to the sequencer
    //     ///         by setting the "to" field of their transactions to this address.
    //     /// @return the reserved address
    //     function expressLaneAddress() external view returns (address);

    //     /// @notice Once the auction master resolves an auction, it will deduct the second-highest
    //     ///         bid amount from the account of the highest bidder and transfer those funds
    //     ///         to either an address designated by governance, or burn them to the zero address.
    //     ///         This function will return the address to which the funds are transferred or zero
    //     ///         if funds are burnt.
    //     /// @return the address to which the funds are transferred or zero if funds are burnt.
    //     function bidReceiver() external view returns (address);

    //     /// @notice Gets the address of the current express lane controller, which has
    //     ///         won the auction for the current round. Will return the zero address
    //     ///         if there is no current express lane controller set.
    //     ///         the current round number can be determined offline by using the round duration
    //     ///         seconds and the initial round timestamp of the contract.
    //     /// @return the address of the current express lane controller
    //     function currentExpressLaneController() external view returns (address);

    //     /// @notice Gets the address of the express lane controller for the upcoming round.
    //     ///         Will return the zero address if there is no upcoming express lane controller set.
    //     /// @return the address of the express lane controller for the upcoming round.
    //     function nextExpressLaneController() external view returns (address);

    //     /// @notice Gets the duration of each round in seconds
    //     /// @return the round duration seconds
    //     function roundDurationSeconds() external view returns (uint64);

    //     /// @notice Gets the initial round timestamp for the auction contract
    //     ///         round timestamps should be a multiple of the round duration seconds
    //     ///         for convenience.
    //     /// @return the initial round timestamp
    //     function initialRoundTimestamp() external view returns (uint256);

    //     /// @notice Gets the balance of a bidder in the contract.
    //     /// @param bidder the address of the bidder.
    //     /// @return the balance of the bidder in the contract.
    //     function bidderBalance(address bidder) external view returns (uint256);

    //     /// @notice Gets the domain value required for the signature of a bid, which is a domain
    //     ///         separator constant used for signature verification.
    //     ///         bids contain a signature over an abi encoded tuple of the form
    //     ///         (uint16 domainValue, uint64 chainId, uint64 roundNumber, uint256 amount)
    //     /// @return the domain value required for bid signatures.
    //     function bidSignatureDomainValue() external view returns (uint16);

    /// @notice The ERC20 token that can be used for bidding
    /// @dev    CHRIS: TODO: specify the things we expect of this token - what restrictions it can or cannot have
    function biddingToken() external returns (IERC20);

    /// @notice Deposit an amount of ERC20 token to the auction to make bids with
    ///         Deposits must be submitted prior to bidding.
    /// @dev    Deposits are submitted first so that the auctioneer can be sure that the accepted bids can actually be paid
    /// @param amount   The amount to deposit.
    function deposit(uint256 amount) external;

    /// @notice Initiate a withdrawal of funds
    ///         Once funds have been deposited they can only be retrieved by initiating + finalizing a withdrawal
    ///         There is a delay between initializing and finalizing a withdrawal so that the auctioneer can be sure
    ///         that value cannot be removed before a bid is resolved. The timeline is as follows:
    ///         1. Initiate a withdrawal at some time in round r
    ///         2. During round r the balance is still available and can be used in an auction
    ///         3. During round r+1 the auctioneer should consider any funds that have been initiated for withdrawal as unavailable to the bidder
    ///         4. During round r+2 the bidder can finalize a withdrawal and remove their funds
    ///         A bidder may have only one withdrawal being processed at any one time.
    /// @param amount The amount to iniate a withdrawal for
    function initiateWithdrawal(uint256 amount) external;

    /// @notice Finalizes a withdrawal
    ///         Withdrawals can only be finalized 2 rounds after being initiated
    function finalizeWithdrawal() external;

    //     /// @notice Only the auction master can call this method. If there are only two distinct bids
    //     ///         present for bidding on the upcoming round, the round can be deemed canceled by setting
    //     ///         the express lane controller to the zero address.
    //     function cancelUpcomingRound() external;

    //     /// @notice Allows the upcoming round's express lane controller to delegate ownership of the express lane
    //     ///         to a delegate address. Can only be called after an auction has resolved and before the upcoming
    //     ///         round begins, and the sender must be the winner of the latest resolved auction. Will update
    //     ///         the express lane controller for the upcoming round to the specified delegate address.
    //     /// @param delegate the address to delegate the upcoming round to.
    //     function delegateExpressLane(address delegate) external;

    //     /// @notice Only the auction master can call this method, passing in the two highest bids.
    //     ///         The auction contract will verify the signatures on these bids,
    //     ///         and that both are backed by funds deposited in the auction contract.
    //     ///         Then the auction contract will deduct the second-highest bid amount
    //     ///         from the account of the highest bidder, and transfer those funds to
    //     ///         an account designated by governance, or burn them if governance
    //     ///         specifies that the proceeds are to be burned.
    //     ///         auctions are resolved by the auction master before the end of a current round
    //     ///         at some time T = AUCTION_CLOSING_SECONDS where T < ROUND_DURATION_SECONDS.
    //     /// @param bid1 the first bid
    //     /// @param bid2 the second bid
    //     function resolveAuction(Bid calldata bid1, Bid calldata bid2) external;
}

struct RoundTimingInfo {
    // CHRIS: TODO: docs in here, measured in seconds
    uint64 offsetTimestamp;
    uint64 biddingStageLength;
    uint64 resolvingStageLength;
    // CHRIS: TODO: validate this is less than the bidding stage length
    uint64 reserveBlackoutPeriodStart;
}

library RoundTimingInfoLib {
    // CHRIS: TODO: should these be storage? assess at the end
    function roundDuration(RoundTimingInfo memory info) internal pure returns (uint64) {
        return info.biddingStageLength + info.resolvingStageLength;
    }

    function currentRound(RoundTimingInfo memory info) internal view returns (uint64) {
        if (info.offsetTimestamp > block.timestamp) {
            // CHRIS: TODO: Invariant: info.offsetTimestamp > block.timestamp only during initialization and never any other time
            return 0;
        }

        // CHRIS: TODO: test that this rounds down
        return (uint64(block.timestamp) - info.offsetTimestamp) / roundDuration(info);
    }

    function currentStage(RoundTimingInfo memory info) internal view returns (RoundStage) {
        if (info.offsetTimestamp > block.timestamp) {
            return RoundStage.Bidding;
        }

        uint64 timeSinceOffset = (uint64(block.timestamp) - info.offsetTimestamp);
        uint64 timeIntoRound = timeSinceOffset % roundDuration(info);
        // CHRIS: TODO: test boundary conditions 0, biddingStageLength, biddingStageLength + resolvingStageLength
        if (timeIntoRound < info.biddingStageLength) {
            return RoundStage.Bidding;
        } else {
            return RoundStage.Resolving;
        }
    }

    function isReserveBlackoutPeriod(
        RoundTimingInfo memory info,
        uint64 latestResolvedRound,
        uint64 currentControllingRound
    ) internal view returns (bool) {
        // CHRIS: TODO: this whole func should be DRYed out
        if (info.offsetTimestamp > block.timestamp) {
            return false;
        }

        // CHRIS: TODO: we should put this check in a lib, we also have it in the resolve
        if (latestResolvedRound == currentControllingRound) {
            // round has been resolved, so we can set reserve for the next round
            return false;
        }

        //
        uint64 timeSinceOffset = (uint64(block.timestamp) - info.offsetTimestamp);
        uint64 timeIntoRound = timeSinceOffset % roundDuration(info);
        if (timeIntoRound < info.reserveBlackoutPeriodStart) {
            return false;
        } else {
            return true;
        }

        // has the current round been set? if so then no

        // starts into the round
    }

    // function roundStartTimestamp(RoundTimingInfo memory info, uint256 round) internal returns(uint256) {
    //     // CHRIS: TODO: when we include updates we need to point out that this is not
    //     //              accurate for timestamps after the update timestamp - that will be a bit tricky wont it?
    //     // CHRIS: TODO: review this whole function when we support updates

    //     // CHRIS: TODO: we will need an offsetRound when we allow for updating timing info
    //     return info.offsetTimestamp + round * roundDuration(info);
    // }
}

// CHRIS: TODO: rethink when we want to set the reduced value for in the balance
//              perhaps it should be at round + 2
//              and instead the balance() should look ahead a bit to round + 1, rather than setting those vals internally. Is the balance reducing the think that happens on the round, or the balance becoming withdrawable the thing that happens. Currently we have the former, but then we still allow spending of it, which makes no sense. To be fai

// 1. reserve update cannot be made in the down period - otherwise it can be made instantly
// 2. balance update can be made any time
//    * but it applies in the next round
//    * and is withdrawable in the round+2
//    * do this via 2 reads every time we check balance
// 3. update the round time
//    * do this via 2 reads each time
//    * check if an update is there, if so use that if it's in the past
//    * needs to contain round number as well as other things
// 4. update the election controller - specify the slot via index
// 5. update min reserve at any time, that's fine since we can see it coming, also updates normal reserve

struct ELCRound {
    address expressLaneController;
    uint64 round;
}

// CHRIS: TODO: consider all usages of the these during initialization
// CHRIS: TODO: Invariant: not possible for the rounds in latest rounds to have the same value
library LatestELCRoundsLib {
    // CHRIS: TODO: this isnt efficient to do on storage - we may need to return the index or something
    function latestELCRound(ELCRound[2] memory rounds) public pure returns (ELCRound memory, uint8) {
        ELCRound memory latestRound = rounds[0];
        uint8 index = 0;
        // CHRIS: TODO: what values do these have during init?
        if (latestRound.round < rounds[1].round) {
            latestRound = rounds[1];
            index = 1;
        }
        return (latestRound, index);
    }
}

// CHRIS: TODO: go through all the functions and look for duplicate storage access

contract ExpressLaneAuction is IExpressLaneAuction, AccessControl {
    using SafeERC20 for IERC20;
    using RoundTimingInfoLib for RoundTimingInfo;
    using BalanceLib for Balance;
    // using MessageHashUtils for bytes32;
    using ECDSA for bytes32;
    using LatestELCRoundsLib for ELCRound[2];

    event Deposit(address indexed account, uint256 amount);
    event WithdrawalInitiated(address indexed account, uint256 withdrawalAmount, uint256 roundWithdrawable);
    event WithdrawalFinalized(address indexed account, uint256 withdrawalAmount);
    // CHRIS: TODO: should I include the stage times? yes
    // uint256 roundStartTimestamp,
    // uint256 roundResolvingStartTimestamp,
    // uint256 roundEndTimestamp,
    // CHRIS: TODO: rename
    event AuctionResolved(
        uint256 round,
        address indexed firstPriceBidder,
        address indexed firstPriceElectionController,
        uint256 firstPriceAmount,
        uint256 price
    );


    bytes32 public constant AUCTIONEER_ROLE = keccak256("AUCTIONEER");
    // CHRIS: TODO: should we a general updater role
    bytes32 public constant MIN_RESERVE_SETTER_ROLE = keccak256("MIN_RESERVE_SETTER");
    bytes32 public constant RESERVE_SETTER_ROLE = keccak256("RESERVE_SETTER");

    /// @inheritdoc IExpressLaneAuction
    IERC20 public immutable biddingToken;
    mapping(address => Balance) internal _balanceOf;
    RoundTimingInfo public roundTimingInfo;

    ELCRound[2] latestResolvedRounds;

    // CHRIS: TODO: function to update this
    address public immutable beneficiary;

    uint256 public minReservePrice;
    uint256 public reservePrice;

    // CHRIS: TODO: tests for the constructor/*  */
    constructor(
        address _beneficiary,
        RoundTimingInfo memory _roundTimingInfo,
        address _biddingToken,
        address _auctioneer,
        address _roleAdmin,
        uint256 _minReservePrice,
        address _minReservePriceSetter,
        address _reservePriceSetter
    ) {
        // CHRIS: TODO: initialisation is a bit strange since we have a round in the future, but we cant do any bidding
        //              we need to test all the functions to see if they work before round 0 begins

        // CHRIS: TODO: validation on all of these

        beneficiary = _beneficiary;
        // CHRIS: TODO: validation on the round timing
        roundTimingInfo = _roundTimingInfo;
        biddingToken = IERC20(_biddingToken);
        minReservePrice = _minReservePrice;
        reservePrice = _minReservePrice;

        _grantRole(DEFAULT_ADMIN_ROLE, _roleAdmin);
        _grantRole(AUCTIONEER_ROLE, _auctioneer);
        _grantRole(MIN_RESERVE_SETTER_ROLE, _minReservePriceSetter);
        _grantRole(RESERVE_SETTER_ROLE, _reservePriceSetter);
    }

    // CHRIS: TODO: docs and tests on these
    function currentRound() public view returns (uint64) {
        return roundTimingInfo.currentRound();
    }

    function roundDuration() public view returns (uint64) {
        return roundTimingInfo.roundDuration();
    }

    // CHRIS: TODO: improve namings here
    function biddingStageLength() public view returns (uint64) {
        return roundTimingInfo.biddingStageLength;
    }

    function resolvingStageLength() public view returns (uint64) {
        return roundTimingInfo.resolvingStageLength;
    }

    function currentStage() public view returns (RoundStage) {
        return roundTimingInfo.currentStage();
    }

    function setMinReservePrice(uint256 newMinReservePrice) public onlyRole(MIN_RESERVE_SETTER_ROLE) {
        // CHRIS: TODO: tests up in here
        minReservePrice = newMinReservePrice;

        // CHRIS: TODO: set the reserve price if the min is higher
        if (newMinReservePrice > reservePrice) {
            _setReservePrice(newMinReservePrice);
        }

        // CHRIS: TODO: events up in here and reserve price
    }

    function setReservePrice(uint256 newReservePrice) public onlyRole(RESERVE_SETTER_ROLE) {
        (ELCRound memory lastRoundResolved,) = latestResolvedRounds.latestELCRound();
        if (roundTimingInfo.isReserveBlackoutPeriod(lastRoundResolved.round, currentRound() + 1)) {
            revert ReserveBlackoutPeriod();
        }

        _setReservePrice(newReservePrice);
    }

    function _setReservePrice(uint256 newReservePrice) public {
        if (newReservePrice < minReservePrice) {
            revert ReservePriceTooLow(newReservePrice, minReservePrice);
        }

        reservePrice = newReservePrice;
    }

    // CHRIS: TODO: invariant: balance after <= balance before
    // CHRIS: TODO: invariant: if balance after == 0 and balance before == 0, then round must be set to max

    // CHRIS: TODO: tests for balanceOf, freeBalance and withdrawable balance

    function balanceOf(address account) public view returns (uint256) {
        return _balanceOf[account].balanceAtRound(currentRound());
    }

    // CHRIS: TODO: test each of these functions for an uninitialized deposit, and for one that has been zerod out

    /// @notice The amount of balance that can currently be withdrawn via the finalize method
    ///         This balance only increases 2 rounds after a withdrawal is initiated
    /// @param account The account the check the withdrawable balance for
    function withdrawableBalance(address account) public view returns (uint256) {
        // CHRIS: TODO: consider whether the whole balance of mapping and the round number should be in a lib together
        return _balanceOf[account].withdrawableBalanceAtRound(currentRound());
    }

    /// @inheritdoc IExpressLaneAuction
    function deposit(uint256 amount) external {
        _balanceOf[msg.sender].increase(amount);
        biddingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Deposit(msg.sender, amount);
    }

    /// @inheritdoc IExpressLaneAuction
    function initiateWithdrawal(uint256 amount) external {
        uint64 curRnd = currentRound();
        _balanceOf[msg.sender].initiateReduce(amount, curRnd);
        // CHRIS: TODO: do we want to also have the balance before, the one beind decremented
        // CHRIS: TODO: doing this is too expensive: bal.balanceBeforeRound - bal.balanceAfterRound
        emit WithdrawalInitiated(msg.sender, amount, curRnd + 2);
    }

    /// @inheritdoc IExpressLaneAuction
    function finalizeWithdrawal() external {
        uint256 amountReduced = _balanceOf[msg.sender].finalizeReduce(currentRound());
        biddingToken.safeTransfer(msg.sender, amountReduced);
        // CHRIS: TODO: consider adding the following assertion - it's an invariant
        // CHRIS: TODO: Invariant: assert(withdrawableBalance(msg.sender) == 0);
        emit WithdrawalFinalized(msg.sender, amountReduced);
    }

    function getBidHash(uint64 _round, uint256 _amount, address _expressLaneController) public view returns (bytes32) {
        return keccak256(abi.encodePacked(block.chainid, address(this), _round, _amount, _expressLaneController));
    }

    function resolveAuction(Bid calldata firstPriceBid, uint256 price) internal returns (address, uint64) {
        if (roundTimingInfo.currentStage() != RoundStage.Resolving) {
            revert InvalidStage(roundTimingInfo.currentStage(), RoundStage.Resolving);
        }

        // CHRIS: TODO: what if the bids are for the same value? what do we do here?
        if (price > firstPriceBid.amount) {
            revert BidsWrongOrder();
        }

        // we know from above that first price bid is >= second price bid
        // so if second price is greater than reserve, then so is the first
        // CHRIS: TODO: not necessary in the single bid case - move to the multibid func
        if (price < reservePrice) {
            // CHRIS: TODO: test
            revert ReservePriceNotMet(price, reservePrice);
        }

        // bidding is for the next round, has a bid already been settled for that round
        uint64 biddingRound = currentRound();
        uint64 controllingRound = biddingRound + 1;
        // CHRIS: TODO: do we have a problem in only test for ==, should we also test for >?
        //              Invariant: lastAuctionRound should never be > controllingRound except during initialization
        (ELCRound memory lastRoundResolved, uint8 index) = latestResolvedRounds.latestELCRound();
        if (lastRoundResolved.round == controllingRound) {
            revert RoundAlreadyResolved(controllingRound);
        }

        address firstPriceBidder = getBidHash(
            controllingRound, firstPriceBid.amount, firstPriceBid.expressLaneController
        ).toEthSignedMessageHash().recover(firstPriceBid.signature);
        // CHRIS: TODO: we dont care about the current round, we care about the next one? no, we care about now!
        if (balanceOf(firstPriceBidder) < firstPriceBid.amount) {
            // CHRIS: TODO: here we should put the account into the error message
            revert InsufficientBalance(firstPriceBid.amount, balanceOf(firstPriceBidder));
        }

        // CHRIS: TODO: this is actually doing an unnecessary balance check, given the check we have above
        _balanceOf[firstPriceBidder].reduce(price, biddingRound);
        // dont replace the latest round
        uint8 oldestRoundIndex = index ^ 1;
        latestResolvedRounds[oldestRoundIndex] = ELCRound(firstPriceBid.expressLaneController, controllingRound);

        // now transfer funds to the bid receiver
        biddingToken.transfer(beneficiary, price);

        emit AuctionResolved(
            controllingRound, firstPriceBidder, firstPriceBid.expressLaneController, firstPriceBid.amount, price
        );

        return (firstPriceBidder, controllingRound);
    }

    // CHRIS: TODO: to be called only when the second price bid is used
    function resolveSingleBidAuction(Bid calldata firstPriceBid) external onlyRole(AUCTIONEER_ROLE) {
        if (firstPriceBid.amount < reservePrice) {
            revert ReservePriceNotMet(firstPriceBid.amount, reservePrice);
        }

        resolveAuction(firstPriceBid, reservePrice);

        // CHRIS: TODO: additional event? here and in the multibid?
    }

    // CHRIS: TODO: we need to settle on a definition of round. Is the round r the one we are bidding in, or the one we are bidding for
    function resolveMultiBidAuction(Bid calldata firstPriceBid, Bid calldata secondPriceBid)
        external
        onlyRole(AUCTIONEER_ROLE)
    {
        (address firstPriceBidder, uint64 controllingRound) = resolveAuction(firstPriceBid, secondPriceBid.amount);

        address secondPriceBidder = getBidHash(
            controllingRound, secondPriceBid.amount, secondPriceBid.expressLaneController
        ).toEthSignedMessageHash().recover(secondPriceBid.signature);
        // CHRIS: TODO: we dont care about the current round, we care about the next one!
        if (balanceOf(secondPriceBidder) < secondPriceBid.amount) {
            revert InsufficientBalance(secondPriceBid.amount, balanceOf(secondPriceBidder));
        }

        // CHRIS: TODO: not necessary really? yes it is, since that would constitute re-use of funds
        //              include comments on why we need this
        if (firstPriceBidder == secondPriceBidder) {
            revert SameBidder();
        }
    }

    function transferExpressLaneController(uint64 round, address newExpressLaneController) external {
        // round must be now or in the future: CHRIS: TODO: why? because the old rounds have already actually passed
        if (round < currentRound()) {
            revert RoundTooOld();
        }

        // CHRIS: TODO: this stuff could be a function on the elcs[2] struct lib
        if (latestResolvedRounds[0].round == round) {
            // check if the express lane controller is msg.sender
            if (latestResolvedRounds[0].expressLaneController != msg.sender) {
                // CHRIS: TODO: revert not express lane controller
            }
            latestResolvedRounds[0].expressLaneController = newExpressLaneController;
        } else if (latestResolvedRounds[1].round == round) {
            if (latestResolvedRounds[1].expressLaneController != msg.sender) {
                // CHRIS: TODO: revert not express lane controller
            }
            latestResolvedRounds[1].expressLaneController = newExpressLaneController;
        } else {
            // CHRIS: TODO: revert round not set
        }

        // CHRIS: TODO: emit an event for the new express lane controller
        // we could also just have events here
    }

    // DEPRECATED: will be replaced by a more ergonomic interface
    function expressLaneControllerRounds() public view returns (ELCRound memory, ELCRound memory) {
        return (latestResolvedRounds[0], latestResolvedRounds[1]);
    }
}
