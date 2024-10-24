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
import {IExpressLaneAuction, Bid, InitArgs, Transferor} from "./IExpressLaneAuction.sol";
import {ELCRound, LatestELCRoundsLib} from "./ELCRound.sol";
import {RoundTimingInfo, RoundTimingInfoLib} from "./RoundTimingInfo.sol";
import {
    EIP712Upgradeable
} from "@openzeppelin/contracts-upgradeable/utils/cryptography/draft-EIP712Upgradeable.sol";

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
    bytes32 public constant ROUND_TIMING_SETTER_ROLE = keccak256("ROUND_TIMING_SETTER");

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
    mapping(address => Transferor) public transferorOf;

    /// @inheritdoc IExpressLaneAuction
    function initialize(InitArgs calldata args) public initializer onlyDelegated {
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

        // the initial timestamp cannot be negative
        if (args._roundTimingInfo.offsetTimestamp < 0) {
            revert NegativeOffset();
        }
        setRoundTimingInfoInternal(args._roundTimingInfo);

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
        _grantRole(ROUND_TIMING_SETTER_ROLE, args._roundTimingSetter);
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

    function setRoundTimingInfoInternal(RoundTimingInfo calldata newRoundTimingInfo) internal {
        // auction closing seconds of 0 wouldnt make sense as it would then be impossible to close the round
        // due to the check below this also causes round duration > 0
        if (newRoundTimingInfo.auctionClosingSeconds == 0) {
            revert ZeroAuctionClosingSeconds();
        }

        // ensure that round duration cannot be too high, other wise this could be used to lock balances
        // in the contract by setting round duration = uint.max
        if (newRoundTimingInfo.roundDurationSeconds > 1 days) {
            revert RoundTooLong(newRoundTimingInfo.roundDurationSeconds);
        }

        // the same check as in initialization - reserve submission and auction closing are non overlapping
        // sub sections of a round, so must fit within it
        if (
            newRoundTimingInfo.reserveSubmissionSeconds + newRoundTimingInfo.auctionClosingSeconds >
            newRoundTimingInfo.roundDurationSeconds
        ) {
            revert RoundDurationTooShort();
        }

        roundTimingInfo = newRoundTimingInfo;
        emit SetRoundTimingInfo(
            newRoundTimingInfo.currentRound(),
            newRoundTimingInfo.offsetTimestamp,
            newRoundTimingInfo.roundDurationSeconds,
            newRoundTimingInfo.auctionClosingSeconds,
            newRoundTimingInfo.reserveSubmissionSeconds
        );
    }

    /// @inheritdoc IExpressLaneAuction
    function setRoundTimingInfo(RoundTimingInfo calldata newRoundTimingInfo)
        external
        onlyRole(ROUND_TIMING_SETTER_ROLE)
    {
        RoundTimingInfo memory currentRoundTimingInfo = roundTimingInfo;
        uint64 currentCurrentRound = currentRoundTimingInfo.currentRound();
        uint64 newCurrentRound = newRoundTimingInfo.currentRound();
        // updating round timing info needs to be synchronised
        // so we ensure that the current round won't change
        if (currentCurrentRound != newCurrentRound) {
            revert InvalidNewRound(currentCurrentRound, newCurrentRound);
        }

        (uint64 currentStart, ) = currentRoundTimingInfo.roundTimestamps(currentCurrentRound + 1);
        (uint64 newStart, ) = newRoundTimingInfo.roundTimestamps(newCurrentRound + 1);
        // we also ensure that the current round end time/next round start time, will not change
        if (currentStart != newStart) {
            revert InvalidNewStart(currentStart, newStart);
        }

        setRoundTimingInfoInternal(newRoundTimingInfo);
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
    function balanceOfAtRound(address account, uint64 round) external view returns (uint256) {
        if (round < roundTimingInfo.currentRound()) {
            revert RoundTooOld(round, roundTimingInfo.currentRound());
        }
        return _balanceOf[account].balanceAtRound(round);
    }

    /// @inheritdoc IExpressLaneAuction
    function withdrawableBalance(address account) external view returns (uint256) {
        return _balanceOf[account].withdrawableBalanceAtRound(roundTimingInfo.currentRound());
    }

    /// @inheritdoc IExpressLaneAuction
    function withdrawableBalanceAtRound(address account, uint64 round)
        external
        view
        returns (uint256)
    {
        if (round < roundTimingInfo.currentRound()) {
            revert RoundTooOld(round, roundTimingInfo.currentRound());
        }
        return _balanceOf[account].withdrawableBalanceAtRound(round);
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
    /// @param roundStart The timestamp at which the bidding for round starts
    /// @param roundEnd The timestamp at which the bidding for round ends
    function resolveAuction(
        bool isMultiBid,
        Bid calldata firstPriceBid,
        address firstPriceBidder,
        uint256 priceToPay,
        uint64 biddingInRound,
        uint64 roundStart,
        uint64 roundEnd
    ) internal {
        // store that a round has been resolved
        uint64 biddingForRound = biddingInRound + 1;
        latestResolvedRounds.setResolvedRound(biddingForRound, firstPriceBid.expressLaneController);

        // first price bidder pays the beneficiary
        _balanceOf[firstPriceBidder].reduce(priceToPay, biddingInRound);
        beneficiaryBalance += priceToPay;

        // emit events so that the offchain sequencer knows a new express lane controller has been selected
        emit SetExpressLaneController(
            biddingForRound,
            address(0),
            firstPriceBid.expressLaneController,
            address(0),
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
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @dev Internal bid domain hash
    bytes32 private constant BID_DOMAIN =
        keccak256("Bid(uint64 round,address expressLaneController,uint256 amount)");

    /// @inheritdoc IExpressLaneAuction
    function getBidHash(
        uint64 round,
        address expressLaneController,
        uint256 amount
    ) public view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(abi.encode(BID_DOMAIN, round, expressLaneController, amount))
            );
    }

    /// @notice Recover the signing address of the provided bid, and check that that address has enough funds to fulfil that bid
    ///         Returns the signing address and the bid hash that was signed
    /// @param bid The bid to recover the signing address of
    /// @param biddingForRound The round the bid is for the control of
    function recoverAndCheckBalance(Bid memory bid, uint64 biddingForRound)
        internal
        view
        returns (address, bytes32)
    {
        bytes32 bidHash = getBidHash(biddingForRound, bid.expressLaneController, bid.amount);
        address bidder = bidHash.recover(bid.signature);
        // we are always bidding for in the current round for the next round
        uint64 curRnd = biddingForRound - 1;
        // always check that the bidder has as much as they're claiming
        if (_balanceOf[bidder].balanceAtRound(curRnd) < bid.amount) {
            revert InsufficientBalanceAcc(
                bidder,
                bid.amount,
                _balanceOf[bidder].balanceAtRound(curRnd)
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
        (address firstPriceBidder, ) = recoverAndCheckBalance(firstPriceBid, biddingForRound);

        (uint64 roundStart, uint64 roundEnd) = info.roundTimestamps(biddingForRound);
        resolveAuction(
            false,
            firstPriceBid,
            firstPriceBidder,
            reservePrice,
            biddingInRound,
            roundStart,
            roundEnd
        );
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
            biddingForRound
        );
        (address secondPriceBidder, bytes32 secondBidHash) = recoverAndCheckBalance(
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
            uint256(keccak256(abi.encodePacked(firstPriceBidder, firstBidHash))) <
            uint256(keccak256(abi.encodePacked(secondPriceBidder, secondBidHash)))
        ) {
            revert TieBidsWrongOrder();
        }

        (uint64 roundStart, uint64 roundEnd) = info.roundTimestamps(biddingForRound);
        resolveAuction(
            true,
            firstPriceBid,
            firstPriceBidder,
            secondPriceBid.amount,
            biddingInRound,
            roundStart,
            roundEnd
        );
    }

    /// @inheritdoc IExpressLaneAuction
    function setTransferor(Transferor calldata transferor) external {
        // if a transferor has already been set, it may be fixed until a future round
        Transferor storage currentTransferor = transferorOf[msg.sender];
        if (
            currentTransferor.addr != address(0) &&
            currentTransferor.fixedUntilRound > roundTimingInfo.currentRound()
        ) {
            revert FixedTransferor(currentTransferor.fixedUntilRound);
        }

        transferorOf[msg.sender] = transferor;

        emit SetTransferor(msg.sender, transferor.addr, transferor.fixedUntilRound);
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
        address transferor = transferorOf[resolvedELC].addr;
        // can only be the transferor if one has been set
        // otherwise we default to the express lane controller to do the transfer
        if (transferor != address(0)) {
            if (transferor != msg.sender) {
                revert NotTransferor(round, transferor, msg.sender);
            }
        } else if (resolvedELC != msg.sender) {
            revert NotExpressLaneController(round, resolvedELC, msg.sender);
        }

        resolvedRound.expressLaneController = newExpressLaneController;

        (uint64 start, uint64 end) = info.roundTimestamps(round);
        emit SetExpressLaneController(
            round,
            resolvedELC,
            newExpressLaneController,
            transferor != address(0) ? transferor : resolvedELC,
            start < uint64(block.timestamp) ? uint64(block.timestamp) : start,
            end
        );
    }

    /// @inheritdoc IExpressLaneAuction
    function resolvedRounds() external view returns (ELCRound memory, ELCRound memory) {
        return
            latestResolvedRounds[0].round > latestResolvedRounds[1].round
                ? (latestResolvedRounds[0], latestResolvedRounds[1])
                : (latestResolvedRounds[1], latestResolvedRounds[0]);
    }
}
