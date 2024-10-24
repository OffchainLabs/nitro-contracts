// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/express-lane-auction/ELCRound.sol";

contract LatestELCRoundsImp {
    using LatestELCRoundsLib for ELCRound[2];

    ELCRound[2] public rounds;

    constructor(ELCRound[2] memory r) {
        rounds[0] = r[0];
        rounds[1] = r[1];
    }

    function latestELCRound() public view returns (ELCRound memory, uint8) {
        return rounds.latestELCRound();
    }

    function resolvedRound(uint64 round) public view returns (ELCRound memory) {
        return rounds.resolvedRound(round);
    }

    function setResolvedRound(uint64 round, address expressLaneController) public {
        rounds.setResolvedRound(round, expressLaneController);
    }
}

contract ExpressLaneELCRoundTest is Test {
    function assertEq(ELCRound memory actual, ELCRound memory expected) internal {
        assertEq(actual.expressLaneController, expected.expressLaneController, "elc address");
        assertEq(actual.round, expected.round, "elc round");
    }

    address addr0 = vm.addr(1);
    address addr1 = vm.addr(2);

    function testLatestELCRound() public {
        ELCRound[2] memory rounds;
        LatestELCRoundsImp li = new LatestELCRoundsImp(rounds);
        (ELCRound memory r, uint8 i) = li.latestELCRound();
        assertEq(r, rounds[0]);
        assertEq(i, 0);

        rounds[0] = ELCRound({expressLaneController: addr0, round: 1});
        li = new LatestELCRoundsImp(rounds);
        (r, i) = li.latestELCRound();
        assertEq(r, rounds[0]);
        assertEq(i, 0);

        rounds[1] = ELCRound({expressLaneController: addr1, round: 2});
        li = new LatestELCRoundsImp(rounds);
        (r, i) = li.latestELCRound();
        assertEq(r, rounds[1]);
        assertEq(i, 1);

        rounds[0] = ELCRound({expressLaneController: addr1, round: 10});
        li = new LatestELCRoundsImp(rounds);
        (r, i) = li.latestELCRound();
        assertEq(r, rounds[0]);
        assertEq(i, 0);
    }

    function testResolvedRound() public {
        ELCRound[2] memory rounds;
        LatestELCRoundsImp li = new LatestELCRoundsImp(rounds);
        ELCRound memory r = li.resolvedRound(0);
        assertEq(r, rounds[0]);

        rounds[0] = ELCRound({expressLaneController: addr0, round: 1});
        li = new LatestELCRoundsImp(rounds);
        r = li.resolvedRound(0);
        assertEq(r, rounds[1]);
        r = li.resolvedRound(1);
        assertEq(r, rounds[0]);
        vm.expectRevert(abi.encodeWithSelector(RoundNotResolved.selector, 10));
        li.resolvedRound(10);

        rounds[1] = ELCRound({expressLaneController: addr1, round: 3});
        li = new LatestELCRoundsImp(rounds);
        vm.expectRevert(abi.encodeWithSelector(RoundNotResolved.selector, 0));
        li.resolvedRound(0);
        r = li.resolvedRound(1);
        assertEq(r, rounds[0]);
        vm.expectRevert(abi.encodeWithSelector(RoundNotResolved.selector, 2));
        li.resolvedRound(2);
        r = li.resolvedRound(3);
        assertEq(r, rounds[1]);
        vm.expectRevert(abi.encodeWithSelector(RoundNotResolved.selector, 10));
        li.resolvedRound(10);
    }

    function getELCRound(LatestELCRoundsImp li, uint8 index)
        internal
        view
        returns (ELCRound memory)
    {
        (address elc, uint64 round) = li.rounds(index);
        return ELCRound(elc, round);
    }

    function testSetResolvedRound() public {
        ELCRound[2] memory rounds;
        LatestELCRoundsImp li = new LatestELCRoundsImp(rounds);
        vm.expectRevert(abi.encodeWithSelector(RoundAlreadyResolved.selector, 0));
        li.setResolvedRound(0, addr0);

        li.setResolvedRound(1, addr0);
        assertEq(getELCRound(li, 0), rounds[0]);
        assertEq(getELCRound(li, 1), ELCRound(addr0, 1));

        vm.expectRevert(abi.encodeWithSelector(RoundAlreadyResolved.selector, 0));
        li.setResolvedRound(0, addr0);
        vm.expectRevert(abi.encodeWithSelector(RoundAlreadyResolved.selector, 1));
        li.setResolvedRound(1, addr0);

        li.setResolvedRound(2, addr1);
        assertEq(getELCRound(li, 0), ELCRound(addr1, 2));
        assertEq(getELCRound(li, 1), ELCRound(addr0, 1));

        vm.expectRevert(abi.encodeWithSelector(RoundAlreadyResolved.selector, 0));
        li.setResolvedRound(0, addr0);
        vm.expectRevert(abi.encodeWithSelector(RoundAlreadyResolved.selector, 1));
        li.setResolvedRound(1, addr0);
        vm.expectRevert(abi.encodeWithSelector(RoundAlreadyResolved.selector, 2));
        li.setResolvedRound(2, addr0);

        li.setResolvedRound(4, vm.addr(4));
        assertEq(getELCRound(li, 0), ELCRound(addr1, 2));
        assertEq(getELCRound(li, 1), ELCRound(vm.addr(4), 4));

        li.setResolvedRound(10, vm.addr(10));
        assertEq(getELCRound(li, 0), ELCRound(vm.addr(10), 10));
        assertEq(getELCRound(li, 1), ELCRound(vm.addr(4), 4));
    }
}

contract ExpressLaneELCRoundInvariant is Test {
    LatestELCRoundsImp li;

    function setUp() public {
        ELCRound[2] memory rounds;
        li = new LatestELCRoundsImp(rounds);
    }

    function invariantRoundsNeverSame() public {
        (, uint64 round0) = li.rounds(0);
        (, uint64 round1) = li.rounds(1);
        assertTrue((round0 == 0 && round1 == 0) || round0 != round1);
    }
}
