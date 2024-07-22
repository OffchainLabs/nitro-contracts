// SPDX-License-Identifier: UNLICENSED
// CHRIS: TODO: choose sol version
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "../../src/express-lane-auction/ExpressLaneAuction.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("LANE", "LNE") {
        _mint(msg.sender, 1_000_000);
    }
}

contract ExpressLaneAuctionTest is Test {
    using ECDSA for bytes;
    using ECDSA for bytes32;

    // CHRIS: TODO: if we use a higher sol version we dont have to do this additional declaration
    event Deposit(address indexed account, uint256 amount);
    event WithdrawalInitiated(
        address indexed account, uint256 withdrawalAmount, uint256 roundWithdrawable
    );
    event WithdrawalFinalized(address indexed account, uint256 withdrawalAmount);
    event AuctionResolved(
        bool indexed isMultiBidAuction,
        uint64 round,
        address indexed firstPriceBidder,
        address indexed firstPriceElectionController,
        uint256 firstPriceAmount,
        uint256 price,
        uint64 roundStartTimestamp,
        uint64 roundEndTimestamp
    );
    event SetReservePrice(uint256 oldReservePrice, uint256 newReservePrice);
    event SetMinReservePrice(uint256 oldPrice, uint256 newPrice);
    event SetExpressLaneController(
        uint64 round, address from, address to, uint64 startTimestamp, uint64 endTimestamp
    );
    event SetBeneficiary(address oldBeneficiary, address newBeneficiary);

    uint64 roundDuration = 60; // 1 min

    // CHRIS: TODO: move these into an array and structs
    uint256 bidder1PrivKey = 137;
    // CHRIS: TODO: can insted use: vm.createWallet(uint256(keccak256(bytes("1"))));
    address bidder1 = vm.addr(bidder1PrivKey);
    // CHRIS: TODO: use bigger numbers (eg mul 10**18)
    address elc1 = vm.addr(138);
    uint256 bidder1Amount = roundDuration;

    uint256 bidder2PrivKey = 139;
    address bidder2 = vm.addr(bidder2PrivKey);
    // CHRIS: TODO: should use hashes here like (uint256(keccak256(bytes("1"))));
    address elc2 = vm.addr(140);
    uint256 bidder2Amount = roundDuration * 3;

    uint256 bidder3PrivKey = 141;
    address bidder3 = vm.addr(bidder3PrivKey);
    address elc3 = vm.addr(142);
    // CHRIS: TODO: use bigger numbers
    uint256 bidder3Amount = roundDuration * 4;

    uint256 bidder4PrivKey = 143;
    address bidder4 = vm.addr(bidder4PrivKey);
    address elc4 = vm.addr(144);
    uint256 bidder4Amount = roundDuration * 5;

    address beneficiary = vm.addr(145);
    uint256 initialTimestamp = block.timestamp;

    address auctioneer = vm.addr(146);

    address roleAdmin = vm.addr(147);
    uint256 minReservePrice = roundDuration / 10;
    address minReservePriceSetter = vm.addr(148);
    address reservePriceSetter = vm.addr(149);
    address beneficiarySetter = vm.addr(150);
    uint64 testRound = 13;

    // CHRIS: TODO: allow updating of round time, but be careful: a party could potentially lock the funds forever by setting the round time to max - this should be written as a known risk

    // CHRIS: TODO: rewrite the spec to have offchain and onchain components
    // CHRIS: TODO: describe the different actors in the system
    // CHRIS: TODO: examine all the different actors in the system, how can they affect other parties
    // CHRIS: TODO: draw diagrams for it

    // CHRIS: TODO: gotcha: always ensure you are synced up to past the boundary before opening the auction. Otherwise you may have out of date info.
    // CHRIS: TODO: guarantee: a round cannot be resolved twice
    // CHRIS: TODO: guarantee: funds cannot be locked indefinately or stolen, unless the contract is upgraded

    // moves that can be made in certain periods
    // explicitly state at which point a move can be made and why
    // 1. deposit - anytime
    // 2. intiate withdrawal - anytime
    // 3. finalize withdrawal - anytime
    // 4. resolve auction - only during the closing period
    // 5. update reserve price - only during the update period, or anytime if updated when updating min reserve
    // 6. update round duration - anytime
    // 7. update minimum reserve - anytime

    // CHRIS: TODO: guarantees around when the auction will be resolved - none required, but advice should be to resolve promptly so as to give assurance of not waiting for longer bid, and to give time for reserve to be set
    // CHRIS: TODO: how do we stop the auctioneer from keeping the bidding open? or even from manufacturing a bid? - we cant in this system

    // CHRIS: TODO: we should return an IIExpressLaneAuction from deploy

    function deploy() internal returns (MockERC20, IExpressLaneAuction) {
        MockERC20 token = new MockERC20();
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        ExpressLaneAuction impl = new ExpressLaneAuction();
        
        ExpressLaneAuction auction = ExpressLaneAuction(address(new TransparentUpgradeableProxy(
            address(impl),
            address(proxyAdmin),
            ""
        )));
        auction.initialize(
            auctioneer,
            beneficiary,
            address(token),
            RoundTimingInfo({
                offsetTimestamp: uint64(block.timestamp) + 10,
                roundDurationSeconds: roundDuration,
                auctionClosingSeconds: roundDuration / 4,
                reserveSubmissionSeconds: roundDuration / 4
            }),
            minReservePrice,
            roleAdmin,
            minReservePriceSetter,
            reservePriceSetter,
            beneficiarySetter
        );

        // move to round test round
        (uint64 offsetTimestamp,uint64 roundDurationSeconds,,) = auction.roundTimingInfo();
        vm.warp(offsetTimestamp + roundDurationSeconds * testRound);

        return (token, IExpressLaneAuction(auction));
    }

    function testInit() public {
        MockERC20 token = new MockERC20();
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        ExpressLaneAuction impl = new ExpressLaneAuction();
        
        vm.expectRevert("Function must be called through delegatecall");
        impl.initialize(
            auctioneer,
            beneficiary,
            address(token),
            RoundTimingInfo({
                offsetTimestamp: uint64(block.timestamp) + 10,
                roundDurationSeconds: roundDuration,
                auctionClosingSeconds: roundDuration / 4,
                reserveSubmissionSeconds: roundDuration / 4
            }),
            minReservePrice,
            roleAdmin,
            minReservePriceSetter,
            reservePriceSetter,
            beneficiarySetter
        );
        
        ExpressLaneAuction auction = ExpressLaneAuction(address(new TransparentUpgradeableProxy(
            address(impl),
            address(proxyAdmin),
            ""
        )));

        vm.expectRevert(abi.encodeWithSelector(ZeroBiddingToken.selector));
        auction.initialize(
            auctioneer,
            beneficiary,
            address(0),
            RoundTimingInfo({
                offsetTimestamp: uint64(block.timestamp) + 10,
                roundDurationSeconds: roundDuration,
                auctionClosingSeconds: roundDuration / 4,
                reserveSubmissionSeconds: roundDuration / 4
            }),
            minReservePrice,
            roleAdmin,
            minReservePriceSetter,
            reservePriceSetter,
            beneficiarySetter
        );

        vm.expectRevert(abi.encodeWithSelector(RoundDurationTooShort.selector));
        auction.initialize(
            auctioneer,
            beneficiary,
            address(token),
            RoundTimingInfo({
                offsetTimestamp: uint64(block.timestamp) + 10,
                roundDurationSeconds: roundDuration,
                auctionClosingSeconds: roundDuration / 2,
                reserveSubmissionSeconds: roundDuration * 2 + 1
            }),
            minReservePrice,
            roleAdmin,
            minReservePriceSetter,
            reservePriceSetter,
            beneficiarySetter
        );

        vm.expectEmit(true, true, true, true);
        emit SetBeneficiary(address(0), beneficiary);
        vm.expectEmit(true, true, true, true);
        emit SetMinReservePrice(uint256(0), minReservePrice);
        vm.expectEmit(true, true, true, true);
        emit SetReservePrice(uint256(0), minReservePrice);
        auction.initialize(
            auctioneer,
            beneficiary,
            address(token),
            RoundTimingInfo({
                offsetTimestamp: uint64(block.timestamp) + 10,
                roundDurationSeconds: roundDuration,
                auctionClosingSeconds: roundDuration / 4,
                reserveSubmissionSeconds: roundDuration / 4
            }),
            minReservePrice,
            roleAdmin,
            minReservePriceSetter,
            reservePriceSetter,
            beneficiarySetter
        );
        (uint64 offsetTimestamp, uint64 roundDurationSeconds,uint64 auctionClosingSeconds,uint64 reserveSubmissionSeconds) = auction.roundTimingInfo();
        assertEq(address(auction.biddingToken()), address(token), "bidding token");
        assertEq(auction.beneficiary(), beneficiary, "beneficiary");
        assertEq(auction.minReservePrice(), minReservePrice, "min reserve price");
        assertEq(auction.reservePrice(), minReservePrice, "reserve price");
        assertEq(offsetTimestamp, uint64(block.timestamp) + 10);
        assertEq(auctionClosingSeconds, roundDuration / 4, "auction closing duration");
        assertEq(roundDurationSeconds, roundDuration, "auction round duration");
        assertEq(reserveSubmissionSeconds, roundDuration / 4, "reserve submission seconds");

        assertTrue(auction.hasRole(auction.DEFAULT_ADMIN_ROLE(), roleAdmin), "admin role");
        assertTrue(auction.hasRole(auction.MIN_RESERVE_SETTER_ROLE(), minReservePriceSetter), "min reserve price setter role");
        assertTrue(auction.hasRole(auction.RESERVE_SETTER_ROLE(), reservePriceSetter), "reserve price setter role");
        assertTrue(auction.hasRole(auction.BENEFICIARY_SETTER_ROLE(), beneficiarySetter), "beneficiary setter role");

        vm.expectRevert("Initializable: contract is already initialized");
        auction.initialize(
            auctioneer,
            beneficiary,
            address(token),
            RoundTimingInfo({
                offsetTimestamp: uint64(block.timestamp) + 10,
                roundDurationSeconds: roundDuration,
                auctionClosingSeconds: roundDuration / 4,
                reserveSubmissionSeconds: roundDuration / 4
            }),
            minReservePrice,
            roleAdmin,
            minReservePriceSetter,
            reservePriceSetter,
            beneficiarySetter
        );

        // cannot send funds to the contract
        (bool success,) = address(auction).call{ value: 10 }(hex"");
        assertFalse(success, "auction value call");
        assertEq(address(auction).balance, 0, "bal after");
    }

    function deployAndDeposit() internal returns (MockERC20, IExpressLaneAuction) {
        (MockERC20 erc20, IExpressLaneAuction auction) = deploy();
        erc20.transfer(bidder1, bidder1Amount);
        erc20.transfer(bidder2, bidder2Amount);
        erc20.transfer(bidder3, bidder3Amount);
        erc20.transfer(bidder4, bidder4Amount);

        vm.startPrank(bidder1);
        erc20.approve(address(auction), bidder1Amount);
        auction.deposit(bidder1Amount);
        vm.stopPrank();

        vm.startPrank(bidder2);
        erc20.approve(address(auction), bidder2Amount);
        auction.deposit(bidder2Amount);
        vm.stopPrank();

        vm.startPrank(bidder3);
        erc20.approve(address(auction), bidder3Amount);
        auction.deposit(bidder3Amount);
        vm.stopPrank();

        vm.startPrank(bidder4);
        erc20.approve(address(auction), bidder4Amount);
        auction.deposit(bidder4Amount);
        vm.stopPrank();

        return (erc20, auction);
    }

    function testDeposit() public {
        (MockERC20 erc20, IExpressLaneAuction auction) = deploy();

        erc20.transfer(bidder1, bidder1Amount);
        erc20.transfer(bidder2, bidder2Amount);

        // cannot deposit without approval
        vm.startPrank(bidder1);
        // error: ERC20InsufficientAllowance(0x2e234DAe75C793f67A35089C9d99245E1C58470b, 0, 20)
        // vm.expectRevert(
        //     hex"fb8f41b20000000000000000000000002e234dae75c793f67a35089c9d99245e1c58470b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000014"
        // );
        vm.expectRevert(abi.encodePacked("ERC20: insufficient allowance"));
        auction.deposit(20);

        vm.expectRevert(ZeroAmount.selector);
        auction.deposit(0);

        // cannot deposit 0
        erc20.approve(address(auction), 20);
        vm.expectEmit(true, true, true, true);
        emit Deposit(bidder1, 20);
        auction.deposit(20);
        assertEq(auction.balanceOf(bidder1), 20, "First balance");
        assertEq(erc20.balanceOf(bidder1), bidder1Amount - 20, "First bidder1 erc20 balance");
        assertEq(erc20.balanceOf(address(auction)), 20, "First auction erc20 balance");

        // can deposit twice
        erc20.approve(address(auction), bidder1Amount - 20);
        vm.expectEmit(true, true, true, true);
        emit Deposit(bidder1, bidder1Amount - 20);
        auction.deposit(bidder1Amount - 20);
        assertEq(auction.balanceOf(bidder1), bidder1Amount, "Full first balance");
        assertEq(erc20.balanceOf(bidder1), 0, "Full first bidder1 erc20 balance");
        assertEq(
            erc20.balanceOf(address(auction)), bidder1Amount, "Full dirst auction erc20 balance"
        );
        vm.stopPrank();

        // can deposit different bidder, do it once per second for 2 rounds
        // to ensure that deposit can occur at any time
        vm.startPrank(bidder2);
        (,uint64 roundDurationSeconds,,) = auction.roundTimingInfo();
        erc20.approve(address(auction), roundDurationSeconds * 3);
        for (uint256 i = 0; i < roundDurationSeconds * 3; i++) {
            vm.warp(block.timestamp + 1);
            vm.expectEmit(true, true, true, true);
            emit Deposit(bidder2, 1);
            auction.deposit(1);
            assertEq(auction.balanceOf(bidder2), i + 1, "Second balance");
            assertEq(
                erc20.balanceOf(bidder2), bidder2Amount - i - 1, "Second bidder2 erc20 balance"
            );
            assertEq(
                erc20.balanceOf(address(auction)),
                bidder1Amount + i + 1,
                "Second auction erc20 balance"
            );
        }
        vm.stopPrank();
    }

    // CHRIS: TODO: tests for round duration

    function testCurrentRound() public {
        (, IExpressLaneAuction auction) = deploy();
        vm.warp(1);
        assertEq(auction.currentRound(), 0);

        (uint64 offsetTimestamp,uint64 roundDurationSeconds,,) = auction.roundTimingInfo();

        vm.warp(offsetTimestamp - 1);
        assertEq(auction.currentRound(), 0);

        for (uint256 i = 0; i < testRound; i++) {
            for (uint256 j = 0; j < roundDurationSeconds; j++) {
                vm.warp(block.timestamp + 1);
                assertEq(auction.currentRound(), i);
            }
        }
    }

    // CHRIS: TODO: rework all the expected balance tests
    function testInitiateWithdrawal() public {
        (MockERC20 erc20, IExpressLaneAuction auction) = deployAndDeposit();
        uint256 curRound = auction.currentRound();

        vm.startPrank(beneficiary);
        // dont expect the beneficiary to have anything to withdraw
        vm.expectRevert(ZeroAmount.selector);
        auction.initiateWithdrawal();
        vm.stopPrank();

        vm.startPrank(bidder1);

        // 1. Withdraw once, then test it's not possible to withdraw in any future rounds
        vm.expectEmit(true, true, true, true);
        emit WithdrawalInitiated(bidder1, bidder1Amount, curRound + 2);
        auction.initiateWithdrawal();
        assertEq(auction.currentRound(), curRound);
        assertEq(auction.balanceOf(bidder1), bidder1Amount);
        assertEq(auction.withdrawableBalance(bidder1), 0);

        // round 1.5
        (, uint64 roundDurationSeconds,,) = auction.roundTimingInfo();
        vm.warp(block.timestamp + roundDurationSeconds / 2);

        assertEq(auction.currentRound(), curRound);
        assertEq(auction.balanceOf(bidder1), bidder1Amount);
        assertEq(auction.withdrawableBalance(bidder1), 0);

        vm.expectRevert(abi.encodeWithSelector(WithdrawalInProgress.selector));
        auction.initiateWithdrawal();

        // round 2
        vm.warp(block.timestamp + roundDurationSeconds / 2);

        assertEq(auction.currentRound(), curRound + 1);
        assertEq(auction.balanceOf(bidder1), bidder1Amount);
        assertEq(auction.withdrawableBalance(bidder1), 0);

        vm.expectRevert(abi.encodeWithSelector(WithdrawalInProgress.selector));
        auction.initiateWithdrawal();

        // round 2.5
        vm.warp(block.timestamp + roundDurationSeconds / 2);
        assertEq(auction.currentRound(), curRound + 1);
        assertEq(auction.balanceOf(bidder1), bidder1Amount);
        assertEq(auction.withdrawableBalance(bidder1), 0);

        // round 3
        vm.warp(block.timestamp + roundDurationSeconds / 2);
        assertEq(auction.currentRound(), curRound + 2);
        assertEq(auction.balanceOf(bidder1), 0);
        assertEq(auction.withdrawableBalance(bidder1), bidder1Amount, "withdrawal 3");

        vm.expectRevert(abi.encodeWithSelector(WithdrawalInProgress.selector));
        auction.initiateWithdrawal();

        // round 3.5
        vm.warp(block.timestamp + roundDurationSeconds / 2);
        assertEq(auction.currentRound(), curRound + 2);
        assertEq(auction.balanceOf(bidder1), 0);
        assertEq(auction.withdrawableBalance(bidder1), bidder1Amount);

        // round 4
        vm.warp(block.timestamp + roundDurationSeconds / 2);
        assertEq(auction.currentRound(), curRound + 3);
        assertEq(auction.balanceOf(bidder1), 0);
        assertEq(auction.withdrawableBalance(bidder1), bidder1Amount);

        vm.expectRevert(abi.encodeWithSelector(WithdrawalInProgress.selector));
        auction.initiateWithdrawal();

        // finalize and initiate a new withdrawal
        auction.finalizeWithdrawal();
        // round 4.5
        vm.warp(block.timestamp + roundDurationSeconds / 2);
        assertEq(auction.currentRound(), curRound + 3);
        assertEq(auction.balanceOf(bidder1), 0);
        assertEq(auction.withdrawableBalance(bidder1), 0);

        vm.expectRevert(ZeroAmount.selector);
        auction.initiateWithdrawal();


        erc20.approve(address(auction), bidder1Amount / 2);
        auction.deposit(bidder1Amount / 2);
        auction.initiateWithdrawal();
        assertEq(auction.currentRound(), curRound + 3);
        assertEq(auction.balanceOf(bidder1), bidder1Amount / 2);
        assertEq(auction.withdrawableBalance(bidder1), 0);

        // round 5
        vm.warp(block.timestamp + roundDurationSeconds / 2);
        assertEq(auction.currentRound(), curRound + 4);
        assertEq(auction.balanceOf(bidder1), bidder1Amount / 2);
        assertEq(auction.withdrawableBalance(bidder1), 0);

        // round 6
        vm.warp(block.timestamp + roundDurationSeconds);
        assertEq(auction.currentRound(), curRound + 5);
        assertEq(auction.balanceOf(bidder1), 0);
        assertEq(auction.withdrawableBalance(bidder1), bidder1Amount / 2);
        auction.finalizeWithdrawal();
        assertEq(auction.currentRound(), curRound + 5);
        assertEq(auction.balanceOf(bidder1), 0);
        assertEq(auction.withdrawableBalance(bidder1), 0);

        // round 7
        vm.stopPrank();

        // CHRIS: TODO: remainig tests initiate withdrawal tests
        // * above guarantees are not effected by round time updates
        // * cant initiate withdrawal when offset is in the future (leave this one, since we might allow it, erm, no point lol, could set it to max, and then allow withdrawal, best to revert for now)
    }

    function testFinalizeWithdrawal() public {
        (MockERC20 erc20, IExpressLaneAuction auction) = deployAndDeposit();
        uint256 curRound = auction.currentRound();

        assertEq(auction.currentRound(), curRound);
        assertEq(auction.balanceOf(bidder1), bidder1Amount);
        assertEq(auction.withdrawableBalance(bidder1), 0);

        // finalize withdrawal tests
        vm.startPrank(bidder1);
        vm.expectRevert(abi.encodeWithSelector(NothingToWithdraw.selector));
        auction.finalizeWithdrawal();

        auction.initiateWithdrawal();

        assertEq(auction.currentRound(), curRound);
        assertEq(auction.balanceOf(bidder1), bidder1Amount);
        assertEq(auction.withdrawableBalance(bidder1), 0);

        // expect revert
        vm.expectRevert(abi.encodeWithSelector(NothingToWithdraw.selector));
        auction.finalizeWithdrawal();

        (,uint64 roundDurationSeconds,,) = auction.roundTimingInfo();
        vm.warp(block.timestamp + roundDurationSeconds);

        assertEq(auction.currentRound(), curRound + 1);
        assertEq(auction.balanceOf(bidder1), bidder1Amount);
        assertEq(auction.withdrawableBalance(bidder1), 0);

        // expect revert
        vm.expectRevert(abi.encodeWithSelector(NothingToWithdraw.selector));
        auction.finalizeWithdrawal();

        vm.warp(block.timestamp + roundDurationSeconds);

        assertEq(auction.currentRound(), curRound + 2);
        assertEq(auction.balanceOf(bidder1), 0);
        assertEq(auction.withdrawableBalance(bidder1), bidder1Amount);

        // expect emit
        uint256 bidderErc20BalBefore = erc20.balanceOf(bidder1);
        uint256 auctionErc20BalBefore = erc20.balanceOf(address(auction));
        vm.expectEmit(true, true, true, true);
        emit WithdrawalFinalized(bidder1, bidder1Amount);
        auction.finalizeWithdrawal();

        assertEq(auction.currentRound(), curRound + 2, "round end");
        assertEq(auction.balanceOf(bidder1), 0, "balance end");
        assertEq(auction.withdrawableBalance(bidder1), 0, "withdrawable balance end");
        uint256 bidderErc20BalAfter = erc20.balanceOf(bidder1);
        uint256 auctionErc20BalAfter = erc20.balanceOf(address(auction));
        assertEq(bidderErc20BalAfter, bidderErc20BalBefore + bidder1Amount, "balance after");
        assertEq(auctionErc20BalAfter, auctionErc20BalBefore - bidder1Amount, "auction balance after");

        // expect revert
        vm.expectRevert(abi.encodeWithSelector(NothingToWithdraw.selector));
        auction.finalizeWithdrawal();

        vm.stopPrank();

        // CHRIS: TODO:
        // * reducing the round time does have an effect - add this later
        // * cannot finalize withdrawal too soon - comments about how this will work during an upgrade/change of time
    }

    function testFinalizeLateWithdrawal() public {
        (MockERC20 erc20, IExpressLaneAuction auction) = deployAndDeposit();
        uint256 curRound = auction.currentRound();

        assertEq(auction.currentRound(), curRound);
        assertEq(auction.balanceOf(bidder1), bidder1Amount);
        assertEq(auction.withdrawableBalance(bidder1), 0);

        // finalize withdrawal tests
        vm.startPrank(bidder1);

        auction.initiateWithdrawal();

        (,uint64 roundDurationSeconds,,) = auction.roundTimingInfo();
        vm.warp(block.timestamp + roundDurationSeconds * 5);

        assertEq(auction.currentRound(), curRound + 5);
        assertEq(auction.balanceOf(bidder1), 0);
        assertEq(auction.withdrawableBalance(bidder1), bidder1Amount);

        // expect emit
        uint256 bidderErc20BalBefore = erc20.balanceOf(bidder1);
        uint256 auctionErc20BalBefore = erc20.balanceOf(address(auction));
        vm.expectEmit(true, true, true, true);
        emit WithdrawalFinalized(bidder1, bidder1Amount);
        auction.finalizeWithdrawal();

        assertEq(auction.currentRound(), curRound + 5);
        assertEq(auction.balanceOf(bidder1), 0);
        assertEq(auction.withdrawableBalance(bidder1), 0);
        uint256 bidderErc20BalAfter = erc20.balanceOf(bidder1);
        uint256 auctionErc20BalAfter = erc20.balanceOf(address(auction));
        assertEq(bidderErc20BalAfter, bidderErc20BalBefore + bidder1Amount);
        assertEq(auctionErc20BalAfter, auctionErc20BalBefore - bidder1Amount);

        vm.stopPrank();
    }

    function sign(uint256 privKey, bytes32 h) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, h);
        return abi.encodePacked(r, s, v);
    }

    struct ResolveSetup {
        MockERC20 erc20;
        IExpressLaneAuction auction;
        Bid bid1;
        Bid bid2;
        bytes32 h1;
        bytes32 h2;
        uint64 biddingForRound;
    }

    function deployDepositAndBids() public returns (ResolveSetup memory) {
        (MockERC20 erc20, IExpressLaneAuction auction) = deployAndDeposit();
        uint64 biddingForRound = auction.currentRound() + 1;

        bytes32 h1 =
            auction.getBidBytes(biddingForRound, bidder1Amount / 2, elc1).toEthSignedMessageHash();
        Bid memory bid1 = Bid({
            amount: bidder1Amount / 2,
            expressLaneController: elc1,
            signature: sign(bidder1PrivKey, h1)
        });
        bytes32 h2 =
            auction.getBidBytes(biddingForRound, bidder2Amount / 2, elc2).toEthSignedMessageHash();
        Bid memory bid2 = Bid({
            amount: bidder2Amount / 2,
            expressLaneController: elc2,
            signature: sign(bidder2PrivKey, h2)
        });

        (,uint64 roundDurationSeconds, uint64 auctionClosingSeconds,) = auction.roundTimingInfo();

        vm.warp(block.timestamp + roundDurationSeconds - auctionClosingSeconds);

        vm.startPrank(auctioneer);

        return ResolveSetup({
            erc20: erc20,
            auction: auction,
            bid1: bid1,
            bid2: bid2,
            h1: h1,
            h2: h2,
            biddingForRound: biddingForRound
        });
    }

    function testCannotResolveNotAuctioneer() public {
        ResolveSetup memory rs = deployDepositAndBids();
        vm.stopPrank();

        bytes memory revertString = abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(uint160(bidder4), 20),
            " is missing role ",
            Strings.toHexString(uint256(rs.auction.AUCTIONEER_ROLE()), 32)
        );

        vm.startPrank(bidder4);
        vm.expectRevert(revertString);
        rs.auction.resolveMultiBidAuction(rs.bid2, rs.bid1);
        vm.stopPrank();

        vm.startPrank(bidder4);
        vm.expectRevert(revertString);
        rs.auction.resolveSingleBidAuction(rs.bid1);
        vm.stopPrank();
    }

    function testCannotResolveSamePerson() public {
        ResolveSetup memory rs = deployDepositAndBids();

        rs.bid1.signature = sign(bidder2PrivKey, rs.h1);

        vm.expectRevert(SameBidder.selector);
        rs.auction.resolveMultiBidAuction(rs.bid2, rs.bid1);
    }

    function testCannotResolveBidWrongOrder() public {
        ResolveSetup memory rs = deployDepositAndBids();
        vm.expectRevert(BidsWrongOrder.selector);
        rs.auction.resolveMultiBidAuction(rs.bid1, rs.bid2);
    }

    function testCannotResolveTieBidWrongOrder() public {
        ResolveSetup memory rs = deployDepositAndBids();

        // bid2.amount == bid1.amount
        bytes32 h2 =
            rs.auction.getBidBytes(rs.biddingForRound, bidder1Amount / 2, elc1).toEthSignedMessageHash();
        Bid memory bid2 = Bid({
            amount: bidder1Amount / 2,
            expressLaneController: elc1,
            signature: sign(bidder2PrivKey, h2)
        });

        vm.expectRevert(TieBidsWrongOrder.selector);
        rs.auction.resolveMultiBidAuction(rs.bid1, bid2);

        // success now with the same price
        rs.auction.resolveMultiBidAuction(bid2, rs.bid1);
    }

    function testCannotResolveReserveNotMet() public {
        ResolveSetup memory rs = deployDepositAndBids();

        bytes32 h1 = rs.auction.getBidBytes(rs.biddingForRound, minReservePrice - 1, elc1)
            .toEthSignedMessageHash();
        Bid memory bid1 = Bid({
            amount: minReservePrice - 1,
            expressLaneController: elc1,
            signature: sign(bidder1PrivKey, h1)
        });

        vm.expectRevert(
            abi.encodeWithSelector(ReservePriceNotMet.selector, minReservePrice - 1, minReservePrice)
        );
        rs.auction.resolveMultiBidAuction(rs.bid2, bid1);

        vm.expectRevert(
            abi.encodeWithSelector(ReservePriceNotMet.selector, minReservePrice - 1, minReservePrice)
        );
        rs.auction.resolveSingleBidAuction(bid1);
    }

    function testCannotResolveInsufficientFunds() public {
        ResolveSetup memory rs = deployDepositAndBids();

        bytes32 h2 = rs.auction.getBidBytes(rs.biddingForRound, bidder2Amount * 2, elc2)
            .toEthSignedMessageHash();
        Bid memory bid2 = Bid({
            amount: bidder2Amount * 2,
            expressLaneController: elc2,
            signature: sign(bidder2PrivKey, h2)
        });

        vm.expectRevert(
            abi.encodeWithSelector(InsufficientBalanceAcc.selector, bidder2, bidder2Amount * 2, bidder2Amount)
        );
        rs.auction.resolveMultiBidAuction(bid2, rs.bid1);

        bytes32 h1 = rs.auction.getBidBytes(rs.biddingForRound, bidder1Amount * 3 / 2, elc1)
            .toEthSignedMessageHash();
        Bid memory bid1 = Bid({
            amount: bidder1Amount * 3 / 2,
            expressLaneController: elc1,
            signature: sign(bidder1PrivKey, h1)
        });

        vm.expectRevert(
            abi.encodeWithSelector(InsufficientBalanceAcc.selector, bidder1, bidder1Amount * 3 / 2, bidder1Amount)
        );
        rs.auction.resolveMultiBidAuction(rs.bid2, bid1);

        vm.expectRevert(
            abi.encodeWithSelector(InsufficientBalanceAcc.selector, bidder2, bidder2Amount * 2, bidder2Amount)
        );
        rs.auction.resolveSingleBidAuction(bid2);
    }

    function testCannotResolveWrongChain() public {
        ResolveSetup memory rs = deployDepositAndBids();

        bytes32 h2 = abi.encodePacked(
                block.chainid * 137,
                address(rs.auction),
                rs.biddingForRound,
                bidder2Amount / 2,
                elc2
            ).toEthSignedMessageHash();
        
        Bid memory bid2 = Bid({
            amount: bidder2Amount / 2,
            expressLaneController: elc2,
            signature: sign(bidder2PrivKey, h2)
        });
        bytes memory correctH2 = abi.encodePacked(block.chainid, address(rs.auction), rs.biddingForRound, bidder2Amount / 2, elc2);
        address wrongBidder2 = correctH2.toEthSignedMessageHash().recover(bid2.signature);

        // wrong chain means wrong hash means wrong address
        vm.expectRevert(abi.encodeWithSelector(InsufficientBalanceAcc.selector, wrongBidder2,  bidder2Amount / 2, 0));
        rs.auction.resolveMultiBidAuction(bid2, rs.bid1);

        bytes32 h1 = 
            abi.encodePacked(
                block.chainid * 137,
                address(rs.auction),
                rs.biddingForRound,
                bidder1Amount / 2,
                elc1
            ).toEthSignedMessageHash();
        
        Bid memory bid1 = Bid({
            amount: bidder1Amount / 2,
            expressLaneController: elc1,
            signature: sign(bidder1PrivKey, h1)
        });
        bytes memory correctH1 = 
            abi.encodePacked(block.chainid, address(rs.auction), rs.biddingForRound, bidder1Amount / 2, elc1);
        
        address wrongBidder1 = correctH1.toEthSignedMessageHash().recover(bid1.signature);

        // wrong chain means wrong hash means wrong address
        vm.expectRevert(abi.encodeWithSelector(InsufficientBalanceAcc.selector, wrongBidder1, bidder1Amount / 2, 0));
        rs.auction.resolveMultiBidAuction(rs.bid2, bid1);

        // wrong chain means wrong hash means wrong address
        vm.expectRevert(abi.encodeWithSelector(InsufficientBalanceAcc.selector, wrongBidder2, bidder2Amount / 2, 0));
        rs.auction.resolveSingleBidAuction(bid2);
    }

    function testCannotResolveWrongContract() public {
        ResolveSetup memory rs = deployDepositAndBids();

        bytes32 h2 = abi.encodePacked(block.chainid, bidder4, rs.biddingForRound, bidder2Amount / 2, elc2).toEthSignedMessageHash();
        Bid memory bid2 = Bid({
            amount: bidder2Amount / 2,
            expressLaneController: elc2,
            signature: sign(bidder2PrivKey, h2)
        });
        bytes memory correctH2 = abi.encodePacked(block.chainid, address(rs.auction), rs.biddingForRound, bidder2Amount / 2, elc2);
        address wrongBidder2 = correctH2.toEthSignedMessageHash().recover(bid2.signature);

        // wrong chain means wrong hash means wrong address
        vm.expectRevert(abi.encodeWithSelector(InsufficientBalanceAcc.selector, wrongBidder2, bidder2Amount / 2, 0));
        rs.auction.resolveMultiBidAuction(bid2, rs.bid1);

        bytes32 h1 = abi.encodePacked(block.chainid, bidder4, rs.biddingForRound, bidder1Amount / 2, elc1).toEthSignedMessageHash();
        Bid memory bid1 = Bid({
            amount: bidder1Amount / 2,
            expressLaneController: elc1,
            signature: sign(bidder1PrivKey, h1)
        });
        bytes memory correctH1 = 
            abi.encodePacked(block.chainid, address(rs.auction), rs.biddingForRound, bidder1Amount / 2, elc1);
        address wrongBidder1 = correctH1.toEthSignedMessageHash().recover(bid1.signature);

        // wrong chain means wrong hash means wrong address
        vm.expectRevert(abi.encodeWithSelector(InsufficientBalanceAcc.selector, wrongBidder1, bidder1Amount / 2, 0));
        rs.auction.resolveMultiBidAuction(rs.bid2, bid1);

        // wrong chain means wrong hash means wrong address
        vm.expectRevert(abi.encodeWithSelector(InsufficientBalanceAcc.selector, wrongBidder1, bidder1Amount / 2, 0));
        rs.auction.resolveSingleBidAuction(bid1);
    }

    error ECDSAInvalidSignature();

    function testCannotResolveWrongSig() public {
        ResolveSetup memory rs = deployDepositAndBids();

        bytes32 h2 = keccak256(
            abi.encodePacked(
                block.chainid, address(rs.auction), rs.biddingForRound, bidder2Amount / 2, elc2
            )
        );
        (, bytes32 r2, bytes32 s2) = vm.sign(bidder2PrivKey, h2);
        uint8 badV = 17;
        Bid memory bid2 = Bid({
            amount: bidder2Amount / 2,
            expressLaneController: elc2,
            signature: abi.encodePacked(r2, s2, badV)
        });

        // bad v means invalid sig
        // vm.expectRevert(ECDSAInvalidSignature.selector);
        vm.expectRevert(abi.encodePacked("ECDSA: invalid signature 'v' value"));
        rs.auction.resolveMultiBidAuction(bid2, rs.bid1);

        bytes32 h1 = keccak256(
            abi.encodePacked(
                block.chainid, address(rs.auction), rs.biddingForRound, bidder1Amount / 2, elc1
            )
        );
        (, bytes32 r1, bytes32 s1) = vm.sign(bidder1PrivKey, h1);
        Bid memory bid1 = Bid({
            amount: bidder1Amount / 2,
            expressLaneController: elc1,
            signature: abi.encodePacked(r1, s1, badV)
        });

        // bad v means invalid sig
        // vm.expectRevert(ECDSAInvalidSignature.selector);
        vm.expectRevert(abi.encodePacked("ECDSA: invalid signature 'v' value"));
        rs.auction.resolveMultiBidAuction(rs.bid2, bid1);

        // bad v means invalid sig
        // vm.expectRevert(ECDSAInvalidSignature.selector);
        vm.expectRevert(abi.encodePacked("ECDSA: invalid signature 'v' value"));
        rs.auction.resolveSingleBidAuction(bid1);
    }

    // CHRIS: TODO: add text to each of the asserts in all the tests

    function testCannotResolveBeforeRoundCloses() public {
        ResolveSetup memory rs = deployDepositAndBids();
        assertEq(rs.auction.isAuctionRoundClosed(), true, "Auction round not closed");

        vm.warp(block.timestamp - 1);

        // rewind to open the auction
        assertEq(rs.auction.isAuctionRoundClosed(), false, "Auction round not open");

        vm.expectRevert(abi.encodeWithSelector(AuctionNotClosed.selector));
        rs.auction.resolveMultiBidAuction(rs.bid2, rs.bid1);

        vm.expectRevert(abi.encodeWithSelector(AuctionNotClosed.selector));
        rs.auction.resolveSingleBidAuction(rs.bid2);

        // go forward again to close again
        vm.warp(block.timestamp + 1);
        assertEq(rs.auction.isAuctionRoundClosed(), true, "Auction round not closed");
        rs.auction.resolveMultiBidAuction(rs.bid2, rs.bid1);
    }

    function testResolveMultiBidAuction() public {
        ResolveSetup memory rs = deployDepositAndBids();
        uint64 biddingForRound = rs.auction.currentRound() + 1;
        (,uint64 roundDurationSeconds,uint64 auctionClosingSeconds,) = rs.auction.roundTimingInfo();
        uint256 auctionBalanceBefore = rs.erc20.balanceOf(address(rs.auction));

        vm.expectEmit(true, true, true, true);
        emit SetExpressLaneController(
            biddingForRound,
            address(0),
            elc2,
            uint64(block.timestamp + auctionClosingSeconds),
            uint64(block.timestamp + auctionClosingSeconds + roundDurationSeconds - 1)
        );
        vm.expectEmit(true, true, true, true);
        emit AuctionResolved(
            true,
            biddingForRound,
            bidder2,
            elc2,
            bidder2Amount / 2,
            bidder1Amount / 2,
            uint64(block.timestamp + auctionClosingSeconds),
            uint64(block.timestamp + auctionClosingSeconds + roundDurationSeconds - 1)
        );
        rs.auction.resolveMultiBidAuction(rs.bid2, rs.bid1);

        // firstPriceBidder (bidder2) pays the price of the second price bidder (bidder1)
        // CHRIS: TODO: test that the express lane controllers were set correctly
        // CHRIS: TODO: check that the latest round was set correctly
        assertEq(rs.auction.balanceOf(bidder2), bidder2Amount - bidder1Amount / 2);
        assertEq(rs.auction.balanceOf(bidder1), bidder1Amount);
        assertEq(rs.erc20.balanceOf(beneficiary), bidder1Amount / 2);
        assertEq(rs.erc20.balanceOf(address(rs.auction)), auctionBalanceBefore - bidder1Amount / 2);

        // cannot resolve same bid
        vm.expectRevert(abi.encodeWithSelector(RoundAlreadyResolved.selector, biddingForRound));
        rs.auction.resolveMultiBidAuction(rs.bid2, rs.bid1);

        // cannot resolve other bids for the same round
        Bid memory bida3 = Bid({
            amount: bidder3Amount / 4,
            expressLaneController: elc3,
            signature: sign(
                bidder3PrivKey,
                rs.auction.getBidBytes(biddingForRound, bidder3Amount / 4, elc3).toEthSignedMessageHash()
            )
        });
        Bid memory bida4 = Bid({
            amount: bidder4Amount / 4,
            expressLaneController: elc4,
            signature: sign(
                bidder4PrivKey,
                rs.auction.getBidBytes(biddingForRound, bidder4Amount / 4, elc4).toEthSignedMessageHash()
            )
        });

        vm.expectRevert(abi.encodeWithSelector(RoundAlreadyResolved.selector, biddingForRound));
        rs.auction.resolveMultiBidAuction(bida4, bida3);

        vm.warp(block.timestamp + roundDurationSeconds);

        // since we're now on the next round the bid hash will be incorrect
        // and the signature will return an unexpected address, which will have no balance
        // CHRIS: TODO: it might be nice to give a better error message here - to do that they would need to provide the message hash, or the whole message contents, that's just the round tbh which might be nice
        vm.expectRevert(abi.encodeWithSelector(InsufficientBalanceAcc.selector, rs.auction.getBidBytes(rs.auction.currentRound() + 1, bidder4Amount / 4, elc4).toEthSignedMessageHash().recover(bida4.signature), bidder4Amount / 4, 0));
        rs.auction.resolveMultiBidAuction(bida4, bida3);

        // successful resolution with correct round
        biddingForRound = rs.auction.currentRound() + 1;
        bida3 = Bid({
            amount: bidder3Amount / 4,
            expressLaneController: elc3,
            signature: sign(
                bidder3PrivKey,
                rs.auction.getBidBytes(biddingForRound, bidder3Amount / 4, elc3).toEthSignedMessageHash()
            )
        });
        bida4 = Bid({
            amount: bidder4Amount / 4,
            expressLaneController: elc4,
            signature: sign(
                bidder4PrivKey,
                rs.auction.getBidBytes(biddingForRound, bidder4Amount / 4, elc4).toEthSignedMessageHash()
            )
        });

        auctionBalanceBefore = rs.erc20.balanceOf(address(rs.auction));
        uint256 beneficiaryBalanceBefore = rs.erc20.balanceOf(beneficiary);
        uint64 roundEnd =
            uint64(block.timestamp + auctionClosingSeconds + roundDurationSeconds - 1);

        vm.expectEmit(true, true, true, true);
        emit SetExpressLaneController(
            biddingForRound,
            address(0),
            elc4,
            uint64(block.timestamp + auctionClosingSeconds),
            roundEnd
        );
        vm.expectEmit(true, true, true, true);
        emit AuctionResolved(
            true,
            biddingForRound,
            bidder4,
            elc4,
            bidder4Amount / 4,
            bidder3Amount / 4,
            uint64(block.timestamp + auctionClosingSeconds),
            roundEnd
        );
        rs.auction.resolveMultiBidAuction(bida4, bida3);

        // CHRIS: TODO: test that the express controllers were set correctly
        assertEq(rs.auction.balanceOf(bidder4), bidder4Amount - bidder3Amount / 4, "bidder4 balance");
        assertEq(rs.auction.balanceOf(bidder3), bidder3Amount, "bidder3 balance");
        assertEq(
            rs.erc20.balanceOf(beneficiary) - beneficiaryBalanceBefore,
            bidder3Amount / 4,
            "beneficiary balance"
        );
        assertEq(
            rs.erc20.balanceOf(address(rs.auction)),
            auctionBalanceBefore - bidder3Amount / 4,
            "auction balance"
        );

        vm.stopPrank();
    }

    // CHRIS: TODO: if we decide to have partial withdrawals then we need tests for partial withdrawal amounts

    function testResolveMultiBidAuctionWithdrawalInitiated() public {
        ResolveSetup memory rs = deployDepositAndBids();
        vm.stopPrank();

        // go back and initiate a withdrawal
        vm.warp(block.timestamp - 1);

        vm.prank(bidder1);
        rs.auction.initiateWithdrawal();

        vm.prank(bidder2);
        rs.auction.initiateWithdrawal();

        vm.warp(block.timestamp + 1);

        vm.prank(auctioneer);
        rs.auction.resolveMultiBidAuction(rs.bid2, rs.bid1);
    }

    function testResolveMultiBidAuctionWithdrawalInitiatedRoundPlusOne() public {
        ResolveSetup memory rs = deployDepositAndBids();
        vm.stopPrank();

        // go back and initiate a withdrawal
        (, uint64 roundDurationSeconds,,) = rs.auction.roundTimingInfo();
        vm.warp(block.timestamp - 1 - roundDurationSeconds);

        vm.prank(bidder1);
        rs.auction.initiateWithdrawal();

        vm.prank(bidder2);
        rs.auction.initiateWithdrawal();

        vm.warp(block.timestamp + 1 + roundDurationSeconds);

        vm.prank(auctioneer);
        rs.auction.resolveMultiBidAuction(rs.bid2, rs.bid1);
    }

    function testResolveMultiBidAuctionWithdrawalInitiatedRoundPlusTwoSecondPrice() public {
        ResolveSetup memory rs = deployDepositAndBids();
        vm.stopPrank();

        // go back and initiate a withdrawal
        (, uint64 roundDurationSeconds,,) = rs.auction.roundTimingInfo();
        vm.warp(block.timestamp - 1 - roundDurationSeconds * 2);

        vm.prank(bidder1);
        rs.auction.initiateWithdrawal();

        vm.warp(block.timestamp + 1 + roundDurationSeconds * 2);

        vm.prank(auctioneer);
        vm.expectRevert(abi.encodeWithSelector(InsufficientBalanceAcc.selector, bidder1, rs.bid1.amount, 0));
        rs.auction.resolveMultiBidAuction(rs.bid2, rs.bid1);
    }

    function testResolveMultiBidAuctionWithdrawalInitiatedRoundPlusTwoFirstPrice() public {
        ResolveSetup memory rs = deployDepositAndBids();
        vm.stopPrank();

        // go back and initiate a withdrawal
        (, uint64 roundDurationSeconds,,) = rs.auction.roundTimingInfo();
        vm.warp(block.timestamp - 1 - roundDurationSeconds * 2);

        vm.prank(bidder2);
        rs.auction.initiateWithdrawal();

        vm.warp(block.timestamp + 1 + roundDurationSeconds * 2);

        vm.prank(auctioneer);
        // CHRIS: TODO: we really should have the address in this error
        vm.expectRevert(abi.encodeWithSelector(InsufficientBalanceAcc.selector, bidder2, rs.bid2.amount, 0));
        rs.auction.resolveMultiBidAuction(rs.bid2, rs.bid1);
    }

    function testResolveSingleBidAuction() public {
        (ResolveSetup memory rs) = deployDepositAndBids();
        uint64 biddingForRound = rs.auction.currentRound() + 1;
        (, uint64 roundDurationSeconds,uint64 auctionClosingSeconds ,) = rs.auction.roundTimingInfo();

        uint256 auctionBalanceBefore = rs.erc20.balanceOf(address(rs.auction));

        vm.expectEmit(true, true, true, true);
        emit SetExpressLaneController(
            biddingForRound,
            address(0),
            elc2,
            uint64(block.timestamp + auctionClosingSeconds),
            uint64(block.timestamp + auctionClosingSeconds + roundDurationSeconds - 1)
        );
        vm.expectEmit(true, true, true, true);
        emit AuctionResolved(
            false,
            biddingForRound,
            bidder2,
            elc2,
            bidder2Amount / 2,
            minReservePrice,
            uint64(block.timestamp + auctionClosingSeconds),
            uint64(block.timestamp + auctionClosingSeconds + roundDurationSeconds - 1)
        );
        rs.auction.resolveSingleBidAuction(rs.bid2);

        // firstPriceBidder (bidder2) pays the reserve price
        // CHRIS: TODO: test that the express lane controllers were set correctly
        // CHRIS: TODO: check that the latest round was set correctly
        assertEq(rs.auction.balanceOf(bidder2), bidder2Amount - minReservePrice);
        assertEq(rs.auction.balanceOf(bidder1), bidder1Amount);
        assertEq(rs.erc20.balanceOf(beneficiary), minReservePrice);
        assertEq(rs.erc20.balanceOf(address(rs.auction)), auctionBalanceBefore - minReservePrice);
    }

    function testCanSetReservePrice() public {
        ResolveSetup memory rs = deployDepositAndBids();
        // start of the test round
        (uint64 offsetTimestamp, uint64 roundDurationSeconds,uint64 auctionClosingSeconds,uint64 reserveSubmissionSeconds) = rs.auction.roundTimingInfo();
        vm.warp(offsetTimestamp + roundDurationSeconds * testRound);
        vm.stopPrank();

        assertEq(rs.auction.reservePrice(), minReservePrice, "before reserve price");

        // missing the correct role
        bytes memory revertString = abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(uint160(address(this)), 20),
            " is missing role ",
            Strings.toHexString(uint256(rs.auction.RESERVE_SETTER_ROLE()), 32)
        );
        vm.expectRevert(revertString);
        rs.auction.setReservePrice(minReservePrice + 1);

        // too low
        vm.prank(reservePriceSetter);
        vm.expectRevert(
            abi.encodeWithSelector(
                ReservePriceTooLow.selector, minReservePrice - 1, minReservePrice
            )
        );
        rs.auction.setReservePrice(minReservePrice - 1);

        // before blackout
        vm.prank(reservePriceSetter);
        vm.expectEmit(true, true, true, true);
        emit SetReservePrice(minReservePrice, minReservePrice);
        rs.auction.setReservePrice(minReservePrice);
        assertEq(rs.auction.reservePrice(), minReservePrice);
        vm.prank(reservePriceSetter);
        vm.expectEmit(true, true, true, true);
        emit SetReservePrice(minReservePrice, minReservePrice + 1);
        rs.auction.setReservePrice(minReservePrice + 1);
        assertEq(rs.auction.reservePrice(), minReservePrice + 1);

        // during blackout
        vm.warp(offsetTimestamp + roundDurationSeconds * (testRound + 1) - auctionClosingSeconds - reserveSubmissionSeconds);

        vm.prank(reservePriceSetter);
        vm.expectRevert(abi.encodeWithSelector(ReserveBlackout.selector));
        rs.auction.setReservePrice(minReservePrice);

        vm.warp(offsetTimestamp + roundDurationSeconds * (testRound + 1) - auctionClosingSeconds);

        vm.prank(reservePriceSetter);
        vm.expectRevert(abi.encodeWithSelector(ReserveBlackout.selector));
        rs.auction.setReservePrice(minReservePrice);

        vm.prank(auctioneer);
        rs.auction.resolveMultiBidAuction(rs.bid2, rs.bid1);

        // after blackout, but in same round
        vm.prank(reservePriceSetter);
        vm.expectEmit(true, true, true, true);
        emit SetReservePrice(minReservePrice + 1, minReservePrice + 2);
        rs.auction.setReservePrice(minReservePrice + 2);
        assertEq(rs.auction.reservePrice(), minReservePrice + 2);

        // CHRIS: TODO: include the round in the bid, it'll give a better error for debugging with
    }

    function testCanSetMinReservePrice() public {
        (, IExpressLaneAuction auction) = deploy();
        vm.prank(reservePriceSetter);
        auction.setReservePrice(minReservePrice * 2);

        bytes memory revertString = abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(uint160(address(this)), 20),
            " is missing role ",
            Strings.toHexString(uint256(auction.MIN_RESERVE_SETTER_ROLE()), 32)
        );
        vm.expectRevert(revertString);
        auction.setMinReservePrice(minReservePrice + 1);

        assertEq(auction.minReservePrice(), minReservePrice, "min reserve a");
        assertEq(auction.reservePrice(), minReservePrice * 2, "reserve a");
        // increase
        vm.prank(minReservePriceSetter);
        vm.expectEmit(true, true, true, true);
        emit SetMinReservePrice(minReservePrice, minReservePrice + 1);
        auction.setMinReservePrice(minReservePrice + 1);
        assertEq(auction.minReservePrice(), minReservePrice + 1, "min reserve b");
        assertEq(auction.reservePrice(), minReservePrice * 2, "reserve b");

        // decrease
        vm.prank(minReservePriceSetter);
        vm.expectEmit(true, true, true, true);
        emit SetMinReservePrice(minReservePrice + 1, minReservePrice - 1);
        auction.setMinReservePrice(minReservePrice - 1);
        assertEq(auction.minReservePrice(), minReservePrice - 1, "min reserve c");
        assertEq(auction.reservePrice(), minReservePrice * 2, "reserve c");

        // increase beyond reserve
        vm.prank(minReservePriceSetter);
        vm.expectEmit(true, true, true, true);
        emit SetMinReservePrice(minReservePrice - 1, minReservePrice * 2 + 1);
        vm.expectEmit(true, true, true, true);
        emit SetReservePrice(minReservePrice * 2, minReservePrice * 2 + 1);
        auction.setMinReservePrice(minReservePrice * 2 + 1);
        assertEq(auction.minReservePrice(), minReservePrice * 2 + 1, "min reserve d");
        assertEq(auction.reservePrice(), minReservePrice * 2 + 1, "reserve d");

        // and decrease below without changing back
        vm.prank(minReservePriceSetter);
        vm.expectEmit(true, true, true, true);
        emit SetMinReservePrice(minReservePrice * 2 + 1, minReservePrice * 2);
        auction.setMinReservePrice(minReservePrice * 2);
        assertEq(auction.minReservePrice(), minReservePrice * 2, "min reserve e");
        assertEq(auction.reservePrice(), minReservePrice * 2 + 1, "reserve e");

        // can set during blackout
        (, uint64 roundDurationSeconds,uint64 auctionClosingSeconds,uint64 reserveSubmissionSeconds) = auction.roundTimingInfo();
        vm.warp(block.timestamp + roundDurationSeconds - auctionClosingSeconds - reserveSubmissionSeconds);
        assertEq(auction.isReserveBlackout(), true);

        vm.prank(minReservePriceSetter);
        vm.expectEmit(true, true, true, true);
        emit SetMinReservePrice(minReservePrice * 2, minReservePrice * 2 + 2);
        vm.expectEmit(true, true, true, true);
        emit SetReservePrice(minReservePrice * 2 + 1, minReservePrice * 2 + 2);
        auction.setMinReservePrice(minReservePrice * 2 + 2);
        assertEq(auction.minReservePrice(), minReservePrice * 2 + 2, "min reserve f");
        assertEq(auction.reservePrice(), minReservePrice * 2 + 2, "reserve f");
    }

    function testTransferELC() public {
        ResolveSetup memory rs = deployDepositAndBids();
        vm.stopPrank();

        // cant transfer for previous rounds
        vm.expectRevert(abi.encodeWithSelector(RoundTooOld.selector, testRound - 1, testRound));
        rs.auction.transferExpressLaneController(testRound - 1, elc1);

        // cant transfer before something is set
        vm.expectRevert(abi.encodeWithSelector(RoundNotResolved.selector, testRound));
        rs.auction.transferExpressLaneController(testRound, elc1);
        vm.expectRevert(abi.encodeWithSelector(RoundNotResolved.selector, testRound + 1));
        rs.auction.transferExpressLaneController(testRound + 1, elc1);

        // resolve a round
        vm.prank(auctioneer);
        rs.auction.resolveMultiBidAuction(rs.bid2, rs.bid1);

        // current round still not resolved
        vm.expectRevert(abi.encodeWithSelector(RoundNotResolved.selector, testRound));
        rs.auction.transferExpressLaneController(testRound, elc1);
        vm.expectRevert(
            abi.encodeWithSelector(
                NotExpressLaneController.selector, testRound + 1, elc2, address(this)
            )
        );
        rs.auction.transferExpressLaneController(testRound + 1, elc1);

        (uint64 start, uint64 end) = rs.auction.roundTimestamps(testRound + 1);
        vm.prank(elc2);
        vm.expectEmit(true, true, true, true);
        emit SetExpressLaneController(testRound + 1, elc2, elc1, start, end);
        rs.auction.transferExpressLaneController(testRound + 1, elc1);

        (, uint64 roundDurationSeconds,,) = rs.auction.roundTimingInfo();
        vm.warp(block.timestamp + roundDurationSeconds);

        // round has moved forward
        vm.expectRevert(abi.encodeWithSelector(RoundTooOld.selector, testRound, testRound + 1));
        rs.auction.transferExpressLaneController(testRound, elc1);
        vm.expectRevert(abi.encodeWithSelector(RoundNotResolved.selector, testRound + 2));
        rs.auction.transferExpressLaneController(testRound + 2, elc1);

        // can still change the current
        vm.prank(elc1);
        vm.expectEmit(true, true, true, true);
        emit SetExpressLaneController(testRound + 1, elc1, elc2, uint64(block.timestamp), end);
        rs.auction.transferExpressLaneController(testRound + 1, elc2);

        // some new bids for the next round
        bytes32 h3 =
            rs.auction.getBidBytes(testRound + 2, bidder3Amount / 2, elc3).toEthSignedMessageHash();
        Bid memory bid3 = Bid({
            amount: bidder3Amount / 2,
            expressLaneController: elc3,
            signature: sign(bidder3PrivKey, h3)
        });
        bytes32 h4 =
            rs.auction.getBidBytes(testRound + 2, bidder4Amount / 2, elc4).toEthSignedMessageHash();
        Bid memory bid4 = Bid({
            amount: bidder4Amount / 2,
            expressLaneController: elc4,
            signature: sign(bidder4PrivKey, h4)
        });

        vm.prank(auctioneer);
        rs.auction.resolveMultiBidAuction(bid4, bid3);

        // change current
        vm.prank(elc2);
        vm.expectEmit(true, true, true, true);
        emit SetExpressLaneController(testRound + 1, elc2, elc1, uint64(block.timestamp), end);
        rs.auction.transferExpressLaneController(testRound + 1, elc1);

        // cant change next from wrong sender
        vm.expectRevert(
            abi.encodeWithSelector(
                NotExpressLaneController.selector, testRound + 2, elc4, address(this)
            )
        );
        rs.auction.transferExpressLaneController(testRound + 2, elc3);

        // change next now
        start = start + roundDuration;
        end = end + roundDuration;
        vm.prank(elc4);
        vm.expectEmit(true, true, true, true);
        emit SetExpressLaneController(testRound + 2, elc4, elc3, start, end);
        rs.auction.transferExpressLaneController(testRound + 2, elc3);
    }

    function testSetBeneficiary() public {
        (, IExpressLaneAuction auction) = deploy();

        address newBeneficiary = vm.addr(9090);
        
        bytes memory revertString = abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(uint160(address(this)), 20),
            " is missing role ",
            Strings.toHexString(uint256(auction.BENEFICIARY_SETTER_ROLE()), 32)
        );
        vm.expectRevert(revertString);
        auction.setBeneficiary(newBeneficiary);

        vm.prank(beneficiarySetter);
        vm.expectEmit(true, true, true, true);
        emit SetBeneficiary(beneficiary, newBeneficiary);
        auction.setBeneficiary(newBeneficiary);
        assertEq(auction.beneficiary(), newBeneficiary, "new beneficiary");
    }
}
