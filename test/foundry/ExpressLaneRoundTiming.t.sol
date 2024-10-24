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

    RoundTimingInfo negativeInfo =
        RoundTimingInfo({
            offsetTimestamp: -1000,
            roundDurationSeconds: 100,
            auctionClosingSeconds: 25,
            reserveSubmissionSeconds: 20
        });

    function testCurrentRound() public {
        RoundTimingInfoImp ri = new RoundTimingInfoImp(info);
        uint64 offset = uint64(info.offsetTimestamp);

        vm.warp(offset - 500);
        assertEq(ri.currentRound(), 0, "Long before offset");
        vm.warp(offset - 1);
        assertEq(ri.currentRound(), 0, "Before offset");
        vm.warp(offset);
        assertEq(ri.currentRound(), 0, "At offset");
        vm.warp(offset + 1);
        assertEq(ri.currentRound(), 0, "After offset");
        vm.warp(offset + info.roundDurationSeconds - 1);
        assertEq(ri.currentRound(), 0, "Before round 1");
        vm.warp(offset + info.roundDurationSeconds);
        assertEq(ri.currentRound(), 1, "At round 1");
        vm.warp(offset + info.roundDurationSeconds + 1);
        assertEq(ri.currentRound(), 1, "At round 1");
        vm.warp(offset + 5 * info.roundDurationSeconds);
        assertEq(ri.currentRound(), 5, "At round 5");

        RoundTimingInfoImp mri = new RoundTimingInfoImp(matchInfo);
        uint64 matchOffset = uint64(matchInfo.offsetTimestamp);
        vm.warp(matchOffset + matchInfo.roundDurationSeconds);
        assertEq(mri.currentRound(), 1, "mri at round 1");

        RoundTimingInfoImp nri = new RoundTimingInfoImp(negativeInfo);
        uint64 negativeOffset = uint64(-negativeInfo.offsetTimestamp);
        vm.warp(0);
        assertEq(nri.currentRound(), 10, "Before offset");
        vm.warp(1);
        assertEq(nri.currentRound(), 10, "At offset");
        vm.warp(info.roundDurationSeconds - 1);
        assertEq(nri.currentRound(), 10, "Before round 1");
        vm.warp(info.roundDurationSeconds);
        assertEq(nri.currentRound(), 11, "At round 1");
        vm.warp(info.roundDurationSeconds + 1);
        assertEq(nri.currentRound(), 11, "At round 1");
        vm.warp(5 * info.roundDurationSeconds);
        assertEq(nri.currentRound(), 15, "At round 5");
        vm.warp(negativeOffset + info.roundDurationSeconds);
        assertEq(nri.currentRound(), 21, "At round 21");
    }

    function testIsAuctionClosed() public {
        RoundTimingInfoImp ri = new RoundTimingInfoImp(info);
        uint64 offset = uint64(info.offsetTimestamp);

        vm.warp(offset - 1);
        assertFalse(ri.isAuctionRoundClosed(), "Before offset");
        vm.warp(offset);
        assertFalse(ri.isAuctionRoundClosed(), "At offset");
        vm.warp(offset + info.roundDurationSeconds - info.auctionClosingSeconds - 1);
        assertFalse(ri.isAuctionRoundClosed(), "Before close");
        vm.warp(offset + info.roundDurationSeconds - info.auctionClosingSeconds);
        assertTrue(ri.isAuctionRoundClosed(), "At close");
        vm.warp(offset + info.roundDurationSeconds - info.auctionClosingSeconds + 1);
        assertTrue(ri.isAuctionRoundClosed(), "After close");
        vm.warp(offset + info.roundDurationSeconds - 1);
        assertTrue(ri.isAuctionRoundClosed(), "Before round start");
        vm.warp(offset + info.roundDurationSeconds);
        assertFalse(ri.isAuctionRoundClosed(), "At round start");
        vm.warp(offset + 2 * info.roundDurationSeconds - info.auctionClosingSeconds - 1);
        assertFalse(ri.isAuctionRoundClosed(), "Before next round start");
        vm.warp(offset + 2 * info.roundDurationSeconds - info.auctionClosingSeconds);
        assertTrue(ri.isAuctionRoundClosed(), "At round start");
        vm.warp(offset + 2 * info.roundDurationSeconds);
        assertFalse(ri.isAuctionRoundClosed(), "At next round");

        RoundTimingInfoImp mri = new RoundTimingInfoImp(matchInfo);
        uint64 matchOffset = uint64(matchInfo.offsetTimestamp);
        vm.warp(matchOffset + info.roundDurationSeconds - info.auctionClosingSeconds);
        assertTrue(mri.isAuctionRoundClosed(), "mri close");

        RoundTimingInfoImp nri = new RoundTimingInfoImp(negativeInfo);
        uint64 negativeOffset = uint64(-negativeInfo.offsetTimestamp);
        vm.warp(0);
        assertFalse(nri.isAuctionRoundClosed(), "At offset");
        vm.warp(negativeOffset + info.roundDurationSeconds - info.auctionClosingSeconds - 1);
        assertFalse(nri.isAuctionRoundClosed(), "Before close");
        vm.warp(negativeOffset + info.roundDurationSeconds - info.auctionClosingSeconds);
        assertTrue(nri.isAuctionRoundClosed(), "At close");
        vm.warp(negativeOffset + info.roundDurationSeconds - info.auctionClosingSeconds + 1);
        assertTrue(nri.isAuctionRoundClosed(), "After close");
        vm.warp(negativeOffset + info.roundDurationSeconds - 1);
        assertTrue(nri.isAuctionRoundClosed(), "Before round start");
        vm.warp(negativeOffset + info.roundDurationSeconds);
        assertFalse(nri.isAuctionRoundClosed(), "At round start");
        vm.warp(negativeOffset + 2 * info.roundDurationSeconds - info.auctionClosingSeconds - 1);
        assertFalse(nri.isAuctionRoundClosed(), "Before next round start");
        vm.warp(negativeOffset + 2 * info.roundDurationSeconds - info.auctionClosingSeconds);
        assertTrue(nri.isAuctionRoundClosed(), "At round start");
        vm.warp(negativeOffset + 2 * info.roundDurationSeconds);
        assertFalse(nri.isAuctionRoundClosed(), "At next round");
    }

    function testIsReserveBlackout() public {
        RoundTimingInfoImp ri = new RoundTimingInfoImp(info);
        uint64 offset = uint64(info.offsetTimestamp);

        vm.warp(offset - 1);
        assertFalse(ri.isReserveBlackout(0), "Before offset");
        assertFalse(ri.isReserveBlackout(1), "Before offset");
        assertFalse(ri.isReserveBlackout(2), "Before offset");
        vm.warp(offset);
        assertFalse(ri.isReserveBlackout(0), "At offset");
        assertFalse(ri.isReserveBlackout(1), "At offset");
        assertFalse(ri.isReserveBlackout(2), "At offset");
        vm.warp(
            offset +
                info.roundDurationSeconds -
                info.auctionClosingSeconds -
                info.reserveSubmissionSeconds -
                1
        );
        assertFalse(ri.isReserveBlackout(0), "Before blackout");
        assertFalse(ri.isReserveBlackout(1), "Before blackout");
        assertFalse(ri.isReserveBlackout(2), "Before blackout");
        vm.warp(
            offset +
                info.roundDurationSeconds -
                info.auctionClosingSeconds -
                info.reserveSubmissionSeconds
        );
        assertTrue(ri.isReserveBlackout(0), "At blackout 0");
        assertFalse(ri.isReserveBlackout(1), "At blackout 1");
        assertFalse(ri.isReserveBlackout(2), "At blackout 2");
        vm.warp(
            offset +
                info.roundDurationSeconds -
                info.auctionClosingSeconds -
                info.reserveSubmissionSeconds +
                1
        );
        assertTrue(ri.isReserveBlackout(0), "After blackout");
        assertFalse(ri.isReserveBlackout(1), "After blackout");
        assertFalse(ri.isReserveBlackout(2), "After blackout");
        vm.warp(offset + info.roundDurationSeconds - 1);
        assertTrue(ri.isReserveBlackout(0), "Before next round");
        assertFalse(ri.isReserveBlackout(1), "Before next round");
        assertFalse(ri.isReserveBlackout(2), "Before next round");
        vm.warp(offset + info.roundDurationSeconds);
        assertFalse(ri.isReserveBlackout(0), "At next round");
        assertFalse(ri.isReserveBlackout(1), "At next round");
        assertFalse(ri.isReserveBlackout(2), "At next round");
        vm.warp(
            offset +
                2 *
                info.roundDurationSeconds -
                info.auctionClosingSeconds -
                info.reserveSubmissionSeconds
        );
        assertTrue(ri.isReserveBlackout(0), "At next reserve submission deadline");
        assertTrue(ri.isReserveBlackout(1), "At next reserve submission deadline");
        assertFalse(ri.isReserveBlackout(2), "At next reserve submission deadline");

        RoundTimingInfoImp mri = new RoundTimingInfoImp(matchInfo);
        uint64 matchOffset = uint64(matchInfo.offsetTimestamp);
        vm.warp(matchOffset + matchInfo.roundDurationSeconds);
        assertTrue(mri.isReserveBlackout(0), "mri at next round");
        assertTrue(mri.isReserveBlackout(1), "mri at next round");
        assertFalse(mri.isReserveBlackout(2), "mri at next round");

        RoundTimingInfoImp nri = new RoundTimingInfoImp(negativeInfo);
        uint64 negativeOffset = uint64(-negativeInfo.offsetTimestamp);
        vm.warp(negativeOffset - 1);
        assertTrue(nri.isReserveBlackout(19), "Before offset");
        assertFalse(nri.isReserveBlackout(20), "Before offset");
        assertFalse(nri.isReserveBlackout(21), "Before offset");
        vm.warp(negativeOffset);
        assertFalse(nri.isReserveBlackout(19), "At offset");
        assertFalse(nri.isReserveBlackout(20), "At offset");
        assertFalse(nri.isReserveBlackout(21), "At offset");
        vm.warp(
            negativeOffset +
                info.roundDurationSeconds -
                info.auctionClosingSeconds -
                info.reserveSubmissionSeconds -
                1
        );
        assertFalse(nri.isReserveBlackout(19), "Before blackout");
        assertFalse(nri.isReserveBlackout(20), "Before blackout");
        assertFalse(nri.isReserveBlackout(21), "Before blackout");
        vm.warp(
            negativeOffset +
                info.roundDurationSeconds -
                info.auctionClosingSeconds -
                info.reserveSubmissionSeconds
        );
        assertTrue(nri.isReserveBlackout(19), "At blackout 19");
        assertTrue(nri.isReserveBlackout(20), "At blackout 20");
        assertFalse(nri.isReserveBlackout(21), "At blackout 21");
        vm.warp(
            negativeOffset +
                info.roundDurationSeconds -
                info.auctionClosingSeconds -
                info.reserveSubmissionSeconds +
                1
        );
        assertTrue(nri.isReserveBlackout(19), "After blackout");
        assertTrue(nri.isReserveBlackout(20), "After blackout");
        assertFalse(nri.isReserveBlackout(21), "After blackout");
        vm.warp(negativeOffset + info.roundDurationSeconds - info.auctionClosingSeconds - 1);
        assertTrue(nri.isReserveBlackout(19), "Before auction closing");
        assertTrue(nri.isReserveBlackout(20), "Before auction closing");
        assertFalse(nri.isReserveBlackout(21), "Before auction closing");
        vm.warp(negativeOffset + info.roundDurationSeconds - info.auctionClosingSeconds);
        assertTrue(nri.isReserveBlackout(19), "At auction closing");
        assertTrue(nri.isReserveBlackout(20), "At auction closing");
        assertFalse(nri.isReserveBlackout(21), "At auction closing");
        vm.warp(negativeOffset + info.roundDurationSeconds - info.auctionClosingSeconds + 1);
        assertTrue(nri.isReserveBlackout(19), "After auction closing");
        assertTrue(nri.isReserveBlackout(20), "After auction closing");
        assertFalse(nri.isReserveBlackout(21), "After auction closing");
        vm.warp(negativeOffset + info.roundDurationSeconds - 1);
        assertTrue(nri.isReserveBlackout(19), "Before next round");
        assertTrue(nri.isReserveBlackout(20), "Before next round");
        assertFalse(nri.isReserveBlackout(21), "Before next round");
        vm.warp(negativeOffset + info.roundDurationSeconds);
        assertFalse(nri.isReserveBlackout(19), "At next round");
        assertFalse(nri.isReserveBlackout(20), "At next round");
        assertFalse(nri.isReserveBlackout(21), "At next round");
        vm.warp(
            negativeOffset +
                2 *
                info.roundDurationSeconds -
                info.auctionClosingSeconds -
                info.reserveSubmissionSeconds
        );
        assertTrue(nri.isReserveBlackout(19), "At next reserve submission deadline");
        assertTrue(nri.isReserveBlackout(20), "At next reserve submission deadline");
        assertTrue(nri.isReserveBlackout(21), "At next reserve submission deadline");
    }

    function testRoundTimestamps() public {
        RoundTimingInfoImp ri = new RoundTimingInfoImp(info);
        uint64 offset = uint64(info.offsetTimestamp);

        (uint64 start, uint64 end) = ri.roundTimestamps(0);
        assertEq(start, offset);
        assertEq(end, offset + 1 * info.roundDurationSeconds - 1);
        (start, end) = ri.roundTimestamps(1);
        assertEq(start, offset + 1 * info.roundDurationSeconds);
        assertEq(end, offset + 2 * info.roundDurationSeconds - 1);
        (start, end) = ri.roundTimestamps(2);
        assertEq(start, offset + 2 * info.roundDurationSeconds);
        assertEq(end, offset + 3 * info.roundDurationSeconds - 1);
        (start, end) = ri.roundTimestamps(11057);
        assertEq(start, offset + 11057 * info.roundDurationSeconds);
        assertEq(end, offset + 11058 * info.roundDurationSeconds - 1);

        RoundTimingInfoImp nri = new RoundTimingInfoImp(negativeInfo);
        vm.expectRevert(
            abi.encodeWithSelector(NegativeRoundStart.selector, negativeInfo.offsetTimestamp)
        );
        nri.roundTimestamps(0);
        vm.expectRevert(
            abi.encodeWithSelector(
                NegativeRoundStart.selector,
                negativeInfo.offsetTimestamp + int64(negativeInfo.roundDurationSeconds)
            )
        );
        nri.roundTimestamps(1);
        vm.expectRevert(
            abi.encodeWithSelector(NegativeRoundStart.selector, negativeInfo.offsetTimestamp)
        );
        nri.roundTimestamps(0);
        vm.expectRevert(
            abi.encodeWithSelector(
                NegativeRoundStart.selector,
                negativeInfo.offsetTimestamp + int64(negativeInfo.roundDurationSeconds * 9)
            )
        );
        nri.roundTimestamps(9);

        (start, end) = nri.roundTimestamps(10);
        assertEq(start, 0);
        assertEq(end, negativeInfo.roundDurationSeconds - 1);
        (start, end) = nri.roundTimestamps(11);
        assertEq(start, negativeInfo.roundDurationSeconds);
        assertEq(end, (2 * negativeInfo.roundDurationSeconds) - 1);
        (start, end) = nri.roundTimestamps(21);
        assertEq(start, (negativeInfo.roundDurationSeconds * 11));
        assertEq(end, (12 * negativeInfo.roundDurationSeconds) - 1);
    }
}
