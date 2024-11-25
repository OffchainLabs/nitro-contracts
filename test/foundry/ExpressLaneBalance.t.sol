// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/express-lane-auction/Balance.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract BalanceImp {
    using BalanceLib for Balance;

    constructor(Balance memory _bal) {
        bal = _bal;
    }

    Balance public bal;

    function balanceAtRound(uint64 round) external view returns (uint256) {
        return bal.balanceAtRound(round);
    }

    function withdrawableBalanceAtRound(uint64 round) external view returns (uint256) {
        return bal.withdrawableBalanceAtRound(round);
    }

    function increase(uint256 amount) external {
        return bal.increase(amount);
    }

    function reduce(uint256 amount, uint64 round) external {
        return bal.reduce(amount, round);
    }

    function initiateWithdrawal(uint64 round) external {
        return bal.initiateWithdrawal(round);
    }

    function finalizeWithdrawal(uint64 round) external returns (uint256) {
        return bal.finalizeWithdrawal(round);
    }
}

contract ExpressLaneBalanceTest is Test {
    function checkBal(BalanceImp b, Balance memory expectedBalance) internal {
        (uint256 balance, uint64 withdrawalRound) = b.bal();
        assertEq(balance, expectedBalance.balance);
        assertEq(withdrawalRound, expectedBalance.withdrawalRound);
    }

    function testBalanceAtRound(
        uint256 initialBalance,
        uint64 initialRound,
        uint64 withdrawalRound
    ) public {
        Balance memory bal = Balance(initialBalance, initialRound);
        BalanceImp b = new BalanceImp(bal);
        if (withdrawalRound >= initialRound) {
            assertEq(b.balanceAtRound(withdrawalRound), 0);
        } else {
            assertEq(b.balanceAtRound(withdrawalRound), initialBalance);
        }
    }

    function testWithdrawableBalanceAtRound(
        uint256 initialBalance,
        uint64 initialRound,
        uint64 withdrawalRound
    ) public {
        Balance memory bal = Balance(initialBalance, initialRound);
        BalanceImp b = new BalanceImp(bal);
        if (withdrawalRound >= initialRound) {
            assertEq(b.withdrawableBalanceAtRound(withdrawalRound), initialBalance);
        } else {
            assertEq(b.withdrawableBalanceAtRound(withdrawalRound), 0);
        }
    }

    function testIncrease(
        uint256 initialBalance,
        uint64 initialRound,
        uint256 increaseAmount
    ) public {
        Balance memory bal = Balance(initialBalance, initialRound);
        BalanceImp b = new BalanceImp(bal);
        if (increaseAmount == 0) {
            vm.expectRevert(ZeroAmount.selector);
            b.increase(increaseAmount);
        } else if (type(uint256).max - increaseAmount < initialBalance) {
            vm.expectRevert();
            b.increase(increaseAmount);
        } else {
            b.increase(increaseAmount);
            checkBal(b, Balance(initialBalance + increaseAmount, type(uint64).max));
        }
    }

    function testReduce(
        uint256 initialBalance,
        uint64 initialRound,
        uint256 reduceAmount,
        uint64 reduceRound
    ) public {
        Balance memory bal = Balance(initialBalance, initialRound);
        BalanceImp b = new BalanceImp(bal);
        if (initialRound <= reduceRound) {
            vm.expectRevert(abi.encodeWithSelector(InsufficientBalance.selector, reduceAmount, 0));
            b.reduce(reduceAmount, reduceRound);
        } else if (reduceAmount > initialBalance) {
            vm.expectRevert(
                abi.encodeWithSelector(InsufficientBalance.selector, reduceAmount, initialBalance)
            );
            b.reduce(reduceAmount, reduceRound);
        } else if (reduceAmount <= initialBalance) {
            b.reduce(reduceAmount, reduceRound);
            checkBal(b, Balance(initialBalance - reduceAmount, initialRound));
        } else {
            revert("Unreachable");
        }
    }

    function testInitiateWithdrawalBoundaries() public {
        testInitiateWithdrawal(0, 0, 0);
        testInitiateWithdrawal(0, 0, 10);
        testInitiateWithdrawal(0, 0, type(uint64).max);
        testInitiateWithdrawal(0, 10, 0);
        testInitiateWithdrawal(0, 10, 5);
        testInitiateWithdrawal(0, 10, 10);
        testInitiateWithdrawal(0, 10, 15);
        testInitiateWithdrawal(0, 10, type(uint64).max);
        testInitiateWithdrawal(0, type(uint64).max, 0);
        testInitiateWithdrawal(0, type(uint64).max, 10);
        testInitiateWithdrawal(0, type(uint64).max, type(uint64).max);
        testInitiateWithdrawal(10, 0, 0);
        testInitiateWithdrawal(10, 0, 10);
        testInitiateWithdrawal(10, 0, type(uint64).max);
        testInitiateWithdrawal(10, 10, 0);
        testInitiateWithdrawal(10, 10, 5);
        testInitiateWithdrawal(10, 10, 10);
        testInitiateWithdrawal(10, 10, 15);
        testInitiateWithdrawal(10, 10, type(uint64).max);
        testInitiateWithdrawal(10, type(uint64).max, 0);
        testInitiateWithdrawal(10, type(uint64).max, 10);
        testInitiateWithdrawal(10, type(uint64).max, type(uint64).max);
        testInitiateWithdrawal(type(uint256).max, 0, 0);
        testInitiateWithdrawal(type(uint256).max, 0, 10);
        testInitiateWithdrawal(type(uint256).max, 0, type(uint64).max);
        testInitiateWithdrawal(type(uint256).max, 10, 0);
        testInitiateWithdrawal(type(uint256).max, 10, 5);
        testInitiateWithdrawal(type(uint256).max, 10, 10);
        testInitiateWithdrawal(type(uint256).max, 10, 15);
        testInitiateWithdrawal(type(uint256).max, 10, type(uint64).max);
        testInitiateWithdrawal(type(uint256).max, type(uint64).max, 0);
        testInitiateWithdrawal(type(uint256).max, type(uint64).max, 10);
        testInitiateWithdrawal(type(uint256).max, type(uint64).max, type(uint64).max);
    }

    function testInitiateWithdrawal(
        uint256 initialBalance,
        uint64 initialRound,
        uint64 withdrawalRound
    ) public {
        Balance memory bal = Balance(initialBalance, initialRound);
        BalanceImp b = new BalanceImp(bal);
        if (initialBalance == 0) {
            vm.expectRevert(ZeroAmount.selector);
            b.initiateWithdrawal(withdrawalRound);
        } else if (withdrawalRound == type(uint64).max) {
            vm.expectRevert(WithdrawalMaxRound.selector);
            b.initiateWithdrawal(withdrawalRound);
        } else if (initialRound != type(uint64).max) {
            vm.expectRevert(WithdrawalInProgress.selector);
            b.initiateWithdrawal(withdrawalRound);
        } else {
            b.initiateWithdrawal(withdrawalRound);
            checkBal(b, Balance(initialBalance, withdrawalRound));
        }
    }

    function testFinalizeWithdrawal(
        uint256 initialBalance,
        uint64 initialRound,
        uint64 withdrawalRound
    ) public {
        Balance memory bal = Balance(initialBalance, initialRound);
        BalanceImp b = new BalanceImp(bal);
        if (withdrawalRound == type(uint64).max) {
            vm.expectRevert(WithdrawalMaxRound.selector);
            b.finalizeWithdrawal(withdrawalRound);
        } else if (initialBalance == 0) {
            vm.expectRevert(NothingToWithdraw.selector);
            b.finalizeWithdrawal(withdrawalRound);
        } else if (withdrawalRound < initialRound) {
            vm.expectRevert(NothingToWithdraw.selector);
            b.finalizeWithdrawal(withdrawalRound);
        } else {
            b.finalizeWithdrawal(withdrawalRound);
            checkBal(b, Balance(0, initialRound));
        }
    }
}

contract InvariantBalance is Test {
    BalanceImp balanceImp;

    function setUp() public {
        balanceImp = new BalanceImp(Balance(0, 0));
    }

    function invariantBalanceWithdrawableSum() public {
        uint64 randRound = uint64(
            uint256(keccak256(abi.encode(msg.sender, block.timestamp, "round")))
        );
        (uint256 bal, ) = balanceImp.bal();
        // withdrawable balance + available balance should always equal internal balance
        assertEq(
            balanceImp.balanceAtRound(randRound) + balanceImp.withdrawableBalanceAtRound(randRound),
            bal
        );
    }
}
