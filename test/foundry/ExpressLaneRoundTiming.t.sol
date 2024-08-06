// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/express-lane-auction/RoundTimingInfo.sol";

contract RoundTimingInfoImp {
    using RoundTimingInfoLib for RoundTimingInfo;

    RoundTimingInfo public timingInfo;

    constructor(RoundTimingInfo memory r) {
        timingInfo = r;
    }

    function currentRound() public view returns (uint64) {
        return timingInfo.currentRound();
    }

    function isAuctionRoundClosed() public view returns (bool) {
        return timingInfo.isAuctionRoundClosed();
    }

    function timeIntoRound() public view returns (uint64) {
        return timingInfo.timeIntoRound();
    }

    function isReserveBlackout(uint64 latestResolvedRound) public view returns (bool) {
        return timingInfo.isReserveBlackout(latestResolvedRound);
    }

    function roundTimestamps(uint64 round) public view returns (uint64, uint64) {
        return timingInfo.roundTimestamps(round);
    }
}

contract ExpressLaneRoundTimingTest is Test {
    RoundTimingInfo info =
        RoundTimingInfo({
            offsetTimestamp: 1000,
            roundDurationSeconds: 100,
            auctionClosingSeconds: 25,
            reserveSubmissionSeconds: 20
        });

    RoundTimingInfo matchInfo =
        RoundTimingInfo({
            offsetTimestamp: 1000,
            roundDurationSeconds: 100,
            auctionClosingSeconds: 25,
            reserveSubmissionSeconds: 75
        });

    function testCurrentRound() public {
        RoundTimingInfoImp ri = new RoundTimingInfoImp(info);

        vm.warp(info.offsetTimestamp - 500);
        assertEq(ri.currentRound(), 0, "Long before offset");
        vm.warp(info.offsetTimestamp - 1);
        assertEq(ri.currentRound(), 0, "Before offset");
        vm.warp(info.offsetTimestamp);
        assertEq(ri.currentRound(), 0, "At offset");
        vm.warp(info.offsetTimestamp + 1);
        assertEq(ri.currentRound(), 0, "After offset");
        vm.warp(info.offsetTimestamp + info.roundDurationSeconds - 1);
        assertEq(ri.currentRound(), 0, "Before round 1");
        vm.warp(info.offsetTimestamp + info.roundDurationSeconds);
        assertEq(ri.currentRound(), 1, "At round 1");
        vm.warp(info.offsetTimestamp + info.roundDurationSeconds + 1);
        assertEq(ri.currentRound(), 1, "At round 1");
        vm.warp(info.offsetTimestamp + 5 * info.roundDurationSeconds);
        assertEq(ri.currentRound(), 5, "At round 5");

        RoundTimingInfoImp mri = new RoundTimingInfoImp(matchInfo);
        vm.warp(matchInfo.offsetTimestamp + matchInfo.roundDurationSeconds);
        assertEq(mri.currentRound(), 1, "mri at round 1");
    }

    function testIsAuctionClosed() public {
        RoundTimingInfoImp ri = new RoundTimingInfoImp(info);

        vm.warp(info.offsetTimestamp - 1);
        assertFalse(ri.isAuctionRoundClosed(), "Before offset");
        vm.warp(info.offsetTimestamp);
        assertFalse(ri.isAuctionRoundClosed(), "At offset");
        vm.warp(info.offsetTimestamp + info.roundDurationSeconds - info.auctionClosingSeconds - 1);
        assertFalse(ri.isAuctionRoundClosed(), "Before close");
        vm.warp(info.offsetTimestamp + info.roundDurationSeconds - info.auctionClosingSeconds);
        assertTrue(ri.isAuctionRoundClosed(), "At close");
        vm.warp(info.offsetTimestamp + info.roundDurationSeconds - info.auctionClosingSeconds + 1);
        assertTrue(ri.isAuctionRoundClosed(), "After close");
        vm.warp(info.offsetTimestamp + info.roundDurationSeconds - 1);
        assertTrue(ri.isAuctionRoundClosed(), "Before round start");
        vm.warp(info.offsetTimestamp + info.roundDurationSeconds);
        assertFalse(ri.isAuctionRoundClosed(), "At round start");
        vm.warp(
            info.offsetTimestamp + 2 * info.roundDurationSeconds - info.auctionClosingSeconds - 1
        );
        assertFalse(ri.isAuctionRoundClosed(), "Before next round start");
        vm.warp(info.offsetTimestamp + 2 * info.roundDurationSeconds - info.auctionClosingSeconds);
        assertTrue(ri.isAuctionRoundClosed(), "At round start");
        vm.warp(info.offsetTimestamp + 2 * info.roundDurationSeconds);
        assertFalse(ri.isAuctionRoundClosed(), "At next round");

        RoundTimingInfoImp mri = new RoundTimingInfoImp(matchInfo);
        vm.warp(info.offsetTimestamp + info.roundDurationSeconds - info.auctionClosingSeconds);
        assertTrue(mri.isAuctionRoundClosed(), "mri close");
    }

    function testTimeIntoRound() public {
        RoundTimingInfoImp ri = new RoundTimingInfoImp(info);

        vm.warp(info.offsetTimestamp - 1);
        vm.expectRevert();
        ri.timeIntoRound();
        vm.warp(info.offsetTimestamp);
        assertEq(ri.timeIntoRound(), 0, "At offset");
        vm.warp(info.offsetTimestamp + 1);
        assertEq(ri.timeIntoRound(), 1, "At offset");
        vm.warp(info.offsetTimestamp + 13);
        assertEq(ri.timeIntoRound(), 13, "After offset");
        vm.warp(info.offsetTimestamp + info.roundDurationSeconds);
        assertEq(ri.timeIntoRound(), 0, "Next round");
        vm.warp(info.offsetTimestamp + info.roundDurationSeconds + 14);
        assertEq(ri.timeIntoRound(), 14, "After next round");
        vm.warp(info.offsetTimestamp + 5 * info.roundDurationSeconds + 17);
        assertEq(ri.timeIntoRound(), 17, "After next round");

        RoundTimingInfoImp mri = new RoundTimingInfoImp(matchInfo);
        vm.warp(matchInfo.offsetTimestamp + matchInfo.roundDurationSeconds + 14);
        assertEq(mri.timeIntoRound(), 14, "mri after next round");
    }

    function testIsReserveBlackout() public {
        RoundTimingInfoImp ri = new RoundTimingInfoImp(info);

        vm.warp(info.offsetTimestamp - 1);
        assertFalse(ri.isReserveBlackout(0), "Before offset");
        assertFalse(ri.isReserveBlackout(1), "Before offset");
        assertFalse(ri.isReserveBlackout(2), "Before offset");
        vm.warp(info.offsetTimestamp - 1);
        assertFalse(ri.isReserveBlackout(0), "At offset");
        assertFalse(ri.isReserveBlackout(1), "At offset");
        assertFalse(ri.isReserveBlackout(2), "At offset");
        vm.warp(
            info.offsetTimestamp +
                info.roundDurationSeconds -
                info.auctionClosingSeconds -
                info.reserveSubmissionSeconds -
                1
        );
        assertFalse(ri.isReserveBlackout(0), "Before blackout");
        assertFalse(ri.isReserveBlackout(1), "Before blackout");
        assertFalse(ri.isReserveBlackout(2), "Before blackout");
        vm.warp(
            info.offsetTimestamp +
                info.roundDurationSeconds -
                info.auctionClosingSeconds -
                info.reserveSubmissionSeconds
        );
        assertTrue(ri.isReserveBlackout(0), "At blackout 0");
        assertFalse(ri.isReserveBlackout(1), "At blackout 1");
        assertFalse(ri.isReserveBlackout(2), "At blackout 2");
        vm.warp(
            info.offsetTimestamp +
                info.roundDurationSeconds -
                info.auctionClosingSeconds -
                info.reserveSubmissionSeconds +
                1
        );
        assertTrue(ri.isReserveBlackout(0), "After blackout");
        assertFalse(ri.isReserveBlackout(1), "After blackout");
        assertFalse(ri.isReserveBlackout(2), "After blackout");
        vm.warp(info.offsetTimestamp + info.roundDurationSeconds - 1);
        assertTrue(ri.isReserveBlackout(0), "Before next round");
        assertFalse(ri.isReserveBlackout(1), "Before next round");
        assertFalse(ri.isReserveBlackout(2), "Before next round");
        vm.warp(info.offsetTimestamp + info.roundDurationSeconds);
        assertFalse(ri.isReserveBlackout(0), "At next round");
        assertFalse(ri.isReserveBlackout(1), "At next round");
        assertFalse(ri.isReserveBlackout(2), "At next round");
        vm.warp(
            info.offsetTimestamp +
                2 *
                info.roundDurationSeconds -
                info.auctionClosingSeconds -
                info.reserveSubmissionSeconds
        );
        assertTrue(ri.isReserveBlackout(0), "At next reserve submission deadline");
        assertTrue(ri.isReserveBlackout(1), "At next reserve submission deadline");
        assertFalse(ri.isReserveBlackout(2), "At next reserve submission deadline");

        RoundTimingInfoImp mri = new RoundTimingInfoImp(matchInfo);
        vm.warp(matchInfo.offsetTimestamp + matchInfo.roundDurationSeconds);
        assertTrue(mri.isReserveBlackout(0), "mri at next round");
        assertTrue(mri.isReserveBlackout(1), "mri at next round");
        assertFalse(mri.isReserveBlackout(2), "mri at next round");
    }

    function testRoundTimestamps() public {
        RoundTimingInfoImp ri = new RoundTimingInfoImp(info);

        (uint64 start, uint64 end) = ri.roundTimestamps(0);
        assertEq(start, info.offsetTimestamp);
        assertEq(end, info.offsetTimestamp + 1 * info.roundDurationSeconds - 1);
        (start, end) = ri.roundTimestamps(1);
        assertEq(start, info.offsetTimestamp + 1 * info.roundDurationSeconds);
        assertEq(end, info.offsetTimestamp + 2 * info.roundDurationSeconds - 1);
        (start, end) = ri.roundTimestamps(2);
        assertEq(start, info.offsetTimestamp + 2 * info.roundDurationSeconds);
        assertEq(end, info.offsetTimestamp + 3 * info.roundDurationSeconds - 1);
        (start, end) = ri.roundTimestamps(11057);
        assertEq(start, info.offsetTimestamp + 11057 * info.roundDurationSeconds);
        assertEq(end, info.offsetTimestamp + 11058 * info.roundDurationSeconds - 1);
    }
}
