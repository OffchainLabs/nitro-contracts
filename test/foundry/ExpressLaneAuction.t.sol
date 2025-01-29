// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/express-lane-auction/ExpressLaneAuction.sol";
import {
    ERC20Burnable, IERC20
} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../src/express-lane-auction/Burner.sol";

contract MockERC20 is ERC20Burnable {
    constructor() ERC20("LANE", "LNE") {
        _mint(msg.sender, 1_000_000);
    }
}

contract ExpressLaneAuctionTest is Test {
    using ECDSA for bytes;
    using ECDSA for bytes32;

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
        uint64 round,
        address indexed from,
        address indexed to,
        address indexed transferor,
        uint64 startTimestamp,
        uint64 endTimestamp
    );
    event SetBeneficiary(address oldBeneficiary, address newBeneficiary);
    event SetTransferor(
        address indexed expressLaneController, address indexed transferor, uint64 fixedUntilRound
    );
    event SetRoundTimingInfo(
        uint64 currentRound,
        int64 offsetTimestamp,
        uint64 roundDurationSeconds,
        uint64 auctionClosingSeconds,
        uint64 reserveSubmissionSeconds
    );

    uint64 roundDuration = 60; // 1 min
    int64 offsetTimestamp = 3234000;

    struct TestBidder {
        uint256 privKey;
        address addr;
        address elc;
        uint256 amount;
    }

    TestBidder[4] bidders;

    function setUp() public {
        bidders[0] =
            TestBidder({privKey: 137, addr: vm.addr(137), elc: vm.addr(138), amount: roundDuration});
        bidders[1] = TestBidder({
            privKey: 139,
            addr: vm.addr(139),
            elc: vm.addr(140),
            amount: roundDuration * 3
        });
        bidders[2] = TestBidder({
            privKey: 140,
            addr: vm.addr(140),
            elc: vm.addr(141),
            amount: roundDuration * 4
        });
        bidders[3] = TestBidder({
            privKey: 142,
            addr: vm.addr(142),
            elc: vm.addr(143),
            amount: roundDuration * 5
        });
    }

    address beneficiary = vm.addr(145);
    uint256 initialTimestamp = block.timestamp;

    address auctioneer = vm.addr(146);

    address masterAdmin = vm.addr(147);
    uint256 minReservePrice = roundDuration / 10;
    address minReservePriceSetter = vm.addr(148);
    address reservePriceSetter = vm.addr(149);
    address beneficiarySetter = vm.addr(150);
    address auctioneerAdmin = vm.addr(151);
    address reservePriceSetterAdmin = vm.addr(153);
    address roundTimingSetter = vm.addr(155);

    uint64 testRound = 13;

    function deploy() internal returns (MockERC20, IExpressLaneAuction) {
        MockERC20 token = new MockERC20();
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        ExpressLaneAuction impl = new ExpressLaneAuction();

        ExpressLaneAuction auction = ExpressLaneAuction(
            address(new TransparentUpgradeableProxy(address(impl), address(proxyAdmin), ""))
        );
        InitArgs memory args = createArgs(address(token));
        auction.initialize(args);

        // move to round test round
        (, uint64 roundDurationSeconds,,) = auction.roundTimingInfo();
        vm.warp(uint64(offsetTimestamp) + roundDurationSeconds * testRound);

        return (token, IExpressLaneAuction(auction));
    }

    function createArgs(
        address token
    ) internal view returns (InitArgs memory) {
        return InitArgs({
            _auctioneer: auctioneer,
            _beneficiary: beneficiary,
            _biddingToken: token,
            _roundTimingInfo: RoundTimingInfo({
                offsetTimestamp: offsetTimestamp,
                roundDurationSeconds: roundDuration,
                auctionClosingSeconds: roundDuration / 4,
                reserveSubmissionSeconds: roundDuration / 4
            }),
            _minReservePrice: minReservePrice,
            _auctioneerAdmin: auctioneerAdmin,
            _minReservePriceSetter: minReservePriceSetter,
            _reservePriceSetter: reservePriceSetter,
            _reservePriceSetterAdmin: reservePriceSetterAdmin,
            _beneficiarySetter: beneficiarySetter,
            _roundTimingSetter: roundTimingSetter,
            _masterAdmin: masterAdmin
        });
    }

    function testRoundTimingInit(IExpressLaneAuction auction, MockERC20 token) internal {
        InitArgs memory rdArgs = createArgs(address(token));
        rdArgs._roundTimingInfo.auctionClosingSeconds = roundDuration / 2;
        rdArgs._roundTimingInfo.reserveSubmissionSeconds = roundDuration * 2 + 1;
        vm.expectRevert(abi.encodeWithSelector(RoundDurationTooShort.selector));
        auction.initialize(rdArgs);

        InitArgs memory rdArgs0 = createArgs(address(token));
        rdArgs0._roundTimingInfo.auctionClosingSeconds = 0;
        vm.expectRevert(abi.encodeWithSelector(ZeroAuctionClosingSeconds.selector));
        auction.initialize(rdArgs0);

        uint64 longDuration = 86401;
        InitArgs memory rdArgs1 = createArgs(address(token));
        rdArgs1._roundTimingInfo.roundDurationSeconds = longDuration;
        vm.expectRevert(abi.encodeWithSelector(RoundTooLong.selector, longDuration));
        auction.initialize(rdArgs1);

        InitArgs memory rdArgs2 = createArgs(address(token));
        rdArgs2._roundTimingInfo.roundDurationSeconds = 0;
        // expect div by 0 or not less than auction closing - either way revert
        vm.expectRevert();
        auction.initialize(rdArgs2);

        InitArgs memory rdArgs3 = createArgs(address(token));
        rdArgs3._roundTimingInfo.offsetTimestamp = -1;
        vm.expectRevert(abi.encodeWithSelector(NegativeOffset.selector));
        auction.initialize(rdArgs3);
    }

    function testInit() public {
        MockERC20 token = new MockERC20();
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        ExpressLaneAuction impl = new ExpressLaneAuction();
        InitArgs memory args = createArgs(address(token));

        vm.expectRevert("Function must be called through delegatecall");
        impl.initialize(args);

        ExpressLaneAuction auction = ExpressLaneAuction(
            address(new TransparentUpgradeableProxy(address(impl), address(proxyAdmin), ""))
        );

        InitArgs memory zbArgs = createArgs(address(token));
        zbArgs._biddingToken = address(0);
        vm.expectRevert(abi.encodeWithSelector(ZeroBiddingToken.selector));
        auction.initialize(zbArgs);

        testRoundTimingInit(auction, token);

        vm.expectEmit(true, true, true, true);
        emit SetBeneficiary(address(0), beneficiary);
        vm.expectEmit(true, true, true, true);
        emit SetMinReservePrice(uint256(0), minReservePrice);
        vm.expectEmit(true, true, true, true);
        emit SetReservePrice(uint256(0), minReservePrice);
        vm.expectEmit(true, true, true, true);
        emit SetRoundTimingInfo(
            0,
            args._roundTimingInfo.offsetTimestamp,
            args._roundTimingInfo.roundDurationSeconds,
            args._roundTimingInfo.auctionClosingSeconds,
            args._roundTimingInfo.reserveSubmissionSeconds
        );
        auction.initialize(args);
        (
            int64 offsetTimestampA,
            uint64 roundDurationSeconds,
            uint64 auctionClosingSeconds,
            uint64 reserveSubmissionSeconds
        ) = auction.roundTimingInfo();
        assertEq(address(auction.biddingToken()), address(token), "bidding token");
        assertEq(auction.beneficiary(), beneficiary, "beneficiary");
        assertEq(auction.minReservePrice(), minReservePrice, "min reserve price");
        assertEq(auction.reservePrice(), minReservePrice, "reserve price");
        assertEq(offsetTimestampA, offsetTimestamp);
        assertEq(auctionClosingSeconds, roundDuration / 4, "auction closing duration");
        assertEq(roundDurationSeconds, roundDuration, "auction round duration");
        assertEq(reserveSubmissionSeconds, roundDuration / 4, "reserve submission seconds");

        assertTrue(auction.hasRole(auction.DEFAULT_ADMIN_ROLE(), masterAdmin), "admin role");
        assertTrue(auction.hasRole(auction.AUCTIONEER_ROLE(), auctioneer), "auctioneer role");
        assertTrue(
            auction.hasRole(auction.AUCTIONEER_ADMIN_ROLE(), auctioneerAdmin),
            "auctioneer admin role"
        );
        assertTrue(
            auction.hasRole(auction.MIN_RESERVE_SETTER_ROLE(), minReservePriceSetter),
            "min reserve price setter role"
        );
        assertTrue(
            auction.hasRole(auction.RESERVE_SETTER_ROLE(), reservePriceSetter),
            "reserve price setter role"
        );
        assertTrue(
            auction.hasRole(auction.RESERVE_SETTER_ADMIN_ROLE(), reservePriceSetterAdmin),
            "reserve price setter admin role"
        );
        assertTrue(
            auction.hasRole(auction.BENEFICIARY_SETTER_ROLE(), beneficiarySetter),
            "beneficiary setter role"
        );
        assertTrue(
            auction.hasRole(auction.ROUND_TIMING_SETTER_ROLE(), roundTimingSetter),
            "round timing setter role"
        );
        assertEq(auction.getRoleAdmin(auction.AUCTIONEER_ROLE()), auction.AUCTIONEER_ADMIN_ROLE());
        assertEq(
            auction.getRoleAdmin(auction.MIN_RESERVE_SETTER_ROLE()), auction.DEFAULT_ADMIN_ROLE()
        );
        assertEq(
            auction.getRoleAdmin(auction.RESERVE_SETTER_ROLE()), auction.RESERVE_SETTER_ADMIN_ROLE()
        );
        assertEq(
            auction.getRoleAdmin(auction.BENEFICIARY_SETTER_ROLE()), auction.DEFAULT_ADMIN_ROLE()
        );
        assertEq(
            auction.getRoleAdmin(auction.AUCTIONEER_ADMIN_ROLE()), auction.DEFAULT_ADMIN_ROLE()
        );
        assertEq(
            auction.getRoleAdmin(auction.RESERVE_SETTER_ADMIN_ROLE()), auction.DEFAULT_ADMIN_ROLE()
        );

        vm.expectRevert("Initializable: contract is already initialized");
        auction.initialize(args);

        // cannot send funds to the contract
        (bool success,) = address(auction).call{value: 10}(hex"");
        assertFalse(success, "auction value call");
        assertEq(address(auction).balance, 0, "bal after");
    }

    function deployAndDeposit() internal returns (MockERC20, IExpressLaneAuction) {
        (MockERC20 erc20, IExpressLaneAuction auction) = deploy();
        erc20.transfer(bidders[0].addr, bidders[0].amount);
        erc20.transfer(bidders[1].addr, bidders[1].amount);
        erc20.transfer(bidders[2].addr, bidders[2].amount);
        erc20.transfer(bidders[3].addr, bidders[3].amount);

        vm.startPrank(bidders[0].addr);
        erc20.approve(address(auction), bidders[0].amount);
        auction.deposit(bidders[0].amount);
        vm.stopPrank();

        vm.startPrank(bidders[1].addr);
        erc20.approve(address(auction), bidders[1].amount);
        auction.deposit(bidders[1].amount);
        vm.stopPrank();

        vm.startPrank(bidders[2].addr);
        erc20.approve(address(auction), bidders[2].amount);
        auction.deposit(bidders[2].amount);
        vm.stopPrank();

        vm.startPrank(bidders[3].addr);
        erc20.approve(address(auction), bidders[3].amount);
        auction.deposit(bidders[3].amount);
        vm.stopPrank();

        return (erc20, auction);
    }

    function testDeposit() public {
        (MockERC20 erc20, IExpressLaneAuction auction) = deploy();

        erc20.transfer(bidders[0].addr, bidders[0].amount);
        erc20.transfer(bidders[1].addr, bidders[1].amount);

        // cannot deposit without approval
        vm.startPrank(bidders[0].addr);
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
        emit Deposit(bidders[0].addr, 20);
        auction.deposit(20);
        assertEq(auction.balanceOf(bidders[0].addr), 20, "First balance");
        assertEq(
            erc20.balanceOf(bidders[0].addr),
            bidders[0].amount - 20,
            "First bidders[0].addr erc20 balance"
        );
        assertEq(erc20.balanceOf(address(auction)), 20, "First auction erc20 balance");

        // can deposit twice
        erc20.approve(address(auction), bidders[0].amount - 20);
        vm.expectEmit(true, true, true, true);
        emit Deposit(bidders[0].addr, bidders[0].amount - 20);
        auction.deposit(bidders[0].amount - 20);
        assertEq(auction.balanceOf(bidders[0].addr), bidders[0].amount, "Full first balance");
        assertEq(erc20.balanceOf(bidders[0].addr), 0, "Full first bidders[0].addr erc20 balance");
        assertEq(
            erc20.balanceOf(address(auction)), bidders[0].amount, "Full dirst auction erc20 balance"
        );
        vm.stopPrank();

        // can deposit different bidder, do it once per second for 2 rounds
        // to ensure that deposit can occur at any time
        vm.startPrank(bidders[1].addr);
        (, uint64 roundDurationSeconds,,) = auction.roundTimingInfo();
        erc20.approve(address(auction), roundDurationSeconds * 3);
        for (uint256 i = 0; i < roundDurationSeconds * 3; i++) {
            vm.warp(block.timestamp + 1);
            vm.expectEmit(true, true, true, true);
            emit Deposit(bidders[1].addr, 1);
            auction.deposit(1);
            assertEq(auction.balanceOf(bidders[1].addr), i + 1, "Second balance");
            assertEq(
                erc20.balanceOf(bidders[1].addr),
                bidders[1].amount - i - 1,
                "Second bidders[1].addr erc20 balance"
            );
            assertEq(
                erc20.balanceOf(address(auction)),
                bidders[0].amount + i + 1,
                "Second auction erc20 balance"
            );
        }
        vm.stopPrank();
    }

    function testBalanceOf() public {
        (MockERC20 erc20, IExpressLaneAuction auction) = deploy();
        erc20.transfer(bidders[0].addr, bidders[0].amount);

        uint64 currentRound = auction.currentRound();
        vm.expectRevert(
            abi.encodeWithSelector(RoundTooOld.selector, currentRound - 1, currentRound)
        );
        auction.balanceOfAtRound(bidders[0].addr, currentRound - 1);
        vm.expectRevert(
            abi.encodeWithSelector(RoundTooOld.selector, currentRound - 1, currentRound)
        );
        auction.withdrawableBalanceAtRound(bidders[0].addr, currentRound - 1);

        vm.prank(bidders[0].addr);
        erc20.approve(address(auction), 20);

        vm.expectEmit(true, true, true, true);
        emit Deposit(bidders[0].addr, 20);
        vm.prank(bidders[0].addr);
        auction.deposit(20);
        assertEq(auction.balanceOf(bidders[0].addr), 20, "First balance");
        assertEq(
            auction.balanceOfAtRound(bidders[0].addr, currentRound), 20, "First balance at round"
        );
        assertEq(
            auction.balanceOfAtRound(bidders[0].addr, currentRound + 1),
            20,
            "First balance at round + 1"
        );
        assertEq(
            auction.balanceOfAtRound(bidders[0].addr, currentRound + 2),
            20,
            "First balance at round + 2"
        );
        assertEq(
            auction.balanceOfAtRound(bidders[0].addr, currentRound + 3),
            20,
            "First balance at round + 3"
        );
        assertEq(
            auction.withdrawableBalanceAtRound(bidders[0].addr, currentRound),
            0,
            "First withdrawable balance at round"
        );
        assertEq(
            auction.withdrawableBalanceAtRound(bidders[0].addr, currentRound + 1),
            0,
            "First withdrawable balance at round + 1"
        );
        assertEq(
            auction.withdrawableBalanceAtRound(bidders[0].addr, currentRound + 2),
            0,
            "First withdrawable balance at round + 2"
        );
        assertEq(
            auction.withdrawableBalanceAtRound(bidders[0].addr, currentRound + 3),
            0,
            "First withdrawable balance at round + 3"
        );
        assertEq(
            erc20.balanceOf(bidders[0].addr),
            bidders[0].amount - 20,
            "First bidders[0].addr erc20 balance"
        );
        assertEq(erc20.balanceOf(address(auction)), 20, "First auction erc20 balance");

        // resolve the auction
        vm.warp(block.timestamp + roundDuration - roundDuration / 4);

        bytes32 h0 = auction.getBidHash(currentRound + 1, bidders[0].elc, minReservePrice + 1);
        Bid memory bid0 = Bid({
            amount: minReservePrice + 1,
            expressLaneController: bidders[0].elc,
            signature: sign(bidders[0].privKey, h0)
        });

        vm.prank(auctioneer);
        auction.resolveSingleBidAuction(bid0);

        assertEq(
            auction.balanceOfAtRound(bidders[0].addr, currentRound),
            20 - minReservePrice,
            "Second balance at round"
        );
        assertEq(
            auction.balanceOfAtRound(bidders[0].addr, currentRound + 1),
            20 - minReservePrice,
            "Second balance at round + 1"
        );
        assertEq(
            auction.balanceOfAtRound(bidders[0].addr, currentRound + 2),
            20 - minReservePrice,
            "Second balance at round + 2"
        );
        assertEq(
            auction.balanceOfAtRound(bidders[0].addr, currentRound + 3),
            20 - minReservePrice,
            "Second balance at round + 3"
        );
        assertEq(
            auction.withdrawableBalanceAtRound(bidders[0].addr, currentRound),
            0,
            "Second withdrawable balance at round"
        );
        assertEq(
            auction.withdrawableBalanceAtRound(bidders[0].addr, currentRound + 1),
            0,
            "Second withdrawable balance at round + 1"
        );
        assertEq(
            auction.withdrawableBalanceAtRound(bidders[0].addr, currentRound + 2),
            0,
            "Second withdrawable balance at round + 2"
        );
        assertEq(
            auction.withdrawableBalanceAtRound(bidders[0].addr, currentRound + 3),
            0,
            "Second withdrawable balance at round + 3"
        );

        vm.prank(bidders[0].addr);
        auction.initiateWithdrawal();

        assertEq(
            auction.balanceOfAtRound(bidders[0].addr, currentRound),
            20 - minReservePrice,
            "Third balance at round"
        );
        assertEq(
            auction.balanceOfAtRound(bidders[0].addr, currentRound + 1),
            20 - minReservePrice,
            "Third balance at round + 1"
        );
        assertEq(
            auction.balanceOfAtRound(bidders[0].addr, currentRound + 2),
            0,
            "Third balance at round + 2"
        );
        assertEq(
            auction.balanceOfAtRound(bidders[0].addr, currentRound + 3),
            0,
            "Third balance at round + 3"
        );
        assertEq(
            auction.withdrawableBalanceAtRound(bidders[0].addr, currentRound),
            0,
            "Third withdrawable balance at round"
        );
        assertEq(
            auction.withdrawableBalanceAtRound(bidders[0].addr, currentRound + 1),
            0,
            "Third withdrawable balance at round + 1"
        );
        assertEq(
            auction.withdrawableBalanceAtRound(bidders[0].addr, currentRound + 2),
            20 - minReservePrice,
            "Third withdrawable balance at round + 2"
        );
        assertEq(
            auction.withdrawableBalanceAtRound(bidders[0].addr, currentRound + 3),
            20 - minReservePrice,
            "Third withdrawable balance at round + 3"
        );

        vm.warp(block.timestamp + roundDuration);

        assertEq(
            auction.balanceOfAtRound(bidders[0].addr, currentRound + 1),
            20 - minReservePrice,
            "Fourth balance at round + 1"
        );
        assertEq(
            auction.balanceOfAtRound(bidders[0].addr, currentRound + 2),
            0,
            "Fourth balance at round + 2"
        );
        assertEq(
            auction.balanceOfAtRound(bidders[0].addr, currentRound + 3),
            0,
            "Fourth balance at round + 3"
        );
        assertEq(
            auction.withdrawableBalanceAtRound(bidders[0].addr, currentRound + 1),
            0,
            "Fourth withdrawable balance at round + 1"
        );
        assertEq(
            auction.withdrawableBalanceAtRound(bidders[0].addr, currentRound + 2),
            20 - minReservePrice,
            "Fourth withdrawable balance at round + 2"
        );
        assertEq(
            auction.withdrawableBalanceAtRound(bidders[0].addr, currentRound + 3),
            20 - minReservePrice,
            "Fourth withdrawable balance at round + 3"
        );

        vm.warp(block.timestamp + roundDuration);

        assertEq(
            auction.balanceOfAtRound(bidders[0].addr, currentRound + 2),
            0,
            "Fifth balance at round + 2"
        );
        assertEq(
            auction.balanceOfAtRound(bidders[0].addr, currentRound + 3),
            0,
            "Fifth balance at round + 3"
        );
        assertEq(
            auction.withdrawableBalanceAtRound(bidders[0].addr, currentRound + 2),
            20 - minReservePrice,
            "Fifth withdrawable balance at round + 2"
        );
        assertEq(
            auction.withdrawableBalanceAtRound(bidders[0].addr, currentRound + 3),
            20 - minReservePrice,
            "Fifth withdrawable balance at round + 3"
        );

        vm.prank(bidders[0].addr);
        auction.finalizeWithdrawal();

        assertEq(
            auction.balanceOfAtRound(bidders[0].addr, currentRound + 2),
            0,
            "Sixth balance at round + 2"
        );
        assertEq(
            auction.balanceOfAtRound(bidders[0].addr, currentRound + 3),
            0,
            "Sixth balance at round + 3"
        );
        assertEq(
            auction.withdrawableBalanceAtRound(bidders[0].addr, currentRound + 2),
            0,
            "Sixth withdrawable balance at round + 2"
        );
        assertEq(
            auction.withdrawableBalanceAtRound(bidders[0].addr, currentRound + 3),
            0,
            "Sixth withdrawable balance at round + 3"
        );
    }

    function testCurrentRound() public {
        (, IExpressLaneAuction auction) = deploy();
        vm.warp(1);
        assertEq(auction.currentRound(), 0);

        (int64 offsetTimestampA, uint64 roundDurationSeconds,,) = auction.roundTimingInfo();

        vm.warp(uint64(offsetTimestampA) - 1);
        assertEq(auction.currentRound(), 0);

        for (uint256 i = 0; i < testRound; i++) {
            for (uint256 j = 0; j < roundDurationSeconds; j++) {
                vm.warp(block.timestamp + 1);
                assertEq(auction.currentRound(), i);
            }
        }
    }

    function testInitiateWithdrawal() public {
        (MockERC20 erc20, IExpressLaneAuction auction) = deployAndDeposit();
        uint256 curRound = auction.currentRound();

        vm.startPrank(beneficiary);
        // dont expect the beneficiary to have anything to withdraw
        vm.expectRevert(ZeroAmount.selector);
        auction.initiateWithdrawal();
        vm.stopPrank();

        vm.startPrank(bidders[0].addr);

        // 1. Withdraw once, then test it's not possible to withdraw in any future rounds
        vm.expectEmit(true, true, true, true);
        emit WithdrawalInitiated(bidders[0].addr, bidders[0].amount, curRound + 2);
        auction.initiateWithdrawal();
        assertEq(auction.currentRound(), curRound);
        assertEq(auction.balanceOf(bidders[0].addr), bidders[0].amount);
        assertEq(auction.withdrawableBalance(bidders[0].addr), 0);

        // round 1.5
        (, uint64 roundDurationSeconds,,) = auction.roundTimingInfo();
        vm.warp(block.timestamp + roundDurationSeconds / 2);

        assertEq(auction.currentRound(), curRound);
        assertEq(auction.balanceOf(bidders[0].addr), bidders[0].amount);
        assertEq(auction.withdrawableBalance(bidders[0].addr), 0);

        vm.expectRevert(abi.encodeWithSelector(WithdrawalInProgress.selector));
        auction.initiateWithdrawal();

        // round 2
        vm.warp(block.timestamp + roundDurationSeconds / 2);

        assertEq(auction.currentRound(), curRound + 1);
        assertEq(auction.balanceOf(bidders[0].addr), bidders[0].amount);
        assertEq(auction.withdrawableBalance(bidders[0].addr), 0);

        vm.expectRevert(abi.encodeWithSelector(WithdrawalInProgress.selector));
        auction.initiateWithdrawal();

        // round 2.5
        vm.warp(block.timestamp + roundDurationSeconds / 2);
        assertEq(auction.currentRound(), curRound + 1);
        assertEq(auction.balanceOf(bidders[0].addr), bidders[0].amount);
        assertEq(auction.withdrawableBalance(bidders[0].addr), 0);

        // round 3
        vm.warp(block.timestamp + roundDurationSeconds / 2);
        assertEq(auction.currentRound(), curRound + 2);
        assertEq(auction.balanceOf(bidders[0].addr), 0);
        assertEq(auction.withdrawableBalance(bidders[0].addr), bidders[0].amount, "withdrawal 3");

        vm.expectRevert(abi.encodeWithSelector(WithdrawalInProgress.selector));
        auction.initiateWithdrawal();

        // round 3.5
        vm.warp(block.timestamp + roundDurationSeconds / 2);
        assertEq(auction.currentRound(), curRound + 2);
        assertEq(auction.balanceOf(bidders[0].addr), 0);
        assertEq(auction.withdrawableBalance(bidders[0].addr), bidders[0].amount);

        // round 4
        vm.warp(block.timestamp + roundDurationSeconds / 2);
        assertEq(auction.currentRound(), curRound + 3);
        assertEq(auction.balanceOf(bidders[0].addr), 0);
        assertEq(auction.withdrawableBalance(bidders[0].addr), bidders[0].amount);

        vm.expectRevert(abi.encodeWithSelector(WithdrawalInProgress.selector));
        auction.initiateWithdrawal();

        // finalize and initiate a new withdrawal
        auction.finalizeWithdrawal();
        // round 4.5
        vm.warp(block.timestamp + roundDurationSeconds / 2);
        assertEq(auction.currentRound(), curRound + 3);
        assertEq(auction.balanceOf(bidders[0].addr), 0);
        assertEq(auction.withdrawableBalance(bidders[0].addr), 0);

        vm.expectRevert(ZeroAmount.selector);
        auction.initiateWithdrawal();

        erc20.approve(address(auction), bidders[0].amount / 2);
        auction.deposit(bidders[0].amount / 2);
        auction.initiateWithdrawal();
        assertEq(auction.currentRound(), curRound + 3);
        assertEq(auction.balanceOf(bidders[0].addr), bidders[0].amount / 2);
        assertEq(auction.withdrawableBalance(bidders[0].addr), 0);

        // round 5
        vm.warp(block.timestamp + roundDurationSeconds / 2);
        assertEq(auction.currentRound(), curRound + 4);
        assertEq(auction.balanceOf(bidders[0].addr), bidders[0].amount / 2);
        assertEq(auction.withdrawableBalance(bidders[0].addr), 0);

        // round 6
        vm.warp(block.timestamp + roundDurationSeconds);
        assertEq(auction.currentRound(), curRound + 5);
        assertEq(auction.balanceOf(bidders[0].addr), 0);
        assertEq(auction.withdrawableBalance(bidders[0].addr), bidders[0].amount / 2);
        auction.finalizeWithdrawal();
        assertEq(auction.currentRound(), curRound + 5);
        assertEq(auction.balanceOf(bidders[0].addr), 0);
        assertEq(auction.withdrawableBalance(bidders[0].addr), 0);

        // round 7
        vm.stopPrank();
    }

    function testFinalizeWithdrawal() public {
        (MockERC20 erc20, IExpressLaneAuction auction) = deployAndDeposit();
        uint256 curRound = auction.currentRound();

        assertEq(auction.currentRound(), curRound);
        assertEq(auction.balanceOf(bidders[0].addr), bidders[0].amount);
        assertEq(auction.withdrawableBalance(bidders[0].addr), 0);

        // finalize withdrawal tests
        vm.startPrank(bidders[0].addr);
        vm.expectRevert(abi.encodeWithSelector(NothingToWithdraw.selector));
        auction.finalizeWithdrawal();

        auction.initiateWithdrawal();

        assertEq(auction.currentRound(), curRound);
        assertEq(auction.balanceOf(bidders[0].addr), bidders[0].amount);
        assertEq(auction.withdrawableBalance(bidders[0].addr), 0);

        // expect revert
        vm.expectRevert(abi.encodeWithSelector(NothingToWithdraw.selector));
        auction.finalizeWithdrawal();

        (, uint64 roundDurationSeconds,,) = auction.roundTimingInfo();
        vm.warp(block.timestamp + roundDurationSeconds);

        assertEq(auction.currentRound(), curRound + 1);
        assertEq(auction.balanceOf(bidders[0].addr), bidders[0].amount);
        assertEq(auction.withdrawableBalance(bidders[0].addr), 0);

        // expect revert
        vm.expectRevert(abi.encodeWithSelector(NothingToWithdraw.selector));
        auction.finalizeWithdrawal();

        vm.warp(block.timestamp + roundDurationSeconds);

        assertEq(auction.currentRound(), curRound + 2);
        assertEq(auction.balanceOf(bidders[0].addr), 0);
        assertEq(auction.withdrawableBalance(bidders[0].addr), bidders[0].amount);

        // expect emit
        uint256 bidderErc20BalBefore = erc20.balanceOf(bidders[0].addr);
        uint256 auctionErc20BalBefore = erc20.balanceOf(address(auction));
        vm.expectEmit(true, true, true, true);
        emit WithdrawalFinalized(bidders[0].addr, bidders[0].amount);
        auction.finalizeWithdrawal();

        assertEq(auction.currentRound(), curRound + 2, "round end");
        assertEq(auction.balanceOf(bidders[0].addr), 0, "balance end");
        assertEq(auction.withdrawableBalance(bidders[0].addr), 0, "withdrawable balance end");
        uint256 bidderErc20BalAfter = erc20.balanceOf(bidders[0].addr);
        uint256 auctionErc20BalAfter = erc20.balanceOf(address(auction));
        assertEq(bidderErc20BalAfter, bidderErc20BalBefore + bidders[0].amount, "balance after");
        assertEq(
            auctionErc20BalAfter, auctionErc20BalBefore - bidders[0].amount, "auction balance after"
        );

        // expect revert
        vm.expectRevert(abi.encodeWithSelector(NothingToWithdraw.selector));
        auction.finalizeWithdrawal();

        vm.stopPrank();
    }

    function testFinalizeLateWithdrawal() public {
        (MockERC20 erc20, IExpressLaneAuction auction) = deployAndDeposit();
        uint256 curRound = auction.currentRound();

        assertEq(auction.currentRound(), curRound);
        assertEq(auction.balanceOf(bidders[0].addr), bidders[0].amount);
        assertEq(auction.withdrawableBalance(bidders[0].addr), 0);

        // finalize withdrawal tests
        vm.startPrank(bidders[0].addr);

        auction.initiateWithdrawal();

        (, uint64 roundDurationSeconds,,) = auction.roundTimingInfo();
        vm.warp(block.timestamp + roundDurationSeconds * 5);

        assertEq(auction.currentRound(), curRound + 5);
        assertEq(auction.balanceOf(bidders[0].addr), 0);
        assertEq(auction.withdrawableBalance(bidders[0].addr), bidders[0].amount);

        // expect emit
        uint256 bidderErc20BalBefore = erc20.balanceOf(bidders[0].addr);
        uint256 auctionErc20BalBefore = erc20.balanceOf(address(auction));
        vm.expectEmit(true, true, true, true);
        emit WithdrawalFinalized(bidders[0].addr, bidders[0].amount);
        auction.finalizeWithdrawal();

        assertEq(auction.currentRound(), curRound + 5);
        assertEq(auction.balanceOf(bidders[0].addr), 0);
        assertEq(auction.withdrawableBalance(bidders[0].addr), 0);
        uint256 bidderErc20BalAfter = erc20.balanceOf(bidders[0].addr);
        uint256 auctionErc20BalAfter = erc20.balanceOf(address(auction));
        assertEq(bidderErc20BalAfter, bidderErc20BalBefore + bidders[0].amount);
        assertEq(auctionErc20BalAfter, auctionErc20BalBefore - bidders[0].amount);

        vm.stopPrank();
    }

    function sign(uint256 privKey, bytes32 h) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, h);
        return abi.encodePacked(r, s, v);
    }

    struct ResolveSetup {
        MockERC20 erc20;
        IExpressLaneAuction auction;
        Bid bid0;
        Bid bid1;
        bytes32 h0;
        bytes32 h1;
        uint64 biddingForRound;
    }

    function deployDepositAndBids() public returns (ResolveSetup memory) {
        vm.chainId(137);
        (MockERC20 erc20, IExpressLaneAuction auction) = deployAndDeposit();
        uint64 biddingForRound = auction.currentRound() + 1;

        bytes32 h0 = auction.getBidHash(biddingForRound, bidders[0].elc, bidders[0].amount / 2);
        Bid memory bid0 = Bid({
            amount: bidders[0].amount / 2,
            expressLaneController: bidders[0].elc,
            signature: sign(bidders[0].privKey, h0)
        });
        bytes32 h1 = auction.getBidHash(biddingForRound, bidders[1].elc, bidders[1].amount / 2);
        Bid memory bid1 = Bid({
            amount: bidders[1].amount / 2,
            expressLaneController: bidders[1].elc,
            signature: sign(bidders[1].privKey, h1)
        });

        (, uint64 roundDurationSeconds, uint64 auctionClosingSeconds,) = auction.roundTimingInfo();

        vm.warp(block.timestamp + roundDurationSeconds - auctionClosingSeconds);

        vm.startPrank(auctioneer);

        return ResolveSetup({
            erc20: erc20,
            auction: auction,
            bid0: bid0,
            bid1: bid1,
            h0: h0,
            h1: h1,
            biddingForRound: biddingForRound
        });
    }

    function testGetDomainSeparator() public {
        (, IExpressLaneAuction auction) = deployAndDeposit();
        assertEq(
            auction.domainSeparator(),
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256(bytes("ExpressLaneAuction")),
                    keccak256(bytes("1")),
                    block.chainid,
                    address(auction)
                )
            )
        );
    }

    function testFlushBeneficiaryBalance() public {
        ResolveSetup memory rs = deployDepositAndBids();
        vm.stopPrank();

        vm.expectRevert(ZeroAmount.selector);
        rs.auction.flushBeneficiaryBalance();

        vm.prank(auctioneer);
        rs.auction.resolveMultiBidAuction(rs.bid1, rs.bid0);

        assertFalse(rs.auction.beneficiaryBalance() == 0, "bal before");
        uint256 auctionBalanceBefore = rs.erc20.balanceOf(address(rs.auction));
        uint256 beneficiaryBalanceBefore = rs.erc20.balanceOf(rs.auction.beneficiary());

        // any random address should be able to call this
        vm.prank(vm.addr(34567890));
        rs.auction.flushBeneficiaryBalance();

        uint256 auctionBalanceAfter = rs.erc20.balanceOf(address(rs.auction));
        uint256 beneficiaryBalanceAfter = rs.erc20.balanceOf(rs.auction.beneficiary());
        assertTrue(rs.auction.beneficiaryBalance() == 0, "bal after");
        assertEq(beneficiaryBalanceAfter - beneficiaryBalanceBefore, rs.bid0.amount);
        assertEq(auctionBalanceBefore - auctionBalanceAfter, rs.bid0.amount);

        // cannot flush twice
        vm.expectRevert(ZeroAmount.selector);
        rs.auction.flushBeneficiaryBalance();
    }

    function testFlushToBurner() public {
        vm.chainId(137);
        Bid memory bid0;
        Bid memory bid1;
        ExpressLaneAuction auction;
        MockERC20 erc20 = new MockERC20();
        Burner burner = new Burner(address(erc20));
        {
            ProxyAdmin proxyAdmin = new ProxyAdmin();
            ExpressLaneAuction impl = new ExpressLaneAuction();

            auction = ExpressLaneAuction(
                address(new TransparentUpgradeableProxy(address(impl), address(proxyAdmin), ""))
            );
            InitArgs memory args = createArgs(address(erc20));
            args._beneficiary = address(burner);
            auction.initialize(args);

            erc20.transfer(bidders[0].addr, bidders[0].amount);
            erc20.transfer(bidders[1].addr, bidders[1].amount);

            vm.startPrank(bidders[0].addr);
            erc20.approve(address(auction), bidders[0].amount);
            auction.deposit(bidders[0].amount);
            vm.stopPrank();

            vm.startPrank(bidders[1].addr);
            erc20.approve(address(auction), bidders[1].amount);
            auction.deposit(bidders[1].amount);
            vm.stopPrank();

            (int64 o, uint64 roundDurationSeconds, uint64 auctionClosingSeconds,) =
                auction.roundTimingInfo();
            vm.warp(
                uint64(o) + (roundDurationSeconds * testRound) + roundDurationSeconds
                    - auctionClosingSeconds
            );
            uint64 biddingForRound = auction.currentRound() + 1;

            bytes32 h0 = auction.getBidHash(biddingForRound, bidders[0].elc, bidders[0].amount / 2);
            bid0 = Bid({
                amount: bidders[0].amount / 2,
                expressLaneController: bidders[0].elc,
                signature: sign(bidders[0].privKey, h0)
            });
            bytes32 h1 = auction.getBidHash(biddingForRound, bidders[1].elc, bidders[1].amount / 2);
            bid1 = Bid({
                amount: bidders[1].amount / 2,
                expressLaneController: bidders[1].elc,
                signature: sign(bidders[1].privKey, h1)
            });
        }

        vm.prank(auctioneer);
        auction.resolveMultiBidAuction(bid1, bid0);

        assertFalse(auction.beneficiaryBalance() == 0, "bal before");
        uint256 auctionBalanceBefore = erc20.balanceOf(address(auction));
        uint256 beneficiaryBalanceBefore = erc20.balanceOf(auction.beneficiary());
        assertEq(erc20.balanceOf(address(burner)), 0);

        // any random address should be able to call this
        vm.prank(vm.addr(34567890));
        auction.flushBeneficiaryBalance();

        uint256 auctionBalanceAfter = erc20.balanceOf(address(auction));
        uint256 beneficiaryBalanceAfter = erc20.balanceOf(auction.beneficiary());
        assertTrue(auction.beneficiaryBalance() == 0, "bal after");
        assertEq(beneficiaryBalanceAfter - beneficiaryBalanceBefore, bid0.amount);
        assertEq(auctionBalanceBefore - auctionBalanceAfter, bid0.amount);
        assertEq(erc20.balanceOf(address(burner)), bid0.amount);

        vm.prank(vm.addr(948765));
        burner.burn();

        assertEq(erc20.balanceOf(address(burner)), 0);
    }

    function testCannotResolveNotAuctioneer() public {
        ResolveSetup memory rs = deployDepositAndBids();
        vm.stopPrank();

        bytes memory revertString = abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(uint160(bidders[3].addr), 20),
            " is missing role ",
            Strings.toHexString(uint256(rs.auction.AUCTIONEER_ROLE()), 32)
        );

        vm.startPrank(bidders[3].addr);
        vm.expectRevert(revertString);
        rs.auction.resolveMultiBidAuction(rs.bid1, rs.bid0);
        vm.stopPrank();

        vm.startPrank(bidders[3].addr);
        vm.expectRevert(revertString);
        rs.auction.resolveSingleBidAuction(rs.bid0);
        vm.stopPrank();
    }

    function testCannotResolveSamePerson() public {
        ResolveSetup memory rs = deployDepositAndBids();

        rs.bid0.signature = sign(bidders[1].privKey, rs.h0);

        vm.expectRevert(SameBidder.selector);
        rs.auction.resolveMultiBidAuction(rs.bid1, rs.bid0);
    }

    function testCannotResolveBidWrongOrder() public {
        ResolveSetup memory rs = deployDepositAndBids();
        vm.expectRevert(BidsWrongOrder.selector);
        rs.auction.resolveMultiBidAuction(rs.bid0, rs.bid1);
    }

    function testCannotResolveTieBidWrongOrder() public {
        ResolveSetup memory rs = deployDepositAndBids();

        // bid1.amount == bid0.amount
        bytes32 h1 =
            rs.auction.getBidHash(rs.biddingForRound, bidders[0].elc, bidders[0].amount / 2);
        Bid memory bid1 = Bid({
            amount: bidders[0].amount / 2,
            expressLaneController: bidders[0].elc,
            signature: sign(bidders[1].privKey, h1)
        });

        vm.expectRevert(TieBidsWrongOrder.selector);
        rs.auction.resolveMultiBidAuction(bid1, rs.bid0);

        // success now with the same price
        rs.auction.resolveMultiBidAuction(rs.bid0, bid1);
    }

    function testCannotResolveReserveNotMet() public {
        ResolveSetup memory rs = deployDepositAndBids();

        bytes32 h0 = rs.auction.getBidHash(rs.biddingForRound, bidders[0].elc, minReservePrice - 1);
        Bid memory bid0 = Bid({
            amount: minReservePrice - 1,
            expressLaneController: bidders[0].elc,
            signature: sign(bidders[0].privKey, h0)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                ReservePriceNotMet.selector, minReservePrice - 1, minReservePrice
            )
        );
        rs.auction.resolveMultiBidAuction(rs.bid1, bid0);

        vm.expectRevert(
            abi.encodeWithSelector(
                ReservePriceNotMet.selector, minReservePrice - 1, minReservePrice
            )
        );
        rs.auction.resolveSingleBidAuction(bid0);
    }

    function testCannotResolveInsufficientFunds() public {
        ResolveSetup memory rs = deployDepositAndBids();

        bytes32 h1 =
            rs.auction.getBidHash(rs.biddingForRound, bidders[1].elc, bidders[1].amount * 2);
        Bid memory bid1 = Bid({
            amount: bidders[1].amount * 2,
            expressLaneController: bidders[1].elc,
            signature: sign(bidders[1].privKey, h1)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                InsufficientBalanceAcc.selector,
                bidders[1].addr,
                bidders[1].amount * 2,
                bidders[1].amount
            )
        );
        rs.auction.resolveMultiBidAuction(bid1, rs.bid0);

        bytes32 h0 =
            rs.auction.getBidHash(rs.biddingForRound, bidders[0].elc, (bidders[0].amount * 3) / 2);
        Bid memory bid0 = Bid({
            amount: (bidders[0].amount * 3) / 2,
            expressLaneController: bidders[0].elc,
            signature: sign(bidders[0].privKey, h0)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                InsufficientBalanceAcc.selector,
                bidders[0].addr,
                (bidders[0].amount * 3) / 2,
                bidders[0].amount
            )
        );
        rs.auction.resolveMultiBidAuction(rs.bid1, bid0);

        vm.expectRevert(
            abi.encodeWithSelector(
                InsufficientBalanceAcc.selector,
                bidders[1].addr,
                bidders[1].amount * 2,
                bidders[1].amount
            )
        );
        rs.auction.resolveSingleBidAuction(bid1);
    }

    function testCannotResolveWrongChain() public {
        ResolveSetup memory rs = deployDepositAndBids();
        vm.chainId(31337);
        bytes32 h1 =
            rs.auction.getBidHash(rs.biddingForRound, bidders[1].elc, bidders[1].amount / 2);

        vm.chainId(137);
        bytes32 correctH1 =
            rs.auction.getBidHash(rs.biddingForRound, bidders[1].elc, bidders[1].amount / 2);
        Bid memory bid1 = Bid({
            amount: bidders[1].amount / 2,
            expressLaneController: bidders[1].elc,
            signature: sign(bidders[1].privKey, h1)
        });

        address wrongBidder1 = correctH1.recover(bid1.signature);

        // wrong chain means wrong hash means wrong address
        vm.expectRevert(
            abi.encodeWithSelector(
                InsufficientBalanceAcc.selector, wrongBidder1, bidders[1].amount / 2, 0
            )
        );
        rs.auction.resolveMultiBidAuction(bid1, rs.bid0);

        vm.chainId(31337);
        bytes32 h0 =
            rs.auction.getBidHash(rs.biddingForRound, bidders[0].elc, bidders[0].amount / 2);

        vm.chainId(137);
        bytes32 correctH0 =
            rs.auction.getBidHash(rs.biddingForRound, bidders[0].elc, bidders[0].amount / 2);
        Bid memory bid0 = Bid({
            amount: bidders[0].amount / 2,
            expressLaneController: bidders[0].elc,
            signature: sign(bidders[0].privKey, h0)
        });

        address wrongBidder0 = correctH0.recover(bid0.signature);

        // wrong chain means wrong hash means wrong address
        vm.expectRevert(
            abi.encodeWithSelector(
                InsufficientBalanceAcc.selector, wrongBidder0, bidders[0].amount / 2, 0
            )
        );
        rs.auction.resolveMultiBidAuction(rs.bid1, bid0);

        // wrong chain means wrong hash means wrong address
        vm.expectRevert(
            abi.encodeWithSelector(
                InsufficientBalanceAcc.selector, wrongBidder1, bidders[1].amount / 2, 0
            )
        );
        rs.auction.resolveSingleBidAuction(bid1);
    }

    function testCannotResolveWrongContract() public {
        ResolveSetup memory rs = deployDepositAndBids();

        (, bytes memory res) = address(rs.auction).delegatecall(
            abi.encodeWithSelector(
                rs.auction.getBidHash.selector,
                rs.biddingForRound,
                bidders[1].elc,
                bidders[1].amount / 2
            )
        );
        bytes32 h1 = bytes32(res);

        Bid memory bid1 = Bid({
            amount: bidders[1].amount / 2,
            expressLaneController: bidders[1].elc,
            signature: sign(bidders[1].privKey, h1)
        });
        bytes32 correctH1 =
            rs.auction.getBidHash(rs.biddingForRound, bidders[1].elc, bidders[1].amount / 2);
        address wrongBidder1 = correctH1.recover(bid1.signature);

        // wrong chain means wrong hash means wrong address
        vm.expectRevert(
            abi.encodeWithSelector(
                InsufficientBalanceAcc.selector, wrongBidder1, bidders[1].amount / 2, 0
            )
        );
        rs.auction.resolveMultiBidAuction(bid1, rs.bid0);

        (, res) = address(rs.auction).delegatecall(
            abi.encodeWithSelector(
                rs.auction.getBidHash.selector,
                rs.biddingForRound,
                bidders[0].elc,
                bidders[0].amount / 2
            )
        );
        bytes32 h0 = bytes32(res);
        Bid memory bid0 = Bid({
            amount: bidders[0].amount / 2,
            expressLaneController: bidders[0].elc,
            signature: sign(bidders[0].privKey, h0)
        });
        bytes32 correctH0 =
            rs.auction.getBidHash(rs.biddingForRound, bidders[0].elc, bidders[0].amount / 2);
        address wrongBidder0 = correctH0.recover(bid0.signature);

        // wrong chain means wrong hash means wrong address
        vm.expectRevert(
            abi.encodeWithSelector(
                InsufficientBalanceAcc.selector, wrongBidder0, bidders[0].amount / 2, 0
            )
        );
        rs.auction.resolveMultiBidAuction(rs.bid1, bid0);

        // wrong chain means wrong hash means wrong address
        vm.expectRevert(
            abi.encodeWithSelector(
                InsufficientBalanceAcc.selector, wrongBidder0, bidders[0].amount / 2, 0
            )
        );
        rs.auction.resolveSingleBidAuction(bid0);
    }

    error ECDSAInvalidSignature();

    function testCannotResolveWrongSig() public {
        ResolveSetup memory rs = deployDepositAndBids();

        bytes32 h1 =
            rs.auction.getBidHash(rs.biddingForRound, bidders[1].elc, bidders[1].amount / 2);
        (, bytes32 r2, bytes32 s2) = vm.sign(bidders[1].privKey, h1);
        uint8 badV = 17;
        Bid memory bid1 = Bid({
            amount: bidders[1].amount / 2,
            expressLaneController: bidders[1].elc,
            signature: abi.encodePacked(r2, s2, badV)
        });

        // bad v means invalid sig
        // vm.expectRevert(ECDSAInvalidSignature.selector);
        vm.expectRevert(abi.encodePacked("ECDSA: invalid signature 'v' value"));
        rs.auction.resolveMultiBidAuction(bid1, rs.bid0);

        bytes32 h0 =
            rs.auction.getBidHash(rs.biddingForRound, bidders[0].elc, bidders[0].amount / 2);
        (, bytes32 r1, bytes32 s1) = vm.sign(bidders[0].privKey, h0);
        Bid memory bid0 = Bid({
            amount: bidders[0].amount / 2,
            expressLaneController: bidders[0].elc,
            signature: abi.encodePacked(r1, s1, badV)
        });

        // bad v means invalid sig
        // vm.expectRevert(ECDSAInvalidSignature.selector);
        vm.expectRevert(abi.encodePacked("ECDSA: invalid signature 'v' value"));
        rs.auction.resolveMultiBidAuction(rs.bid1, bid0);

        // bad v means invalid sig
        // vm.expectRevert(ECDSAInvalidSignature.selector);
        vm.expectRevert(abi.encodePacked("ECDSA: invalid signature 'v' value"));
        rs.auction.resolveSingleBidAuction(bid0);
    }

    function testCannotResolveBeforeRoundCloses() public {
        ResolveSetup memory rs = deployDepositAndBids();
        assertEq(rs.auction.isAuctionRoundClosed(), true, "Auction round not closed");

        vm.warp(block.timestamp - 1);

        // rewind to open the auction
        assertEq(rs.auction.isAuctionRoundClosed(), false, "Auction round not open");

        vm.expectRevert(abi.encodeWithSelector(AuctionNotClosed.selector));
        rs.auction.resolveMultiBidAuction(rs.bid1, rs.bid0);

        vm.expectRevert(abi.encodeWithSelector(AuctionNotClosed.selector));
        rs.auction.resolveSingleBidAuction(rs.bid1);

        // go forward again to close again
        vm.warp(block.timestamp + 1);
        assertEq(rs.auction.isAuctionRoundClosed(), true, "Auction round not closed");
        rs.auction.resolveMultiBidAuction(rs.bid1, rs.bid0);
    }

    function checkResolvedRounds(
        IExpressLaneAuction auction,
        ELCRound memory expected0,
        ELCRound memory expected1
    ) internal {
        (ELCRound memory actual0, ELCRound memory actual1) = auction.resolvedRounds();
        assertEq(actual0.expressLaneController, expected0.expressLaneController, "0 elc");
        assertEq(actual0.round, expected0.round, "0 round");
        assertEq(actual1.expressLaneController, expected1.expressLaneController, "1 elc");
        assertEq(actual1.round, expected1.round, "1 round");
    }

    function testResolveMultiBidAuction() public {
        ResolveSetup memory rs = deployDepositAndBids();
        uint64 biddingForRound = rs.auction.currentRound() + 1;
        (, uint64 roundDurationSeconds, uint64 auctionClosingSeconds,) =
            rs.auction.roundTimingInfo();
        uint256 auctionBalanceBefore = rs.erc20.balanceOf(address(rs.auction));

        vm.expectEmit(true, true, true, true);
        emit SetExpressLaneController(
            biddingForRound,
            address(0),
            bidders[1].elc,
            address(0),
            uint64(block.timestamp + auctionClosingSeconds),
            uint64(block.timestamp + auctionClosingSeconds + roundDurationSeconds - 1)
        );
        vm.expectEmit(true, true, true, true);
        emit AuctionResolved(
            true,
            biddingForRound,
            bidders[1].addr,
            bidders[1].elc,
            bidders[1].amount / 2,
            bidders[0].amount / 2,
            uint64(block.timestamp + auctionClosingSeconds),
            uint64(block.timestamp + auctionClosingSeconds + roundDurationSeconds - 1)
        );
        rs.auction.resolveMultiBidAuction(rs.bid1, rs.bid0);

        // firstPriceBidder (bidders[1].addr) pays the price of the second price bidder (bidders[0].addr)
        assertEq(rs.auction.balanceOf(bidders[1].addr), bidders[1].amount - bidders[0].amount / 2);
        assertEq(rs.auction.balanceOf(bidders[0].addr), bidders[0].amount);
        assertEq(rs.auction.beneficiaryBalance(), bidders[0].amount / 2);
        assertEq(rs.erc20.balanceOf(address(rs.auction)), auctionBalanceBefore);
        ELCRound memory expected0 = ELCRound(rs.bid1.expressLaneController, biddingForRound);
        checkResolvedRounds(rs.auction, expected0, ELCRound(address(0), 0));

        // cannot resolve same bid
        vm.expectRevert(abi.encodeWithSelector(RoundAlreadyResolved.selector, biddingForRound));
        rs.auction.resolveMultiBidAuction(rs.bid1, rs.bid0);

        // cannot resolve other bids for the same round
        Bid[2] memory bid34;
        bid34[0] = Bid({
            amount: bidders[2].amount / 4,
            expressLaneController: bidders[2].elc,
            signature: sign(
                bidders[2].privKey,
                rs.auction.getBidHash(biddingForRound, bidders[2].elc, bidders[2].amount / 4)
            )
        });
        bid34[1] = Bid({
            amount: bidders[3].amount / 4,
            expressLaneController: bidders[3].elc,
            signature: sign(
                bidders[3].privKey,
                rs.auction.getBidHash(biddingForRound, bidders[3].elc, bidders[3].amount / 4)
            )
        });

        vm.expectRevert(abi.encodeWithSelector(RoundAlreadyResolved.selector, biddingForRound));
        rs.auction.resolveMultiBidAuction(bid34[1], bid34[0]);

        vm.warp(block.timestamp + roundDurationSeconds);

        // since we're now on the next round the bid hash will be incorrect
        // and the signature will return an unexpected address, which will have no balance
        vm.expectRevert(
            abi.encodeWithSelector(
                InsufficientBalanceAcc.selector,
                rs.auction.getBidHash(
                    rs.auction.currentRound() + 1, bidders[3].elc, bidders[3].amount / 4
                ).recover(bid34[1].signature),
                bidders[3].amount / 4,
                0
            )
        );
        rs.auction.resolveMultiBidAuction(bid34[1], bid34[0]);

        // successful resolution with correct round
        biddingForRound = rs.auction.currentRound() + 1;
        bid34[0] = Bid({
            amount: bidders[2].amount / 4,
            expressLaneController: bidders[2].elc,
            signature: sign(
                bidders[2].privKey,
                rs.auction.getBidHash(biddingForRound, bidders[2].elc, bidders[2].amount / 4)
            )
        });
        bid34[1] = Bid({
            amount: bidders[3].amount / 4,
            expressLaneController: bidders[3].elc,
            signature: sign(
                bidders[3].privKey,
                rs.auction.getBidHash(biddingForRound, bidders[3].elc, bidders[3].amount / 4)
            )
        });

        auctionBalanceBefore = rs.erc20.balanceOf(address(rs.auction));
        uint256 beneficiaryBalanceBefore = rs.auction.beneficiaryBalance();

        vm.expectEmit(true, true, true, true);
        emit SetExpressLaneController(
            biddingForRound,
            address(0),
            bidders[3].elc,
            address(0),
            uint64(block.timestamp + auctionClosingSeconds),
            uint64(block.timestamp + auctionClosingSeconds + roundDurationSeconds - 1)
        );
        vm.expectEmit(true, true, true, true);
        emit AuctionResolved(
            true,
            biddingForRound,
            bidders[3].addr,
            bidders[3].elc,
            bidders[3].amount / 4,
            bidders[2].amount / 4,
            uint64(block.timestamp + auctionClosingSeconds),
            uint64(block.timestamp + auctionClosingSeconds + roundDurationSeconds - 1)
        );
        rs.auction.resolveMultiBidAuction(bid34[1], bid34[0]);

        assertEq(
            rs.auction.balanceOf(bidders[3].addr),
            bidders[3].amount - bidders[2].amount / 4,
            "bidders[3].addr balance"
        );
        assertEq(
            rs.auction.balanceOf(bidders[2].addr), bidders[2].amount, "bidders[2].addr balance"
        );
        assertEq(
            rs.auction.beneficiaryBalance() - beneficiaryBalanceBefore,
            bidders[2].amount / 4,
            "beneficiary balance"
        );
        assertEq(rs.erc20.balanceOf(address(rs.auction)), auctionBalanceBefore, "auction balance");
        checkResolvedRounds(
            rs.auction, ELCRound(bid34[1].expressLaneController, biddingForRound), expected0
        );

        vm.stopPrank();
    }

    function testResolveMultiBidZeroSecondPrice() public {
        ResolveSetup memory rs = deployDepositAndBids();
        vm.stopPrank();

        (
            ,
            uint64 roundDurationSeconds,
            uint64 auctionClosingSeconds,
            uint64 reservePriceSubmissionSeconds
        ) = rs.auction.roundTimingInfo();
        uint256 auctionBalanceBefore = rs.erc20.balanceOf(address(rs.auction));

        vm.prank(minReservePriceSetter);
        rs.auction.setMinReservePrice(0);
        vm.warp(block.timestamp - reservePriceSubmissionSeconds - 1);
        vm.prank(reservePriceSetter);
        rs.auction.setReservePrice(0);
        vm.warp(block.timestamp + reservePriceSubmissionSeconds + 1);

        uint64 biddingForRound = rs.auction.currentRound() + 1;

        // zero amount bid
        bytes32 h0 = rs.auction.getBidHash(biddingForRound, bidders[0].elc, 0);
        Bid memory bid0 = Bid({
            amount: 0,
            expressLaneController: bidders[0].elc,
            signature: sign(bidders[0].privKey, h0)
        });
        {
            bytes32 h1 = rs.auction.getBidHash(biddingForRound, vm.addr(1667), 0);
            Bid memory bid1 =
                Bid({amount: 0, expressLaneController: vm.addr(1667), signature: sign(1668, h1)});
            vm.expectRevert(abi.encodeWithSelector(InsufficientBalance.selector, 0, 0));
            vm.prank(auctioneer);
            rs.auction.resolveMultiBidAuction(bid1, bid0);
        }

        vm.expectEmit(true, true, true, true);
        emit SetExpressLaneController(
            biddingForRound,
            address(0),
            bidders[1].elc,
            address(0),
            uint64(block.timestamp + auctionClosingSeconds),
            uint64(block.timestamp + auctionClosingSeconds + roundDurationSeconds - 1)
        );
        vm.expectEmit(true, true, true, true);
        emit AuctionResolved(
            true,
            biddingForRound,
            bidders[1].addr,
            bidders[1].elc,
            bidders[1].amount / 2,
            0,
            uint64(block.timestamp + auctionClosingSeconds),
            uint64(block.timestamp + auctionClosingSeconds + roundDurationSeconds - 1)
        );
        vm.prank(auctioneer);
        rs.auction.resolveMultiBidAuction(rs.bid1, bid0);

        // firstPriceBidder (bidders[1].addr) pays the price of the second price bidder (bidders[0].addr)
        assertEq(rs.auction.balanceOf(bidders[1].addr), bidders[1].amount);
        assertEq(rs.auction.balanceOf(bidders[0].addr), bidders[0].amount);
        assertEq(rs.auction.beneficiaryBalance(), 0);
        assertEq(rs.erc20.balanceOf(address(rs.auction)), auctionBalanceBefore);
        ELCRound memory expected0 = ELCRound(rs.bid1.expressLaneController, biddingForRound);
        checkResolvedRounds(rs.auction, expected0, ELCRound(address(0), 0));
    }

    function testResolveSingleBidZeroSecondPrice() public {
        ResolveSetup memory rs = deployDepositAndBids();
        vm.stopPrank();

        (
            ,
            uint64 roundDurationSeconds,
            uint64 auctionClosingSeconds,
            uint64 reservePriceSubmissionSeconds
        ) = rs.auction.roundTimingInfo();
        uint256 auctionBalanceBefore = rs.erc20.balanceOf(address(rs.auction));

        vm.prank(minReservePriceSetter);
        rs.auction.setMinReservePrice(0);
        vm.warp(block.timestamp - reservePriceSubmissionSeconds - 1);
        vm.prank(reservePriceSetter);
        rs.auction.setReservePrice(0);
        vm.warp(block.timestamp + reservePriceSubmissionSeconds + 1);

        uint64 biddingForRound = rs.auction.currentRound() + 1;

        {
            bytes32 h1 = rs.auction.getBidHash(biddingForRound, vm.addr(1667), 0);
            Bid memory bid1 =
                Bid({amount: 0, expressLaneController: vm.addr(1667), signature: sign(1668, h1)});
            vm.expectRevert(abi.encodeWithSelector(InsufficientBalance.selector, 0, 0));
            vm.prank(auctioneer);
            rs.auction.resolveSingleBidAuction(bid1);
        }

        vm.expectEmit(true, true, true, true);
        emit SetExpressLaneController(
            biddingForRound,
            address(0),
            bidders[1].elc,
            address(0),
            uint64(block.timestamp + auctionClosingSeconds),
            uint64(block.timestamp + auctionClosingSeconds + roundDurationSeconds - 1)
        );
        vm.expectEmit(true, true, true, true);
        emit AuctionResolved(
            false,
            biddingForRound,
            bidders[1].addr,
            bidders[1].elc,
            bidders[1].amount / 2,
            0,
            uint64(block.timestamp + auctionClosingSeconds),
            uint64(block.timestamp + auctionClosingSeconds + roundDurationSeconds - 1)
        );
        vm.prank(auctioneer);
        rs.auction.resolveSingleBidAuction(rs.bid1);

        // firstPriceBidder (bidders[1].addr) pays the price of the second price bidder (bidders[0].addr)
        assertEq(rs.auction.balanceOf(bidders[1].addr), bidders[1].amount);
        assertEq(rs.auction.balanceOf(bidders[0].addr), bidders[0].amount);
        assertEq(rs.auction.beneficiaryBalance(), 0);
        assertEq(rs.erc20.balanceOf(address(rs.auction)), auctionBalanceBefore);
        ELCRound memory expected0 = ELCRound(rs.bid1.expressLaneController, biddingForRound);
        checkResolvedRounds(rs.auction, expected0, ELCRound(address(0), 0));
    }

    function testResolveMultiBidAuctionWithdrawalInitiated() public {
        ResolveSetup memory rs = deployDepositAndBids();
        vm.stopPrank();

        // go back and initiate a withdrawal
        vm.warp(block.timestamp - 1);

        vm.prank(bidders[0].addr);
        rs.auction.initiateWithdrawal();

        vm.prank(bidders[1].addr);
        rs.auction.initiateWithdrawal();

        vm.warp(block.timestamp + 1);

        vm.prank(auctioneer);
        rs.auction.resolveMultiBidAuction(rs.bid1, rs.bid0);
    }

    function testResolveMultiBidAuctionWithdrawalInitiatedRoundPlusOne() public {
        ResolveSetup memory rs = deployDepositAndBids();
        vm.stopPrank();

        // go back and initiate a withdrawal
        (, uint64 roundDurationSeconds,,) = rs.auction.roundTimingInfo();
        vm.warp(block.timestamp - 1 - roundDurationSeconds);

        vm.prank(bidders[0].addr);
        rs.auction.initiateWithdrawal();

        vm.prank(bidders[1].addr);
        rs.auction.initiateWithdrawal();

        vm.warp(block.timestamp + 1 + roundDurationSeconds);

        vm.prank(auctioneer);
        rs.auction.resolveMultiBidAuction(rs.bid1, rs.bid0);
    }

    function testResolveMultiBidAuctionWithdrawalInitiatedRoundPlusTwoSecondPrice() public {
        ResolveSetup memory rs = deployDepositAndBids();
        vm.stopPrank();

        // go back and initiate a withdrawal
        (, uint64 roundDurationSeconds,,) = rs.auction.roundTimingInfo();
        vm.warp(block.timestamp - 1 - roundDurationSeconds * 2);

        vm.prank(bidders[0].addr);
        rs.auction.initiateWithdrawal();

        vm.warp(block.timestamp + 1 + roundDurationSeconds * 2);

        vm.prank(auctioneer);
        vm.expectRevert(
            abi.encodeWithSelector(
                InsufficientBalanceAcc.selector, bidders[0].addr, rs.bid0.amount, 0
            )
        );
        rs.auction.resolveMultiBidAuction(rs.bid1, rs.bid0);
    }

    function testResolveMultiBidAuctionWithdrawalInitiatedRoundPlusTwoFirstPrice() public {
        ResolveSetup memory rs = deployDepositAndBids();
        vm.stopPrank();

        // go back and initiate a withdrawal
        (, uint64 roundDurationSeconds,,) = rs.auction.roundTimingInfo();
        vm.warp(block.timestamp - 1 - roundDurationSeconds * 2);

        vm.prank(bidders[1].addr);
        rs.auction.initiateWithdrawal();

        vm.warp(block.timestamp + 1 + roundDurationSeconds * 2);

        vm.prank(auctioneer);
        vm.expectRevert(
            abi.encodeWithSelector(
                InsufficientBalanceAcc.selector, bidders[1].addr, rs.bid1.amount, 0
            )
        );
        rs.auction.resolveMultiBidAuction(rs.bid1, rs.bid0);
    }

    function testResolveSingleBidAuction() public {
        ResolveSetup memory rs = deployDepositAndBids();
        uint64 biddingForRound = rs.auction.currentRound() + 1;
        (, uint64 roundDurationSeconds, uint64 auctionClosingSeconds,) =
            rs.auction.roundTimingInfo();

        uint256 auctionBalanceBefore = rs.erc20.balanceOf(address(rs.auction));

        vm.expectEmit(true, true, true, true);
        emit SetExpressLaneController(
            biddingForRound,
            address(0),
            bidders[1].elc,
            address(0),
            uint64(block.timestamp + auctionClosingSeconds),
            uint64(block.timestamp + auctionClosingSeconds + roundDurationSeconds - 1)
        );
        vm.expectEmit(true, true, true, true);
        emit AuctionResolved(
            false,
            biddingForRound,
            bidders[1].addr,
            bidders[1].elc,
            bidders[1].amount / 2,
            minReservePrice,
            uint64(block.timestamp + auctionClosingSeconds),
            uint64(block.timestamp + auctionClosingSeconds + roundDurationSeconds - 1)
        );
        rs.auction.resolveSingleBidAuction(rs.bid1);

        // firstPriceBidder (bidders[1].addr) pays the reserve price
        assertEq(rs.auction.balanceOf(bidders[1].addr), bidders[1].amount - minReservePrice);
        assertEq(rs.auction.balanceOf(bidders[0].addr), bidders[0].amount);
        assertEq(rs.auction.beneficiaryBalance(), minReservePrice);
        assertEq(rs.erc20.balanceOf(address(rs.auction)), auctionBalanceBefore);
        ELCRound memory expected0 = ELCRound(rs.bid1.expressLaneController, biddingForRound);
        checkResolvedRounds(rs.auction, expected0, ELCRound(address(0), 0));
    }

    function testCanSetReservePrice() public {
        ResolveSetup memory rs = deployDepositAndBids();
        // start of the test round
        (
            int64 offsetTimestampA,
            uint64 roundDurationSeconds,
            uint64 auctionClosingSeconds,
            uint64 reserveSubmissionSeconds
        ) = rs.auction.roundTimingInfo();
        vm.warp(uint64(offsetTimestampA) + roundDurationSeconds * testRound);
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
        vm.warp(
            uint64(offsetTimestamp) + roundDurationSeconds * (testRound + 1) - auctionClosingSeconds
                - reserveSubmissionSeconds
        );

        vm.prank(reservePriceSetter);
        vm.expectRevert(abi.encodeWithSelector(ReserveBlackout.selector));
        rs.auction.setReservePrice(minReservePrice);

        vm.warp(
            uint64(offsetTimestamp) + roundDurationSeconds * (testRound + 1) - auctionClosingSeconds
        );

        vm.prank(reservePriceSetter);
        vm.expectRevert(abi.encodeWithSelector(ReserveBlackout.selector));
        rs.auction.setReservePrice(minReservePrice);

        vm.prank(auctioneer);
        rs.auction.resolveMultiBidAuction(rs.bid1, rs.bid0);

        // after blackout, but in same round
        vm.prank(reservePriceSetter);
        vm.expectEmit(true, true, true, true);
        emit SetReservePrice(minReservePrice + 1, minReservePrice + 2);
        rs.auction.setReservePrice(minReservePrice + 2);
        assertEq(rs.auction.reservePrice(), minReservePrice + 2);
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
        (
            ,
            uint64 roundDurationSeconds,
            uint64 auctionClosingSeconds,
            uint64 reserveSubmissionSeconds
        ) = auction.roundTimingInfo();
        vm.warp(
            block.timestamp + roundDurationSeconds - auctionClosingSeconds
                - reserveSubmissionSeconds
        );
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
        rs.auction.transferExpressLaneController(testRound - 1, bidders[0].elc);

        // cant transfer before something is set
        vm.expectRevert(abi.encodeWithSelector(RoundNotResolved.selector, testRound));
        rs.auction.transferExpressLaneController(testRound, bidders[0].elc);
        vm.expectRevert(abi.encodeWithSelector(RoundNotResolved.selector, testRound + 1));
        rs.auction.transferExpressLaneController(testRound + 1, bidders[0].elc);

        // resolve a round
        vm.prank(auctioneer);
        rs.auction.resolveMultiBidAuction(rs.bid1, rs.bid0);

        // current round still not resolved
        vm.expectRevert(abi.encodeWithSelector(RoundNotResolved.selector, testRound));
        rs.auction.transferExpressLaneController(testRound, bidders[0].elc);
        vm.expectRevert(
            abi.encodeWithSelector(
                NotExpressLaneController.selector, testRound + 1, bidders[1].elc, address(this)
            )
        );
        rs.auction.transferExpressLaneController(testRound + 1, bidders[0].elc);

        (uint64 start, uint64 end) = rs.auction.roundTimestamps(testRound + 1);
        vm.prank(bidders[1].elc);
        vm.expectEmit(true, true, true, true);
        emit SetExpressLaneController(
            testRound + 1, bidders[1].elc, bidders[0].elc, bidders[1].elc, start, end
        );
        rs.auction.transferExpressLaneController(testRound + 1, bidders[0].elc);

        (, uint64 roundDurationSeconds,,) = rs.auction.roundTimingInfo();
        vm.warp(block.timestamp + roundDurationSeconds);

        // round has moved forward
        vm.expectRevert(abi.encodeWithSelector(RoundTooOld.selector, testRound, testRound + 1));
        rs.auction.transferExpressLaneController(testRound, bidders[0].elc);
        vm.expectRevert(abi.encodeWithSelector(RoundNotResolved.selector, testRound + 2));
        rs.auction.transferExpressLaneController(testRound + 2, bidders[0].elc);

        // can still change the current
        vm.prank(bidders[0].elc);
        vm.expectEmit(true, true, true, true);
        emit SetExpressLaneController(
            testRound + 1,
            bidders[0].elc,
            bidders[1].elc,
            bidders[0].elc,
            uint64(block.timestamp),
            end
        );
        rs.auction.transferExpressLaneController(testRound + 1, bidders[1].elc);

        // some new bids for the next round
        bytes32 h2 = rs.auction.getBidHash(testRound + 2, bidders[2].elc, bidders[2].amount / 2);
        Bid memory bid2 = Bid({
            amount: bidders[2].amount / 2,
            expressLaneController: bidders[2].elc,
            signature: sign(bidders[2].privKey, h2)
        });
        bytes32 h3 = rs.auction.getBidHash(testRound + 2, bidders[3].elc, bidders[3].amount / 2);
        Bid memory bid3 = Bid({
            amount: bidders[3].amount / 2,
            expressLaneController: bidders[3].elc,
            signature: sign(bidders[3].privKey, h3)
        });

        vm.prank(auctioneer);
        rs.auction.resolveMultiBidAuction(bid3, bid2);

        // change current
        vm.prank(bidders[1].elc);
        vm.expectEmit(true, true, true, true);
        emit SetExpressLaneController(
            testRound + 1,
            bidders[1].elc,
            bidders[0].elc,
            bidders[1].elc,
            uint64(block.timestamp),
            end
        );
        rs.auction.transferExpressLaneController(testRound + 1, bidders[0].elc);

        // cant change next from wrong sender
        vm.expectRevert(
            abi.encodeWithSelector(
                NotExpressLaneController.selector, testRound + 2, bidders[3].elc, address(this)
            )
        );
        rs.auction.transferExpressLaneController(testRound + 2, bidders[2].elc);

        // change next now
        start = start + roundDuration;
        end = end + roundDuration;
        vm.prank(bidders[3].elc);
        vm.expectEmit(true, true, true, true);
        emit SetExpressLaneController(
            testRound + 2, bidders[3].elc, bidders[2].elc, bidders[3].elc, start, end
        );
        rs.auction.transferExpressLaneController(testRound + 2, bidders[2].elc);

        // set a transferor and have them transfer
        vm.prank(bidders[2].elc);
        rs.auction.setTransferor(Transferor(bidders[2].addr, 1000));

        vm.prank(bidders[3].elc);
        vm.expectRevert(
            abi.encodeWithSelector(
                NotTransferor.selector, testRound + 2, bidders[2].addr, bidders[3].elc
            )
        );
        rs.auction.transferExpressLaneController(testRound + 2, bidders[2].elc);

        // change next now
        vm.prank(bidders[2].addr);
        vm.expectEmit(true, true, true, true);
        emit SetExpressLaneController(
            testRound + 2, bidders[2].elc, bidders[3].elc, bidders[2].addr, start, end
        );
        rs.auction.transferExpressLaneController(testRound + 2, bidders[3].elc);
    }

    function testSetTransferor() public {
        (, IExpressLaneAuction auction) = deploy();

        address elc = vm.addr(1559);
        address transferor = vm.addr(1560);
        address transferor2 = vm.addr(1561);
        uint64 fixedUntilRound = 137;
        address actualTransferor;
        uint64 actualFixedUntil;
        (actualTransferor, actualFixedUntil) = auction.transferorOf(elc);
        assertEq(actualTransferor, address(0));
        assertEq(actualFixedUntil, 0);

        vm.prank(elc);
        vm.expectEmit(true, true, true, true);
        emit SetTransferor(elc, transferor, 0);
        auction.setTransferor(Transferor({addr: transferor, fixedUntilRound: 0}));
        (actualTransferor, actualFixedUntil) = auction.transferorOf(elc);
        assertEq(actualTransferor, transferor);
        assertEq(actualFixedUntil, 0);

        vm.prank(elc);
        vm.expectEmit(true, true, true, true);
        emit SetTransferor(elc, transferor2, fixedUntilRound);
        auction.setTransferor(Transferor({addr: transferor2, fixedUntilRound: fixedUntilRound}));
        (actualTransferor, actualFixedUntil) = auction.transferorOf(elc);
        assertEq(actualTransferor, transferor2);
        assertEq(actualFixedUntil, fixedUntilRound);

        vm.prank(elc);
        vm.expectRevert(abi.encodeWithSelector(FixedTransferor.selector, fixedUntilRound));
        auction.setTransferor(Transferor({addr: transferor, fixedUntilRound: fixedUntilRound + 1}));

        while (auction.currentRound() < fixedUntilRound) {
            vm.warp(block.timestamp + roundDuration);
        }

        assertEq(auction.currentRound(), fixedUntilRound);
        vm.prank(elc);
        vm.expectEmit(true, true, true, true);
        emit SetTransferor(elc, transferor, fixedUntilRound + 1);
        auction.setTransferor(Transferor({addr: transferor, fixedUntilRound: fixedUntilRound + 1}));
        (actualTransferor, actualFixedUntil) = auction.transferorOf(elc);
        assertEq(actualTransferor, transferor);
        assertEq(actualFixedUntil, fixedUntilRound + 1);
    }

    function testSetBeneficiary() public {
        ResolveSetup memory rs = deployDepositAndBids();
        vm.stopPrank();

        address newBeneficiary = vm.addr(9090);

        bytes memory revertString = abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(uint160(address(this)), 20),
            " is missing role ",
            Strings.toHexString(uint256(rs.auction.BENEFICIARY_SETTER_ROLE()), 32)
        );
        vm.expectRevert(revertString);
        rs.auction.setBeneficiary(newBeneficiary);

        vm.prank(beneficiarySetter);
        vm.expectEmit(true, true, true, true);
        emit SetBeneficiary(beneficiary, newBeneficiary);
        rs.auction.setBeneficiary(newBeneficiary);
        assertEq(rs.auction.beneficiary(), newBeneficiary, "new beneficiary");
    }

    function testSetRoundTimingInfo() public {
        (, IExpressLaneAuction auction) = deploy();

        RoundTimingInfo memory newInfo = RoundTimingInfo({
            offsetTimestamp: 10,
            roundDurationSeconds: 70,
            auctionClosingSeconds: 10,
            reserveSubmissionSeconds: 20
        });

        bytes memory revertString = abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(uint160(address(this)), 20),
            " is missing role ",
            Strings.toHexString(uint256(auction.ROUND_TIMING_SETTER_ROLE()), 32)
        );
        vm.expectRevert(revertString);
        auction.setRoundTimingInfo(newInfo);

        // set to round 23
        vm.warp(uint64(offsetTimestamp) + roundDuration * 23);
        // now use an offset that would put us on round 24
        vm.prank(roundTimingSetter);
        vm.expectRevert(abi.encodeWithSelector(InvalidNewRound.selector, 23, 24));
        auction.setRoundTimingInfo(
            RoundTimingInfo({
                offsetTimestamp: offsetTimestamp - int64(roundDuration),
                roundDurationSeconds: roundDuration,
                auctionClosingSeconds: 10,
                reserveSubmissionSeconds: 20
            })
        );

        // round 23 but offset incorrect offset
        vm.prank(roundTimingSetter);
        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidNewStart.selector,
                uint64(offsetTimestamp) + roundDuration * 24,
                uint64(offsetTimestamp) + (roundDuration - 1) * 24
            )
        );
        auction.setRoundTimingInfo(
            RoundTimingInfo({
                offsetTimestamp: offsetTimestamp,
                roundDurationSeconds: roundDuration - 1,
                auctionClosingSeconds: 10,
                reserveSubmissionSeconds: 20
            })
        );

        (uint64 start,) = auction.roundTimestamps(auction.currentRound() + 1);
        int64 newOffset = int64(start - 86401 * 24);

        vm.prank(roundTimingSetter);
        vm.expectRevert(abi.encodeWithSelector(RoundTooLong.selector, 86401));
        auction.setRoundTimingInfo(
            RoundTimingInfo({
                offsetTimestamp: newOffset,
                roundDurationSeconds: 86401,
                auctionClosingSeconds: 10,
                reserveSubmissionSeconds: 20
            })
        );

        vm.prank(roundTimingSetter);
        vm.expectRevert(abi.encodeWithSelector(ZeroAuctionClosingSeconds.selector));
        auction.setRoundTimingInfo(
            RoundTimingInfo({
                offsetTimestamp: offsetTimestamp,
                roundDurationSeconds: roundDuration,
                auctionClosingSeconds: 0,
                reserveSubmissionSeconds: 20
            })
        );

        vm.prank(roundTimingSetter);
        vm.expectRevert(abi.encodeWithSelector(RoundDurationTooShort.selector));
        auction.setRoundTimingInfo(
            RoundTimingInfo({
                offsetTimestamp: offsetTimestamp,
                roundDurationSeconds: roundDuration,
                auctionClosingSeconds: roundDuration / 2,
                reserveSubmissionSeconds: roundDuration / 2 + 1
            })
        );

        uint64 cNewDuration = (roundDuration * 7) / 3;
        (uint64 cStart,) = auction.roundTimestamps(auction.currentRound() + 1);
        int64 cNewOffset = int64(cStart - cNewDuration * (auction.currentRound() + 1));

        vm.expectEmit(true, true, true, true);
        emit SetRoundTimingInfo(auction.currentRound(), cNewOffset, cNewDuration, 13, 12);
        vm.prank(roundTimingSetter);
        auction.setRoundTimingInfo(
            RoundTimingInfo({
                offsetTimestamp: cNewOffset,
                roundDurationSeconds: cNewDuration,
                auctionClosingSeconds: 13,
                reserveSubmissionSeconds: 12
            })
        );
        (int64 offsetAfter, uint64 durationAfter, uint64 acAfter, uint64 rsAfter) =
            auction.roundTimingInfo();
        assertEq(offsetAfter, cNewOffset);
        assertEq(durationAfter, cNewDuration);
        assertEq(acAfter, 13);
        assertEq(rsAfter, 12);

        // set the min duration
        cNewDuration = 1;
        (cStart,) = auction.roundTimestamps(auction.currentRound() + 1);
        int64 intStart = int64(cStart);
        // warp to just before that start - we need to be within round duration of the next round
        vm.warp(cStart - 1);
        cNewOffset = int64(intStart - int64(cNewDuration * (auction.currentRound() + 1)));
        vm.prank(roundTimingSetter);
        auction.setRoundTimingInfo(
            RoundTimingInfo({
                offsetTimestamp: cNewOffset,
                roundDurationSeconds: cNewDuration,
                auctionClosingSeconds: 1,
                reserveSubmissionSeconds: 0
            })
        );
        (offsetAfter, durationAfter, acAfter, rsAfter) = auction.roundTimingInfo();
        assertEq(offsetAfter, cNewOffset);
        assertEq(durationAfter, cNewDuration);
        assertEq(acAfter, 1);
        assertEq(rsAfter, 0);

        // fast forward 10k years - that sets a high number of rounds
        vm.warp(block.timestamp + (365 * 86400));
        cNewDuration = 86400;
        (cStart,) = auction.roundTimestamps(auction.currentRound() + 1);
        intStart = int64(cStart);
        cNewOffset = int64(intStart - int64(cNewDuration * (auction.currentRound() + 1)));
        vm.prank(roundTimingSetter);
        auction.setRoundTimingInfo(
            RoundTimingInfo({
                offsetTimestamp: cNewOffset,
                roundDurationSeconds: cNewDuration,
                auctionClosingSeconds: 13,
                reserveSubmissionSeconds: 12
            })
        );
        (offsetAfter, durationAfter, acAfter, rsAfter) = auction.roundTimingInfo();
        assertEq(offsetAfter, cNewOffset);
        assertEq(durationAfter, cNewDuration);
        assertEq(acAfter, 13);
        assertEq(rsAfter, 12);
    }
}
