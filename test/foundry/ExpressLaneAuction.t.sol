// SPDX-License-Identifier: UNLICENSED
// CHRIS: TODO: choose sol version
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "../../src/express-lane-auction/ExpressLaneAuction.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("LANE", "LNE") {
        _mint(msg.sender, 1000000);
    }
}

contract ExpressLaneAuctionTest is Test {
    // CHRIS: TODO: if we use a higher sol version we dont have to do this additional declaration
    event Deposit(address indexed account, uint256 amount);
    event WithdrawalInitiated(address indexed account, uint256 withdrawalAmount, uint256 roundWithdrawable);
    event WithdrawalFinalized(address indexed account, uint256 withdrawalAmount);
    event AuctionResolved(
        uint256 round,
        address indexed firstPriceBidder,
        address indexed firstPriceElectionController,
        uint256 firstPriceAmount,
        uint256 price
    );

    using ECDSA for bytes32;

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

    function deploy() internal returns (MockERC20, ExpressLaneAuction) {
        MockERC20 token = new MockERC20();
        ExpressLaneAuction auction = new ExpressLaneAuction(
            beneficiary,
            RoundTimingInfo({
                offsetTimestamp: uint64(block.timestamp) + 10,
                biddingStageLength: roundDuration * 3 / 4,
                resolvingStageLength: roundDuration / 4,
                reserveBlackoutPeriodStart: roundDuration / 2
            }),
            address(token),
            auctioneer,
            roleAdmin,
            minReservePrice,
            minReservePriceSetter,
            reservePriceSetter
        );

        (uint64 offset,,,) = auction.roundTimingInfo();
        // move to round 13
        vm.warp(offset + auction.roundDuration() * 13);

        return (token, auction);
    }

    function deployAndDeposit() internal returns (MockERC20, ExpressLaneAuction) {
        (MockERC20 erc20, ExpressLaneAuction auction) = deploy();
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
        (MockERC20 erc20, ExpressLaneAuction auction) = deploy();

        erc20.transfer(bidder1, bidder1Amount);
        erc20.transfer(bidder2, bidder2Amount);

        // cannot deposit without approval
        vm.startPrank(bidder1);
        // error: ERC20InsufficientAllowance(0x2e234DAe75C793f67A35089C9d99245E1C58470b, 0, 20)
        // vm.expectRevert(
        //     hex"fb8f41b20000000000000000000000002e234dae75c793f67a35089c9d99245e1c58470b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000014"
        // );
        vm.expectRevert(
            abi.encodePacked("ERC20: insufficient allowance")
        );
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
        assertEq(erc20.balanceOf(address(auction)), bidder1Amount, "Full dirst auction erc20 balance");
        vm.stopPrank();

        // can deposit different bidder, do it once per second for 2 rounds
        // to ensure that deposit can occur at any time
        vm.startPrank(bidder2);
        erc20.approve(address(auction), auction.roundDuration() * 3);
        for (uint256 i = 0; i < auction.roundDuration() * 3; i++) {
            vm.warp(block.timestamp + 1);
            vm.expectEmit(true, true, true, true);
            emit Deposit(bidder2, 1);
            auction.deposit(1);
            assertEq(auction.balanceOf(bidder2), i + 1, "Second balance");
            assertEq(erc20.balanceOf(bidder2), bidder2Amount - i - 1, "Second bidder2 erc20 balance");
            assertEq(erc20.balanceOf(address(auction)), bidder1Amount + i + 1, "Second auction erc20 balance");
        }
        vm.stopPrank();
    }

    // CHRIS: TODO: tests for round duration

    function testCurrentRound() public {
        (, ExpressLaneAuction auction) = deploy();
        vm.warp(1);
        assertEq(auction.currentRound(), 0);

        (uint64 offset,,,) = auction.roundTimingInfo();
        vm.warp(offset - 1);
        assertEq(auction.currentRound(), 0);

        for (uint256 i = 0; i < 13; i++) {
            for (uint256 j = 0; j < auction.roundDuration(); j++) {
                vm.warp(block.timestamp + 1);
                assertEq(auction.currentRound(), i);
            }
        }
    }

    function testInitiateWithdrawal() public {
        (, ExpressLaneAuction auction) = deployAndDeposit();
        uint256 curRound = auction.currentRound();

        vm.startPrank(bidder1);
        vm.expectRevert(ZeroAmount.selector);
        auction.initiateWithdrawal(0);

        vm.expectRevert(abi.encodeWithSelector(InsufficientBalance.selector, bidder1Amount + 1, bidder1Amount));
        auction.initiateWithdrawal(bidder1Amount + 1);

        // 1. Withdraw once, then test it's not possible to withdraw in any future stages
        vm.expectEmit(true, true, true, true);
        emit WithdrawalInitiated(bidder1, bidder1Amount / 2, curRound + 2);
        auction.initiateWithdrawal(bidder1Amount / 2);
        assertEq(auction.currentRound(), curRound);
        assertEq(auction.balanceOf(bidder1), bidder1Amount);
        assertEq(auction.withdrawableBalance(bidder1), 0);

        // round 1.5
        vm.warp(block.timestamp + auction.roundDuration() / 2);

        assertEq(auction.currentRound(), curRound);
        assertEq(auction.balanceOf(bidder1), bidder1Amount);
        assertEq(auction.withdrawableBalance(bidder1), 0);

        vm.expectRevert(abi.encodeWithSelector(WithdrawalInProgress.selector, bidder1Amount / 2));
        auction.initiateWithdrawal(bidder1Amount / 4);

        // round 2
        vm.warp(block.timestamp + auction.roundDuration() / 2);

        assertEq(auction.currentRound(), curRound + 1);
        assertEq(auction.balanceOf(bidder1), bidder1Amount);
        assertEq(auction.withdrawableBalance(bidder1), 0);

        vm.expectRevert(abi.encodeWithSelector(WithdrawalInProgress.selector, bidder1Amount / 2));
        auction.initiateWithdrawal(bidder1Amount / 4);

        // round 2.5
        vm.warp(block.timestamp + auction.roundDuration() / 2);
        assertEq(auction.currentRound(), curRound + 1);
        assertEq(auction.balanceOf(bidder1), bidder1Amount);
        assertEq(auction.withdrawableBalance(bidder1), 0);

        // round 3
        vm.warp(block.timestamp + auction.roundDuration() / 2);
        assertEq(auction.currentRound(), curRound + 2);
        assertEq(auction.balanceOf(bidder1), bidder1Amount / 2);
        assertEq(auction.withdrawableBalance(bidder1), bidder1Amount / 2, "withdrawal 3");

        vm.expectRevert(abi.encodeWithSelector(WithdrawalInProgress.selector, bidder1Amount / 2));
        auction.initiateWithdrawal(bidder1Amount / 4);

        // round 3.5
        vm.warp(block.timestamp + auction.roundDuration() / 2);
        assertEq(auction.currentRound(), curRound + 2);
        assertEq(auction.balanceOf(bidder1), bidder1Amount / 2);
        assertEq(auction.withdrawableBalance(bidder1), bidder1Amount / 2);

        // round 4
        vm.warp(block.timestamp + auction.roundDuration() / 2);
        assertEq(auction.currentRound(), curRound + 3);
        assertEq(auction.balanceOf(bidder1), bidder1Amount / 2);
        assertEq(auction.withdrawableBalance(bidder1), bidder1Amount / 2);

        vm.expectRevert(abi.encodeWithSelector(WithdrawalInProgress.selector, bidder1Amount / 2));
        auction.initiateWithdrawal(bidder1Amount / 4);

        // finalize and initiate a new withdrawal
        auction.finalizeWithdrawal();
        // round 4.5
        vm.warp(block.timestamp + auction.roundDuration() / 2);
        assertEq(auction.currentRound(), curRound + 3);
        assertEq(auction.balanceOf(bidder1), bidder1Amount / 2);
        assertEq(auction.withdrawableBalance(bidder1), 0);

        auction.initiateWithdrawal(bidder1Amount / 10);
        assertEq(auction.currentRound(), curRound + 3);
        assertEq(auction.balanceOf(bidder1), bidder1Amount / 2);
        assertEq(auction.withdrawableBalance(bidder1), 0);

        // round 5
        vm.warp(block.timestamp + auction.roundDuration() / 2);
        assertEq(auction.currentRound(), curRound + 4);
        assertEq(auction.balanceOf(bidder1), bidder1Amount / 2);
        assertEq(auction.withdrawableBalance(bidder1), 0);

        // round 6
        vm.warp(block.timestamp + auction.roundDuration());
        assertEq(auction.currentRound(), curRound + 5);
        assertEq(auction.balanceOf(bidder1), bidder1Amount / 2 - bidder1Amount / 10);
        assertEq(auction.withdrawableBalance(bidder1), bidder1Amount / 10);
        auction.finalizeWithdrawal();
        assertEq(auction.currentRound(), curRound + 5);
        assertEq(auction.balanceOf(bidder1), bidder1Amount / 2 - bidder1Amount / 10);
        assertEq(auction.withdrawableBalance(bidder1), 0);

        // round 7
        vm.warp(block.timestamp + auction.roundDuration());
        auction.initiateWithdrawal(bidder1Amount / 2 - bidder1Amount / 10);
        // round 9
        vm.warp(block.timestamp + auction.roundDuration() * 2);
        auction.finalizeWithdrawal();
        assertEq(auction.currentRound(), curRound + 8);
        assertEq(auction.balanceOf(bidder1), 0);
        assertEq(auction.withdrawableBalance(bidder1), 0);

        vm.stopPrank();

        // CHRIS: TODO: remainig tests initiate withdrawal tests
        // * above guarantees are not effected by round time updates
        // * cant initiate withdrawal when offset is in the future (leave this one, since we might allow it, erm, no point lol, could set it to max, and then allow withdrawal, best to revert for now)
    }

    function testFinalizeWithdrawal() public {
        (MockERC20 erc20, ExpressLaneAuction auction) = deployAndDeposit();
        uint256 curRound = auction.currentRound();

        assertEq(auction.currentRound(), curRound);
        assertEq(auction.balanceOf(bidder1), bidder1Amount);
        assertEq(auction.withdrawableBalance(bidder1), 0);

        // finalize withdrawal tests
        vm.startPrank(bidder1);
        vm.expectRevert(abi.encodeWithSelector(NothingToWithdraw.selector));
        auction.finalizeWithdrawal();

        auction.initiateWithdrawal(bidder1Amount / 4);

        assertEq(auction.currentRound(), curRound);
        assertEq(auction.balanceOf(bidder1), bidder1Amount);
        assertEq(auction.withdrawableBalance(bidder1), 0);

        // expect revert
        vm.expectRevert(abi.encodeWithSelector(NothingToWithdraw.selector));
        auction.finalizeWithdrawal();

        vm.warp(block.timestamp + auction.roundDuration());

        assertEq(auction.currentRound(), curRound + 1);
        assertEq(auction.balanceOf(bidder1), bidder1Amount);
        assertEq(auction.withdrawableBalance(bidder1), 0);

        // expect revert
        vm.expectRevert(abi.encodeWithSelector(NothingToWithdraw.selector));
        auction.finalizeWithdrawal();

        vm.warp(block.timestamp + auction.roundDuration());

        assertEq(auction.currentRound(), curRound + 2);
        assertEq(auction.balanceOf(bidder1), bidder1Amount * 3 / 4);
        assertEq(auction.withdrawableBalance(bidder1), bidder1Amount / 4);

        // expect emit
        uint256 bidderErc20BalBefore = erc20.balanceOf(bidder1);
        uint256 auctionErc20BalBefore = erc20.balanceOf(address(auction));
        vm.expectEmit(true, true, true, true);
        emit WithdrawalFinalized(bidder1, bidder1Amount / 4);
        auction.finalizeWithdrawal();

        assertEq(auction.currentRound(), curRound + 2);
        assertEq(auction.balanceOf(bidder1), bidder1Amount * 3 / 4);
        assertEq(auction.withdrawableBalance(bidder1), 0);
        uint256 bidderErc20BalAfter = erc20.balanceOf(bidder1);
        uint256 auctionErc20BalAfter = erc20.balanceOf(address(auction));
        assertEq(bidderErc20BalAfter, bidderErc20BalBefore + bidder1Amount / 4);
        assertEq(auctionErc20BalAfter, auctionErc20BalBefore - bidder1Amount / 4);

        // expect revert
        vm.expectRevert(abi.encodeWithSelector(NothingToWithdraw.selector));
        auction.finalizeWithdrawal();

        vm.stopPrank();

        // CHRIS: TODO:
        // * reducing the round time does have an effect - add this later
        // * cannot finalize too soon - comments about how this will work during an upgrade/change of time
    }

    function testFinalizeLateWithdrawal() public {
        (MockERC20 erc20, ExpressLaneAuction auction) = deployAndDeposit();
        uint256 curRound = auction.currentRound();

        assertEq(auction.currentRound(), curRound);
        assertEq(auction.balanceOf(bidder1), bidder1Amount);
        assertEq(auction.withdrawableBalance(bidder1), 0);

        // finalize withdrawal tests
        vm.startPrank(bidder1);

        auction.initiateWithdrawal(bidder1Amount / 4);

        vm.warp(block.timestamp + auction.roundDuration() * 5);

        assertEq(auction.currentRound(), curRound + 5);
        assertEq(auction.balanceOf(bidder1), bidder1Amount * 3 / 4);
        assertEq(auction.withdrawableBalance(bidder1), bidder1Amount / 4);

        // expect emit
        uint256 bidderErc20BalBefore = erc20.balanceOf(bidder1);
        uint256 auctionErc20BalBefore = erc20.balanceOf(address(auction));
        vm.expectEmit(true, true, true, true);
        emit WithdrawalFinalized(bidder1, bidder1Amount / 4);
        auction.finalizeWithdrawal();

        assertEq(auction.currentRound(), curRound + 5);
        assertEq(auction.balanceOf(bidder1), bidder1Amount * 3 / 4);
        assertEq(auction.withdrawableBalance(bidder1), 0);
        uint256 bidderErc20BalAfter = erc20.balanceOf(bidder1);
        uint256 auctionErc20BalAfter = erc20.balanceOf(address(auction));
        assertEq(bidderErc20BalAfter, bidderErc20BalBefore + bidder1Amount / 4);
        assertEq(auctionErc20BalAfter, auctionErc20BalBefore - bidder1Amount / 4);

        vm.stopPrank();
    }

    function sign(uint256 privKey, bytes32 h) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, h);
        return abi.encodePacked(r, s, v);
    }

    struct ResolveSetup {
        MockERC20 erc20;
        ExpressLaneAuction auction;
        Bid bid1;
        Bid bid2;
        bytes32 h1;
        bytes32 h2;
        uint64 biddingRound;
    }

    function deployDepositAndBids() public returns (ResolveSetup memory) {
        (MockERC20 erc20, ExpressLaneAuction auction) = deployAndDeposit();
        uint64 biddingRound = auction.currentRound() + 1;

        bytes32 h1 = auction.getBidHash(biddingRound, bidder1Amount / 2, elc1).toEthSignedMessageHash();
        Bid memory bid1 =
            Bid({amount: bidder1Amount / 2, expressLaneController: elc1, signature: sign(bidder1PrivKey, h1)});
        bytes32 h2 = auction.getBidHash(biddingRound, bidder2Amount / 2, elc2).toEthSignedMessageHash();
        Bid memory bid2 =
            Bid({amount: bidder2Amount / 2, expressLaneController: elc2, signature: sign(bidder2PrivKey, h2)});

        vm.warp(block.timestamp + auction.roundDuration() - auction.resolvingStageLength());

        vm.startPrank(auctioneer);

        return ResolveSetup({
            erc20: erc20,
            auction: auction,
            bid1: bid1,
            bid2: bid2,
            h1: h1,
            h2: h2,
            biddingRound: biddingRound
        });
    }

    function testCannotResolveNotAuctioneer() public {
        ResolveSetup memory rs = deployDepositAndBids();
        vm.stopPrank();

        bytes memory revertString = 
                abi.encodePacked(
                    "AccessControl: account ",
                    Strings.toHexString(uint160(bidder4), 20),
                    " is missing role ",
                    Strings.toHexString(uint256(rs.auction.AUCTIONEER_ROLE()), 32)
                );


        vm.startPrank(bidder4);
        vm.expectRevert(
            revertString
        );
        rs.auction.resolveMultiBidAuction(rs.bid2, rs.bid1);
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

    function testCannotResolveInsufficientFunds() public {
        ResolveSetup memory rs = deployDepositAndBids();

        bytes32 h2 = rs.auction.getBidHash(rs.biddingRound, bidder2Amount * 2, elc2).toEthSignedMessageHash();
        Bid memory bid2 =
            Bid({amount: bidder2Amount * 2, expressLaneController: elc2, signature: sign(bidder2PrivKey, h2)});

        vm.expectRevert(abi.encodeWithSelector(InsufficientBalance.selector, bidder2Amount * 2, bidder2Amount));
        rs.auction.resolveMultiBidAuction(bid2, rs.bid1);
    }

    function testCannotResolveWrongChain() public {
        ResolveSetup memory rs = deployDepositAndBids();

        bytes32 h2 = keccak256(
            abi.encodePacked(block.chainid * 137, address(rs.auction), rs.biddingRound, bidder2Amount / 2, elc2)
        );
        Bid memory bid2 =
            Bid({amount: bidder2Amount / 2, expressLaneController: elc2, signature: sign(bidder2PrivKey, h2)});

        // wrong chain means wrong hash means wrong address
        vm.expectRevert(abi.encodeWithSelector(InsufficientBalance.selector, bidder2Amount / 2, 0));
        rs.auction.resolveMultiBidAuction(bid2, rs.bid1);

        bytes32 h1 = keccak256(
            abi.encodePacked(block.chainid * 137, address(rs.auction), rs.biddingRound, bidder1Amount / 2, elc1)
        );
        Bid memory bid1 =
            Bid({amount: bidder1Amount / 2, expressLaneController: elc1, signature: sign(bidder1PrivKey, h1)});

        // wrong chain means wrong hash means wrong address
        vm.expectRevert(abi.encodeWithSelector(InsufficientBalance.selector, bidder1Amount / 2, 0));
        rs.auction.resolveMultiBidAuction(rs.bid2, bid1);
    }

    function testCannotResolveWrongContract() public {
        ResolveSetup memory rs = deployDepositAndBids();

        bytes32 h2 = keccak256(abi.encodePacked(block.chainid, bidder4, rs.biddingRound, bidder2Amount / 2, elc2));
        Bid memory bid2 =
            Bid({amount: bidder2Amount / 2, expressLaneController: elc2, signature: sign(bidder2PrivKey, h2)});

        // wrong chain means wrong hash means wrong address
        vm.expectRevert(abi.encodeWithSelector(InsufficientBalance.selector, bidder2Amount / 2, 0));
        rs.auction.resolveMultiBidAuction(bid2, rs.bid1);

        bytes32 h1 = keccak256(abi.encodePacked(block.chainid, bidder4, rs.biddingRound, bidder1Amount / 2, elc1));
        Bid memory bid1 =
            Bid({amount: bidder1Amount / 2, expressLaneController: elc1, signature: sign(bidder1PrivKey, h1)});

        // wrong chain means wrong hash means wrong address
        vm.expectRevert(abi.encodeWithSelector(InsufficientBalance.selector, bidder1Amount / 2, 0));
        rs.auction.resolveMultiBidAuction(rs.bid2, bid1);
    }

    error ECDSAInvalidSignature();

    function testCannotResolveWrongSig() public {
        ResolveSetup memory rs = deployDepositAndBids();

        bytes32 h2 =
            keccak256(abi.encodePacked(block.chainid, address(rs.auction), rs.biddingRound, bidder2Amount / 2, elc2));
        (, bytes32 r2, bytes32 s2) = vm.sign(bidder2PrivKey, h2);
        uint8 badV = 17;
        Bid memory bid2 =
            Bid({amount: bidder2Amount / 2, expressLaneController: elc2, signature: abi.encodePacked(r2, s2, badV)});

        // bad v means invalid sig
        // vm.expectRevert(ECDSAInvalidSignature.selector);
        vm.expectRevert(abi.encodePacked("ECDSA: invalid signature 'v' value"));
        rs.auction.resolveMultiBidAuction(bid2, rs.bid1);

        bytes32 h1 =
            keccak256(abi.encodePacked(block.chainid, address(rs.auction), rs.biddingRound, bidder1Amount / 2, elc1));
        (, bytes32 r1, bytes32 s1) = vm.sign(bidder1PrivKey, h1);
        Bid memory bid1 =
            Bid({amount: bidder1Amount / 2, expressLaneController: elc1, signature: abi.encodePacked(r1, s1, badV)});

        // bad v means invalid sig
        // vm.expectRevert(ECDSAInvalidSignature.selector);
        vm.expectRevert(abi.encodePacked("ECDSA: invalid signature 'v' value"));
        rs.auction.resolveMultiBidAuction(rs.bid2, bid1);
    }

    // CHRIS: TODO: add text to each of the asserts in all the tests

    function testCannotResolveOutsideClosingPeriods() public {
        ResolveSetup memory rs = deployDepositAndBids();
        assertEq(uint8(rs.auction.currentStage()), uint8(RoundStage.Resolving), "Not resolving stage");

        vm.warp(block.timestamp - 1);

        // rewind into the bidding stage
        assertEq(uint8(rs.auction.currentStage()), uint8(RoundStage.Bidding), "Not bidding stage");

        vm.expectRevert(abi.encodeWithSelector(InvalidStage.selector, RoundStage.Bidding, RoundStage.Resolving));
        rs.auction.resolveMultiBidAuction(rs.bid2, rs.bid1);

        // go forward again into the resolving stage
        vm.warp(block.timestamp + 1);
        assertEq(uint8(rs.auction.currentStage()), uint8(RoundStage.Resolving), "Not resolving stage");
        rs.auction.resolveMultiBidAuction(rs.bid2, rs.bid1);
    }

    function testresolveMultiBidAuction() public {
        (MockERC20 erc20, ExpressLaneAuction auction) = deployAndDeposit();
        uint64 biddingRound = auction.currentRound() + 1;

        bytes32 h1 = auction.getBidHash(biddingRound, bidder1Amount / 2, elc1).toEthSignedMessageHash();
        Bid memory bid1 =
            Bid({amount: bidder1Amount / 2, expressLaneController: elc1, signature: sign(bidder1PrivKey, h1)});
        bytes32 h2 = auction.getBidHash(biddingRound, bidder2Amount / 2, elc2).toEthSignedMessageHash();
        Bid memory bid2 =
            Bid({amount: bidder2Amount / 2, expressLaneController: elc2, signature: sign(bidder2PrivKey, h2)});

        vm.warp(block.timestamp + auction.roundDuration() - auction.resolvingStageLength());

        uint256 auctionBalanceBefore = erc20.balanceOf(address(auction));

        vm.startPrank(auctioneer);

        vm.expectEmit(true, true, true, true);
        emit AuctionResolved(biddingRound, bidder2, elc2, bidder2Amount / 2, bidder1Amount / 2);
        auction.resolveMultiBidAuction(bid2, bid1);

        // firstPriceBidder (bidder2) pays the price of the second price bidder (bidder1)
        // CHRIS: TODO: test that the election controllers were set correctly
        // CHRIS: TODO: check that the latest round was set correctly
        assertEq(auction.balanceOf(bidder2), bidder2Amount - bidder1Amount / 2);
        assertEq(auction.balanceOf(bidder1), bidder1Amount);
        assertEq(erc20.balanceOf(beneficiary), bidder1Amount / 2);
        assertEq(erc20.balanceOf(address(auction)), auctionBalanceBefore - bidder1Amount / 2);

        // cannot resolve same bid
        vm.expectRevert(abi.encodeWithSelector(RoundAlreadyResolved.selector, biddingRound));
        auction.resolveMultiBidAuction(bid2, bid1);

        // cannot resolve other bids for the same round
        bytes32 ha3 = auction.getBidHash(biddingRound, bidder3Amount / 4, elc3).toEthSignedMessageHash();
        Bid memory bida3 =
            Bid({amount: bidder3Amount / 4, expressLaneController: elc3, signature: sign(bidder3PrivKey, ha3)});
        bytes32 ha4 = auction.getBidHash(biddingRound, bidder4Amount / 4, elc4).toEthSignedMessageHash();
        Bid memory bida4 =
            Bid({amount: bidder4Amount / 4, expressLaneController: elc4, signature: sign(bidder4PrivKey, ha4)});

        vm.expectRevert(abi.encodeWithSelector(RoundAlreadyResolved.selector, biddingRound));
        auction.resolveMultiBidAuction(bida4, bida3);

        vm.warp(block.timestamp + auction.roundDuration());

        // since we're now on the next round the bid hash will be incorrect
        // and the signature will return an unexpected address, which will have no balance
        // CHRIS: TODO: it might be nice to give a better error message here - to do that they would need to provide the message hash, or the whole message contents, that's just the round tbh which might be nice
        vm.expectRevert(abi.encodeWithSelector(InsufficientBalance.selector, bidder4Amount / 4, 0));
        auction.resolveMultiBidAuction(bida4, bida3);

        // successful resolution with correct round
        biddingRound = auction.currentRound() + 1;
        ha3 = auction.getBidHash(biddingRound, bidder3Amount / 4, elc3).toEthSignedMessageHash();
        bida3 = Bid({amount: bidder3Amount / 4, expressLaneController: elc3, signature: sign(bidder3PrivKey, ha3)});
        ha4 = auction.getBidHash(biddingRound, bidder4Amount / 4, elc4).toEthSignedMessageHash();
        bida4 = Bid({amount: bidder4Amount / 4, expressLaneController: elc4, signature: sign(bidder4PrivKey, ha4)});

        auctionBalanceBefore = erc20.balanceOf(address(auction));
        uint256 beneficiaryBalanceBefore = erc20.balanceOf(beneficiary);

        vm.expectEmit(true, true, true, true);
        emit AuctionResolved(biddingRound, bidder4, elc4, bidder4Amount / 4, bidder3Amount / 4);
        auction.resolveMultiBidAuction(bida4, bida3);

        // CHRIS: TODO: test that the election controllers were set correctly
        assertEq(auction.balanceOf(bidder4), bidder4Amount - bidder3Amount / 4, "bidder4 balance");
        assertEq(auction.balanceOf(bidder3), bidder3Amount, "bidder3 balance");
        assertEq(erc20.balanceOf(beneficiary) - beneficiaryBalanceBefore, bidder3Amount / 4, "beneficiary balance");
        assertEq(erc20.balanceOf(address(auction)), auctionBalanceBefore - bidder3Amount / 4, "auction balance");

        vm.stopPrank();
    }

    // CHRIS: TODO: if we decide to have partial withdrawals then we need tests for partial withdrawal amounts

    function testresolveMultiBidAuctionWithdrawalInitiated() public {
        ResolveSetup memory rs = deployDepositAndBids();
        vm.stopPrank();

        // go back and initiate a withdrawal
        vm.warp(block.timestamp - 1);

        vm.prank(bidder1);
        rs.auction.initiateWithdrawal(bidder1Amount);

        vm.prank(bidder2);
        rs.auction.initiateWithdrawal(bidder2Amount);

        vm.warp(block.timestamp + 1);

        vm.prank(auctioneer);
        rs.auction.resolveMultiBidAuction(rs.bid2, rs.bid1);
    }

    function testresolveMultiBidAuctionWithdrawalInitiatedRoundPlusOne() public {
        ResolveSetup memory rs = deployDepositAndBids();
        vm.stopPrank();

        // go back and initiate a withdrawal
        vm.warp(block.timestamp - 1 - rs.auction.roundDuration());

        vm.prank(bidder1);
        rs.auction.initiateWithdrawal(bidder1Amount);

        vm.prank(bidder2);
        rs.auction.initiateWithdrawal(bidder2Amount);

        vm.warp(block.timestamp + 1 + rs.auction.roundDuration());

        vm.prank(auctioneer);
        rs.auction.resolveMultiBidAuction(rs.bid2, rs.bid1);
    }

    function testresolveMultiBidAuctionWithdrawalInitiatedRoundPlusTwoSecondPrice() public {
        ResolveSetup memory rs = deployDepositAndBids();
        vm.stopPrank();

        // go back and initiate a withdrawal
        vm.warp(block.timestamp - 1 - rs.auction.roundDuration() * 2);

        vm.prank(bidder1);
        rs.auction.initiateWithdrawal(bidder1Amount);

        vm.warp(block.timestamp + 1 + rs.auction.roundDuration() * 2);

        vm.prank(auctioneer);
        // CHRIS: TODO: we really should have the address in this error
        vm.expectRevert(abi.encodeWithSelector(InsufficientBalance.selector, rs.bid1.amount, 0));
        rs.auction.resolveMultiBidAuction(rs.bid2, rs.bid1);
    }

    function testresolveMultiBidAuctionWithdrawalInitiatedRoundPlusTwoFirstPrice() public {
        ResolveSetup memory rs = deployDepositAndBids();
        vm.stopPrank();

        // go back and initiate a withdrawal
        vm.warp(block.timestamp - 1 - rs.auction.roundDuration() * 2);

        vm.prank(bidder2);
        rs.auction.initiateWithdrawal(bidder2Amount);

        vm.warp(block.timestamp + 1 + rs.auction.roundDuration() * 2);

        vm.prank(auctioneer);
        // CHRIS: TODO: we really should have the address in this error
        vm.expectRevert(abi.encodeWithSelector(InsufficientBalance.selector, rs.bid2.amount, 0));
        rs.auction.resolveMultiBidAuction(rs.bid2, rs.bid1);
    }
}
