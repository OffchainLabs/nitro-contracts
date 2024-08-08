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
import {IExpressLaneAuction, Bid, InitArgs} from "./IExpressLaneAuction.sol";
import {ELCRound, LatestELCRoundsLib} from "./ELCRound.sol";
import {RoundTimingInfo, RoundTimingInfoLib} from "./RoundTimingInfo.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/draft-EIP712Upgradeable.sol";

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
// CHRIS: TODO: test initiate/finalize withdrawal with round time updates
// * guarantees are not effected by round time updates
// * cant set an offset in the future - should be in the past
// * reducing the round time does have an effect on finalize - add this later
// * check finalization times with round time update

// CHRIS: TODO: add ability to set the transferrer of controller rights

/// @title ExpressLaneAuction
/// @notice The express lane allows a controller to submit undelayed transactions to the sequencer
///         The right to be the express lane controller are auctioned off in rounds, by an offchain auctioneer.
///         The auctioneer then submits the winning bids to this control to deduct funds from the bidders and register the winner
contract ExpressLaneAuction is
    IExpressLaneAuction,
    AccessControlEnumerableUpgradeable,
    DelegateCallAware,
    EIP712Upgradeable
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
    bytes32 public constant AUCTIONEER_ADMIN_ROLE = keccak256("AUCTIONEER_ADMIN");
    /// @inheritdoc IExpressLaneAuction
    bytes32 public constant MIN_RESERVE_SETTER_ROLE = keccak256("MIN_RESERVE_SETTER");
    /// @inheritdoc IExpressLaneAuction
    bytes32 public constant RESERVE_SETTER_ROLE = keccak256("RESERVE_SETTER");
    /// @inheritdoc IExpressLaneAuction
    bytes32 public constant RESERVE_SETTER_ADMIN_ROLE = keccak256("RESERVE_SETTER_ADMIN");
    /// @inheritdoc IExpressLaneAuction
    bytes32 public constant BENEFICIARY_SETTER_ROLE = keccak256("BENEFICIARY_SETTER");
    /// @inheritdoc IExpressLaneAuction
    bytes32 public constant BID_DOMAIN = keccak256("TIMEBOOST_BID");

    /// @notice The balances of each address
    mapping(address => Balance) internal _balanceOf;

    /// @dev Recently resolved round information. Contains the two most recently resolved rounds
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
    uint256 public beneficiaryBalance;

    /// @inheritdoc IExpressLaneAuction
    function initialize(InitArgs memory args) public initializer onlyDelegated {
        __AccessControl_init();
        __EIP712_init("ExpressLaneAuction", "1");

        if (address(args._biddingToken) == address(0)) {
            revert ZeroBiddingToken();
        }
        biddingToken = IERC20(args._biddingToken);

        beneficiary = args._beneficiary;
        emit SetBeneficiary(address(0), args._beneficiary);

        minReservePrice = args._minReservePrice;
        emit SetMinReservePrice(0, args._minReservePrice);

        reservePrice = args._minReservePrice;
        emit SetReservePrice(0, args._minReservePrice);

        if (
            args._roundTimingInfo.reserveSubmissionSeconds +
                args._roundTimingInfo.auctionClosingSeconds >
            args._roundTimingInfo.roundDurationSeconds
        ) {
            revert RoundDurationTooShort();
        }

        roundTimingInfo = args._roundTimingInfo;

        // roles without a custom role admin set will have this as the admin
        _grantRole(DEFAULT_ADMIN_ROLE, args._masterAdmin);
        _grantRole(MIN_RESERVE_SETTER_ROLE, args._minReservePriceSetter);
        _grantRole(BENEFICIARY_SETTER_ROLE, args._beneficiarySetter);

        // the following roles are expected to be controlled by hot wallets, so we add
        // additional custom admin role for each of them to allow for key rotation management
        setRoleAndAdmin(
            AUCTIONEER_ROLE,
            args._auctioneer,
            AUCTIONEER_ADMIN_ROLE,
            args._auctioneerAdmin
        );
        setRoleAndAdmin(
            RESERVE_SETTER_ROLE,
            args._reservePriceSetter,
            RESERVE_SETTER_ADMIN_ROLE,
            args._reservePriceSetterAdmin
        );
    }

    /// @notice Set an address for a role, an admin role for the role, and an address for the admin role
    function setRoleAndAdmin(
        bytes32 role,
        address roleAddr,
        bytes32 adminRole,
        address adminRoleAddr
    ) internal {
        _grantRole(role, roleAddr);
        _grantRole(adminRole, adminRoleAddr);
        _setRoleAdmin(role, adminRole);
    }

    /// @inheritdoc IExpressLaneAuction
    function currentRound() external view returns (uint64) {
        return roundTimingInfo.currentRound();
    }

    /// @inheritdoc IExpressLaneAuction
    function isAuctionRoundClosed() external view returns (bool) {
        return roundTimingInfo.isAuctionRoundClosed();
    }

    /// @inheritdoc IExpressLaneAuction
    function isReserveBlackout() external view returns (bool) {
        (ELCRound storage lastRoundResolved, ) = latestResolvedRounds.latestELCRound();
        return roundTimingInfo.isReserveBlackout(lastRoundResolved.round);
    }

    /// @inheritdoc IExpressLaneAuction
    function roundTimestamps(uint64 round) external view returns (uint64, uint64) {
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
        (ELCRound storage lastRoundResolved, ) = latestResolvedRounds.latestELCRound();
        if (roundTimingInfo.isReserveBlackout(lastRoundResolved.round)) {
            revert ReserveBlackout();
        }

        _setReservePrice(newReservePrice);
    }

    /// @inheritdoc IExpressLaneAuction
    function balanceOf(address account) external view returns (uint256) {
        return _balanceOf[account].balanceAtRound(roundTimingInfo.currentRound());
    }

    /// @inheritdoc IExpressLaneAuction
    function withdrawableBalance(address account) external view returns (uint256) {
        return _balanceOf[account].withdrawableBalanceAtRound(roundTimingInfo.currentRound());
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
        uint64 withdrawalRound = roundTimingInfo.currentRound() + 2;
        uint256 amount = _balanceOf[msg.sender].balance;
        _balanceOf[msg.sender].initiateWithdrawal(withdrawalRound);
        emit WithdrawalInitiated(msg.sender, amount, withdrawalRound);
    }

    /// @inheritdoc IExpressLaneAuction
    function finalizeWithdrawal() external {
        uint256 amountReduced = _balanceOf[msg.sender].finalizeWithdrawal(
            roundTimingInfo.currentRound()
        );
        biddingToken.safeTransfer(msg.sender, amountReduced);
        emit WithdrawalFinalized(msg.sender, amountReduced);
    }

    /// @inheritdoc IExpressLaneAuction
    function flushBeneficiaryBalance() external {
        uint256 bal = beneficiaryBalance;
        if (bal == 0) {
            revert ZeroAmount();
        }
        beneficiaryBalance = 0;
        biddingToken.safeTransfer(beneficiary, bal);
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
        uint64 biddingInRound,
        RoundTimingInfo memory info
    ) internal {
        // store that a round has been resolved
        uint64 biddingForRound = biddingInRound + 1;
        latestResolvedRounds.setResolvedRound(biddingForRound, firstPriceBid.expressLaneController);

        // first price bidder pays the beneficiary
        _balanceOf[firstPriceBidder].reduce(priceToPay, biddingInRound);
        beneficiaryBalance += priceToPay;

        // emit events so that the offchain sequencer knows a new express lane controller has been selected
        (uint64 roundStart, uint64 roundEnd) = info.roundTimestamps(biddingForRound);
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
    function domainSeparator() external view returns(bytes32) {
        return _domainSeparatorV4();
    }

    /// @inheritdoc IExpressLaneAuction
    function getBidHash(uint64 round, address expressLaneController, uint256 amount) public view returns(bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(
            keccak256("Bid(uint64 round,address expressLaneController,uint256 amount)"),
            round,
            expressLaneController,
            amount
        )));
    }

    /// @notice Recover the signing address of the provided bid, and check that that address has enough funds to fulfil that bid
    ///         Returns the signing address and the bid hash that was signed
    /// @param bid The bid to recover the signing address of
    /// @param biddingForRound The round the bid is for the control of
    function recoverAndCheckBalance(
        Bid memory bid,
        uint64 biddingForRound,
        RoundTimingInfo memory info
    ) internal view returns (address, bytes32) {
        bytes32 bidHash = getBidHash(biddingForRound, bid.expressLaneController, bid.amount);
        address bidder = bidHash.recover(bid.signature);
        // always check that the bidder has a much as they're claiming
        if (_balanceOf[bidder].balanceAtRound(info.currentRound()) < bid.amount) {
            revert InsufficientBalanceAcc(
                bidder,
                bid.amount,
                _balanceOf[bidder].balanceAtRound(info.currentRound())
            );
        }

        return (bidder, bidHash);
    }

    /// @inheritdoc IExpressLaneAuction
    function resolveSingleBidAuction(Bid calldata firstPriceBid)
        external
        onlyRole(AUCTIONEER_ROLE)
    {
        RoundTimingInfo memory info = roundTimingInfo;
        if (!info.isAuctionRoundClosed()) {
            revert AuctionNotClosed();
        }

        if (firstPriceBid.amount < reservePrice) {
            revert ReservePriceNotMet(firstPriceBid.amount, reservePrice);
        }

        uint64 biddingInRound = info.currentRound();
        uint64 biddingForRound = biddingInRound + 1;
        (address firstPriceBidder, ) = recoverAndCheckBalance(firstPriceBid, biddingForRound, info);

        resolveAuction(false, firstPriceBid, firstPriceBidder, reservePrice, biddingInRound, info);
    }

    /// @inheritdoc IExpressLaneAuction
    function resolveMultiBidAuction(Bid calldata firstPriceBid, Bid calldata secondPriceBid)
        external
        onlyRole(AUCTIONEER_ROLE)
    {
        RoundTimingInfo memory info = roundTimingInfo;
        if (!info.isAuctionRoundClosed()) {
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

        uint64 biddingInRound = info.currentRound();
        uint64 biddingForRound = biddingInRound + 1;
        // check the signatures and balances of both bids
        // even the second price bid must have the balance it's claiming
        (address firstPriceBidder, bytes32 firstBidHash) = recoverAndCheckBalance(
            firstPriceBid,
            biddingForRound,
            info
        );
        (address secondPriceBidder, bytes32 secondBidHash) = recoverAndCheckBalance(
            secondPriceBid,
            biddingForRound,
            info
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
            uint256(keccak256(abi.encodePacked(firstPriceBidder, firstBidHash))) <
            uint256(keccak256(abi.encodePacked(secondPriceBidder, secondBidHash)))
        ) {
            revert TieBidsWrongOrder();
        }

        resolveAuction(
            true,
            firstPriceBid,
            firstPriceBidder,
            secondPriceBid.amount,
            biddingInRound,
            info
        );
    }

    /// @inheritdoc IExpressLaneAuction
    function transferExpressLaneController(uint64 round, address newExpressLaneController)
        external
    {
        // past rounds cannot be transferred
        RoundTimingInfo memory info = roundTimingInfo;
        uint64 curRnd = info.currentRound();
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

        (uint64 start, uint64 end) = info.roundTimestamps(round);
        emit SetExpressLaneController(
            round,
            resolvedELC,
            newExpressLaneController,
            start < uint64(block.timestamp) ? uint64(block.timestamp) : start,
            end
        );
    }

    /// @inheritdoc IExpressLaneAuction
    function resolvedRounds() public view returns (ELCRound memory, ELCRound memory) {
        return
            latestResolvedRounds[0].round > latestResolvedRounds[1].round
                ? (latestResolvedRounds[0], latestResolvedRounds[1])
                : (latestResolvedRounds[1], latestResolvedRounds[0]);
    }
}
