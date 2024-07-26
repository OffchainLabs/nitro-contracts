// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Errors.sol";
import {Balance, BalanceLib} from "./Balance.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {
    AccessControlEnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import {DelegateCallAware} from "../libraries/DelegateCallAware.sol";
import {IExpressLaneAuction, Bid} from "./IExpressLaneAuction.sol";
import {ELCRound, LatestELCRoundsLib} from "./ELCRound.sol";
import {RoundTimingInfo, RoundTimingInfoLib} from "./RoundTimingInfo.sol";

// CHRIS: TODO: switch signing to 712
// CHRIS: TODO: dont sent to beneficiary every time. Provide another function that anyone can call to flush the beneficiary balance.

// CHRIS: TODO: look through all the comments and see if we want to add any of them to the spec as clarification

// CHRIS: TODO: do we wamt to include the ability to update the round time?
// 3. update the round time
//    * do this via 2 reads each time
//    * check if an update is there, if so use that if it's in the past
//    * needs to contain round number as well as other things
// CHRIS: TODO:
// also look at every function that uses the offset? yes
// also everything that is set during the resolve - and find all usages of those
// wrap all those functions in good getters that have predicatable and easy to reason about return values
// consider what would happen if the offset is set to the future after some rounds have been resolved. Should be easy to reason about if we've done our job correctly
// ok, so we will allow an update in the following way
// 1. direct update of the round timing info
// 2. when doing this ensure that the current round number stays the same
// 3. will update the timings of this round and the next
//    which could have negative consequences - but these need to be pointed out in docs
//    I think this is better than the complexity of scheduling a future update
// CHRIS: TODO: when we include updates we need to point out that roundTimestamps() are not
//              accurate for timestamps after the update timestamp - that will be a bit tricky wont it?
//              all round timing stuff needs reviewing if we include updates
// CHRIS: TODO: update the roundTimestamps on interface for what happens if the roundtiminginfo is updated
//              also consider other places effected by round timing - hopefully only in that lib
// CHRIS: TODO: if we update round timing we need to add the address to the trusted list in the resolve documentation of the interface

// CHRIS: TODO: go through all the functions and look for duplicate storage access

// CHRIS: TODO: switch to a more modern version of openzeppelin so that we can use disableInitializers in the constructor.
// CHRIS: TODO: list of problems due to having a future offset:
//              1. cant withdraw balance until rounds begin
//              2. test other functions to see how they behave before offset has been reached, is it correct to revert or do nothing or what?

// CHRIS: TODO: review what would happen if reserve submission seconds == auction closing seconds
// CHRIS: TODO: test boundary conditions in round timing info lib: roundDuration, auctionClosingStage, reserveSubmission, offset

// CHRIS: TODO:
// do the following to e2e test whether everything works before the offset
// 1. before the offset
//    * do deposit
//    * initiate withdrawal
//    * fail finalize withdrawal ofc
//    * set reserve
//    * fail resolve
//    * check all of the getters return the expected amounts
// 2. during round 0
//    * same as above, except resolve is allowed during the correct period
//    * and setting reserve fails during correct period
//    * check all of the getters
// 3. during round 1
//    * same as above
// 4. during round 2
//    * same as above, but can finalize the withdrawal

// CHRIS: TODO: list all the things that are not set in the following cases:
//              1. before we start
//              2. during a gap of latest resolved rounds
//              3. normal before resolve of current round and after

// CHRIS: TODO: line up natspec comments

// CHRIS: TODO: round timing info tests

// CHRIS: TODO: ensure each public function is tested separately - some are tested as part of other tests

// CHRIS: TODO: the elc can be delayed in sending transaction by a resolve at the very last moment - should only be a very small delay

// CHRIS: TODO: if an address sends a transaction via slow path and then via fast, what happens (rejection or promotion)? what if the nonce increases? wait
//              what does that do to the order of transactions? we cannot guarantee the sequence number is the order transactions are mined in
//              add notes on this behaviour to the spec

// CHRIS: TODO: specify the things we expect of the bidding token - what restrictions it can or cannot have

// CHRIS: TODO: add ability to set the transferrer of controller rights

// CHRIS: TODO: in isReserveBlackout we should never have `latestResolvedRound > curRound + 1`. latest should never be greater than when called from the express lane auction

// CHRIS: TODO: check that auction.roundTimestamps is used in tests
// CHRIS: TODO: check that auction.isReserveBlackout is used in tests

/// @title  ExpressLaneAuction
/// @notice The express lane allows a controller to submit undelayed transactions to the sequencer
///         The right to be the express lane controller are auctioned off in rounds, by an offchain auctioneer.
///         The auctioneer then submits the winning bids to this control to deduct funds from the bidders and register the winner
contract ExpressLaneAuction is
    IExpressLaneAuction,
    AccessControlEnumerableUpgradeable,
    DelegateCallAware
{
    using SafeERC20 for IERC20;
    using RoundTimingInfoLib for RoundTimingInfo;
    using BalanceLib for Balance;
    using ECDSA for bytes32;
    using ECDSA for bytes;
    using LatestELCRoundsLib for ELCRound[2];

    /// @inheritdoc IExpressLaneAuction
    bytes32 public constant AUCTIONEER_ROLE = keccak256("AUCTIONEER");
    /// @inheritdoc IExpressLaneAuction
    bytes32 public constant MIN_RESERVE_SETTER_ROLE = keccak256("MIN_RESERVE_SETTER");
    /// @inheritdoc IExpressLaneAuction
    bytes32 public constant RESERVE_SETTER_ROLE = keccak256("RESERVE_SETTER");
    /// @inheritdoc IExpressLaneAuction
    bytes32 public constant BENEFICIARY_SETTER_ROLE = keccak256("BENEFICIARY_SETTER");
    /// @inheritdoc IExpressLaneAuction
    bytes32 public constant BID_DOMAIN = keccak256("TIMEBOOST_BID");

    /// @notice The balances of each address
    mapping(address => Balance) internal _balanceOf;

    /// @dev    Recently resolved round information. Contains the two most recently resolved rounds
    ELCRound[2] internal latestResolvedRounds;

    /// @inheritdoc IExpressLaneAuction
    address public beneficiary;

    /// @inheritdoc IExpressLaneAuction
    IERC20 public biddingToken;

    /// @inheritdoc IExpressLaneAuction
    uint256 public reservePrice;

    /// @inheritdoc IExpressLaneAuction
    uint256 public minReservePrice;

    /// @inheritdoc IExpressLaneAuction
    RoundTimingInfo public roundTimingInfo;

    /// @inheritdoc IExpressLaneAuction
    function initialize(
        address _auctioneer,
        address _beneficiary,
        address _biddingToken,
        RoundTimingInfo memory _roundTimingInfo,
        uint256 _minReservePrice,
        address _roleAdmin,
        address _minReservePriceSetter,
        address _reservePriceSetter,
        address _beneficiarySetter
    ) public initializer onlyDelegated {
        if (address(_biddingToken) == address(0)) {
            revert ZeroBiddingToken();
        }
        biddingToken = IERC20(_biddingToken);

        beneficiary = _beneficiary;
        emit SetBeneficiary(address(0), _beneficiary);

        minReservePrice = _minReservePrice;
        emit SetMinReservePrice(uint256(0), _minReservePrice);

        reservePrice = _minReservePrice;
        emit SetReservePrice(uint256(0), _minReservePrice);

        if (
            _roundTimingInfo.reserveSubmissionSeconds + _roundTimingInfo.auctionClosingSeconds >
            _roundTimingInfo.roundDurationSeconds
        ) {
            revert RoundDurationTooShort();
        }

        roundTimingInfo = _roundTimingInfo;

        _grantRole(DEFAULT_ADMIN_ROLE, _roleAdmin);
        _grantRole(AUCTIONEER_ROLE, _auctioneer);
        _grantRole(MIN_RESERVE_SETTER_ROLE, _minReservePriceSetter);
        _grantRole(RESERVE_SETTER_ROLE, _reservePriceSetter);
        _grantRole(BENEFICIARY_SETTER_ROLE, _beneficiarySetter);
    }

    /// @inheritdoc IExpressLaneAuction
    function currentRound() public view returns (uint64) {
        return roundTimingInfo.currentRound();
    }

    /// @inheritdoc IExpressLaneAuction
    function isAuctionRoundClosed() public view returns (bool) {
        return roundTimingInfo.isAuctionRoundClosed();
    }

    /// @inheritdoc IExpressLaneAuction
    function isReserveBlackout() public view returns (bool) {
        (ELCRound memory lastRoundResolved, ) = latestResolvedRounds.latestELCRound();
        return roundTimingInfo.isReserveBlackout(lastRoundResolved.round);
    }

    /// @inheritdoc IExpressLaneAuction
    function roundTimestamps(uint64 round) public view returns (uint64, uint64) {
        return roundTimingInfo.roundTimestamps(round);
    }

    /// @inheritdoc IExpressLaneAuction
    function setBeneficiary(address newBeneficiary) external onlyRole(BENEFICIARY_SETTER_ROLE) {
        emit SetBeneficiary(beneficiary, newBeneficiary);
        beneficiary = newBeneficiary;
    }

    function _setReservePrice(uint256 newReservePrice) private {
        if (newReservePrice < minReservePrice) {
            revert ReservePriceTooLow(newReservePrice, minReservePrice);
        }

        emit SetReservePrice(reservePrice, newReservePrice);
        reservePrice = newReservePrice;
    }

    /// @inheritdoc IExpressLaneAuction
    function setMinReservePrice(uint256 newMinReservePrice)
        external
        onlyRole(MIN_RESERVE_SETTER_ROLE)
    {
        emit SetMinReservePrice(minReservePrice, newMinReservePrice);

        minReservePrice = newMinReservePrice;

        if (newMinReservePrice > reservePrice) {
            _setReservePrice(newMinReservePrice);
        }
    }

    /// @inheritdoc IExpressLaneAuction
    function setReservePrice(uint256 newReservePrice) external onlyRole(RESERVE_SETTER_ROLE) {
        if (isReserveBlackout()) {
            revert ReserveBlackout();
        }

        _setReservePrice(newReservePrice);
    }

    /// @inheritdoc IExpressLaneAuction
    function balanceOf(address account) public view returns (uint256) {
        return _balanceOf[account].balanceAtRound(currentRound());
    }

    /// @inheritdoc IExpressLaneAuction
    function withdrawableBalance(address account) external view returns (uint256) {
        return _balanceOf[account].withdrawableBalanceAtRound(currentRound());
    }

    /// @inheritdoc IExpressLaneAuction
    function deposit(uint256 amount) external {
        _balanceOf[msg.sender].increase(amount);
        biddingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Deposit(msg.sender, amount);
    }

    /// @inheritdoc IExpressLaneAuction
    function initiateWithdrawal() external {
        // The withdrawal can be finalized 2 rounds for now. We dont make it round + 1 in 
        // case the initiation were to occur right at the end of a round. Doing round + 2 ensures
        // observers always have at least one full round to become aware of the future balance change.
        uint64 withdrawalRound = currentRound() + 2;
        uint256 amount = _balanceOf[msg.sender].balance;
        _balanceOf[msg.sender].initiateWithdrawal(withdrawalRound);
        emit WithdrawalInitiated(msg.sender, amount, withdrawalRound);
    }

    /// @inheritdoc IExpressLaneAuction
    function finalizeWithdrawal() external {
        uint256 amountReduced = _balanceOf[msg.sender].finalizeWithdrawal(currentRound());
        biddingToken.safeTransfer(msg.sender, amountReduced);
        // CHRIS: TODO: consider adding the following assertion - it's an invariant
        // CHRIS: TODO: Invariant: assert(withdrawableBalance(msg.sender) == 0);
        emit WithdrawalFinalized(msg.sender, amountReduced);
    }

    /// @dev Update local state to resolve an auction
    /// @param isMultiBid Where the auction should be resolved from multiple bids
    /// @param firstPriceBid The winning bid
    /// @param firstPriceBidder The winning bidder
    /// @param priceToPay The price that needs to be paid by the winner
    /// @param biddingInRound The round bidding is taking place in. This is not the round the bidding is taking place for, which is biddingInRound + 1
    function resolveAuction(
        bool isMultiBid,
        Bid calldata firstPriceBid,
        address firstPriceBidder,
        uint256 priceToPay,
        uint64 biddingInRound
    ) internal {
        // store that a round has been resolved
        uint64 biddingForRound = biddingInRound + 1;
        latestResolvedRounds.setResolvedRound(biddingForRound, firstPriceBid.expressLaneController);

        // first price bidder pays the beneficiary
        _balanceOf[firstPriceBidder].reduce(priceToPay, biddingInRound);
        biddingToken.safeTransfer(beneficiary, priceToPay);

        // emit events so that the offchain sequencer knows a new express lane controller has been selected
        (uint64 roundStart, uint64 roundEnd) = roundTimestamps(biddingForRound);
        emit SetExpressLaneController(
            biddingForRound,
            address(0),
            firstPriceBid.expressLaneController,
            roundStart,
            roundEnd
        );
        emit AuctionResolved(
            isMultiBid,
            biddingForRound,
            firstPriceBidder,
            firstPriceBid.expressLaneController,
            firstPriceBid.amount,
            priceToPay,
            roundStart,
            roundEnd
        );
    }

    /// @inheritdoc IExpressLaneAuction
    function getBidBytes(
        uint64 _round,
        uint256 _amount,
        address _expressLaneController
    ) public view returns (bytes memory) {
        // CHRIS: TODO: test the length of this is 144
        return
            abi.encodePacked(
                BID_DOMAIN,
                block.chainid,
                address(this),
                _round,
                _amount,
                _expressLaneController
            );
    }

    /// @notice Recover the signing address of the provided bid, and check that that address has enough funds to fulfil that bid
    ///         Returns the signing address
    /// @param bid The bid to recover the signing address of
    /// @param biddingForRound The round the bid is for the control of
    function recoverAndCheckBalance(Bid memory bid, uint64 biddingForRound)
        internal
        view
        returns (address, bytes memory)
    {
        bytes memory bidBytes = getBidBytes(biddingForRound, bid.amount, bid.expressLaneController);
        address bidder = bidBytes.toEthSignedMessageHash().recover(bid.signature);
        // always check that the bidder has a much as they're claiming
        if (balanceOf(bidder) < bid.amount) {
            revert InsufficientBalanceAcc(bidder, bid.amount, balanceOf(bidder));
        }

        return (bidder, bidBytes);
    }

    /// @inheritdoc IExpressLaneAuction
    function resolveSingleBidAuction(Bid calldata firstPriceBid)
        external
        onlyRole(AUCTIONEER_ROLE)
    {
        if (!isAuctionRoundClosed()) {
            revert AuctionNotClosed();
        }

        if (firstPriceBid.amount < reservePrice) {
            revert ReservePriceNotMet(firstPriceBid.amount, reservePrice);
        }

        uint64 biddingInRound = currentRound();
        uint64 biddingForRound = biddingInRound + 1;
        (address firstPriceBidder, ) = recoverAndCheckBalance(firstPriceBid, biddingForRound);

        resolveAuction(false, firstPriceBid, firstPriceBidder, reservePrice, biddingInRound);
    }

    /// @inheritdoc IExpressLaneAuction
    function resolveMultiBidAuction(Bid calldata firstPriceBid, Bid calldata secondPriceBid)
        external
        onlyRole(AUCTIONEER_ROLE)
    {
        if (!isAuctionRoundClosed()) {
            revert AuctionNotClosed();
        }

        // if the bids are the same amount and offchain mechanism will be used to choose the order and
        // therefore the winner. The auctioneer is trusted to make this choice correctly
        if (firstPriceBid.amount < secondPriceBid.amount) {
            revert BidsWrongOrder();
        }

        // second amount must be greater than or equal the reserve
        if (secondPriceBid.amount < reservePrice) {
            revert ReservePriceNotMet(secondPriceBid.amount, reservePrice);
        }

        uint64 biddingInRound = currentRound();
        uint64 biddingForRound = biddingInRound + 1;
        // check the signatures and balances of both bids
        // even the second price bid must have the balance it's claiming
        (address firstPriceBidder, bytes memory firstBidBytes) = recoverAndCheckBalance(
            firstPriceBid,
            biddingForRound
        );
        // CHRIS: TODO: maybe we dont want to return this value
        (address secondPriceBidder, bytes memory secondBidBytes) = recoverAndCheckBalance(
            secondPriceBid,
            biddingForRound
        );

        // The bidders must be different so that our balance check isnt fooled into thinking
        // that the same balance is valid for both the first and second bid
        if (firstPriceBidder == secondPriceBidder) {
            revert SameBidder();
        }

        // when bids have the same amount we break ties based on the bid hash
        // although we include equality in the check we know this isnt possible due
        // to the check above that ensures the first price bidder and second price bidder are different
        if (
            firstPriceBid.amount == secondPriceBid.amount &&
            uint256(keccak256(abi.encodePacked(firstPriceBidder, firstBidBytes))) <=
            uint256(keccak256(abi.encodePacked(secondPriceBidder, secondBidBytes)))
        ) {
            revert TieBidsWrongOrder();
        }

        resolveAuction(
            true,
            firstPriceBid,
            firstPriceBidder,
            secondPriceBid.amount,
            biddingInRound
        );
    }

    /// @inheritdoc IExpressLaneAuction
    function transferExpressLaneController(uint64 round, address newExpressLaneController)
        external
    {
        // past rounds cannot be transferred
        uint64 curRnd = currentRound();
        if (round < curRnd) {
            revert RoundTooOld(round, curRnd);
        }

        // only resolved rounds can be transferred
        ELCRound storage resolvedRound = latestResolvedRounds.resolvedRound(round);

        address resolvedELC = resolvedRound.expressLaneController;
        if (resolvedELC != msg.sender) {
            revert NotExpressLaneController(round, resolvedELC, msg.sender);
        }

        resolvedRound.expressLaneController = newExpressLaneController;

        (uint64 start, uint64 end) = roundTimestamps(round);
        emit SetExpressLaneController(
            round,
            resolvedELC,
            newExpressLaneController,
            start < uint64(block.timestamp) ? uint64(block.timestamp) : start,
            end
        );
    }

    // CHRIS: TODO: docs and tests
    function resolvedRounds() public returns (ELCRound memory, ELCRound memory) {
        return
            latestResolvedRounds[0].round > latestResolvedRounds[1].round
                ? (latestResolvedRounds[0], latestResolvedRounds[1])
                : (latestResolvedRounds[1], latestResolvedRounds[0]);
    }
}
