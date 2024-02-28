// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/mocks/SimpleDelayBufferable.sol";
import "../../src/bridge/Messages.sol";
import {L2_MSG} from "../../src/libraries/MessageTypes.sol";

contract SimpleDelayBufferableTest is Test {
    ISequencerInbox.MaxTimeVariation maxTimeVariation = ISequencerInbox.MaxTimeVariation({
        delayBlocks: 24 * 60 * 60 / 12,
        futureBlocks: 32 * 2,
        delaySeconds: 24 * 60 * 60,
        futureSeconds: 32 * 2 * 12
    });
    IDelayBufferable.ReplenishRate replenishRate = IDelayBufferable.ReplenishRate({
        secondsPerPeriod: 1,
        blocksPerPeriod: 1,
        periodSeconds: 14,
        periodBlocks: 14
    });
    IDelayBufferable.Config configBufferable = IDelayBufferable.Config({
        thresholdBlocks: 60 * 60 * 2 / 12,
        thresholdSeconds: 60 * 60 * 2,
        maxBufferBlocks: 24 * 60 * 60 / 12 * 2,
        maxBufferSeconds: 24 * 60 * 60 * 2
    });
    IDelayBufferable.Config configNotBufferable = IDelayBufferable.Config({
        thresholdSeconds: type(uint64).max,
        thresholdBlocks: type(uint64).max,
        maxBufferSeconds: 0,
        maxBufferBlocks: 0
    });
    uint64 constant SECOND_PER_SLOT = 12;
    Messages.Message message = Messages.Message({
        kind: L2_MSG,
        sender: address(1),
        blockNumber: uint64(block.number),
        timestamp: uint64(block.timestamp),
        inboxSeqNum: uint256(1),
        baseFeeL1: uint256(1),
        messageDataHash: bytes32(0)
    });

    function testSyncProof() public {
        SimpleDelayBufferable delayBufferable = new SimpleDelayBufferable(
            maxTimeVariation,
            replenishRate,
            configBufferable
        );

        bytes32 beforeDelayedAcc = bytes32(0);
        bytes32 delayedAcc =
            Messages.accumulateInboxMessage(beforeDelayedAcc, Messages.messageHash(message));
        bytes32 beforeAcc = bytes32(0);
        bytes32 dataHash = bytes32(0);

        Messages.InboxAccPreimage memory preimage = Messages.InboxAccPreimage({
            beforeAcc: beforeAcc,
            dataHash: dataHash,
            delayedAcc: delayedAcc
        });
        // first batch reads delayed message
        bytes32 acc = Messages.accumulateSequencerInbox(preimage);

        // initially message if proven with no delay
        bool isValidSyncProof =
            delayBufferable.isValidSyncProof_(beforeDelayedAcc, message, acc, preimage);
        assertEq(isValidSyncProof, true);

        // sanity check
        isValidSyncProof =
            delayBufferable.isValidSyncProof_(beforeDelayedAcc, message, bytes32(0), preimage);
        assertEq(isValidSyncProof, false);

        // (blockNumber, timestamp)

        // (0, 0) -> (0, thresholdSeconds)
        vm.warp(block.timestamp + configBufferable.thresholdSeconds);
        isValidSyncProof = delayBufferable.isValidSyncProof_(beforeDelayedAcc, message, acc, preimage);
        assertEq(isValidSyncProof, true);

        // (0, thresholdSeconds) -> (0, thresholdSeconds + 1)
        vm.warp(block.timestamp + 1);
        isValidSyncProof = delayBufferable.isValidSyncProof_(beforeDelayedAcc, message, acc, preimage);
        assertEq(isValidSyncProof, false);

        // (0, thresholdSeconds + 1) -> (0, 0)
        vm.warp(block.timestamp - 1 - configBufferable.thresholdSeconds);
        isValidSyncProof = delayBufferable.isValidSyncProof_(beforeDelayedAcc, message, acc, preimage);
        assertEq(isValidSyncProof, true);

        // (0, 0) -> (thresholdBlocks, 0)
        vm.roll(block.number + configBufferable.thresholdBlocks);
        isValidSyncProof = delayBufferable.isValidSyncProof_(beforeDelayedAcc, message, acc, preimage);
        assertEq(isValidSyncProof, true);

        // (thresholdBlocks, 0) -> (thresholdBlocks + 1, 0)
        vm.roll(block.number + 1);
        isValidSyncProof = delayBufferable.isValidSyncProof_(beforeDelayedAcc, message, acc, preimage);
        assertEq(isValidSyncProof, false);

        // (thresholdBlocks + 1, 0) -> (0, 0)
        vm.roll(block.number - 1 - configBufferable.thresholdBlocks);
        isValidSyncProof = delayBufferable.isValidSyncProof_(beforeDelayedAcc, message, acc, preimage);
        assertEq(isValidSyncProof, true);

        // (0, 0) -> (thresholdBlocks, thresholdSeconds)
        vm.roll(block.number + configBufferable.thresholdBlocks);
        vm.warp(block.timestamp + configBufferable.thresholdSeconds);
        isValidSyncProof = delayBufferable.isValidSyncProof_(beforeDelayedAcc, message, acc, preimage);
        assertEq(isValidSyncProof, true);

        // (thresholdBlocks, thresholdSeconds) -> (thresholdBlocks + 1, thresholdSeconds)
        vm.roll(block.number + 1);
        isValidSyncProof = delayBufferable.isValidSyncProof_(beforeDelayedAcc, message, acc, preimage);
        assertEq(isValidSyncProof, false);

        // (thresholdBlocks + 1, thresholdSeconds) -> (thresholdBlocks, thresholdSeconds)
        vm.roll(block.number - 1);
        isValidSyncProof = delayBufferable.isValidSyncProof_(beforeDelayedAcc, message, acc, preimage);
        assertEq(isValidSyncProof, true);

        // (thresholdBlocks, thresholdSeconds) -> (thresholdBlocks, thresholdSeconds + 1)
        vm.warp(block.timestamp + 1);
        isValidSyncProof = delayBufferable.isValidSyncProof_(beforeDelayedAcc, message, acc, preimage);
        assertEq(isValidSyncProof, false);

        // (thresholdBlocks, thresholdSeconds + 1) -> (max, max)
        vm.roll(type(uint256).max);
        vm.warp(type(uint256).max);
        isValidSyncProof = delayBufferable.isValidSyncProof_(beforeDelayedAcc, message, acc, preimage);
        assertEq(isValidSyncProof, false);
    }

    function testUpdateBuffersDepleteAndReplenish() public {
        SimpleDelayBufferable delayBufferable = new SimpleDelayBufferable(
            maxTimeVariation,
            replenishRate,
            configBufferable
        );

        (uint64 bufferBlocks,uint64 bufferSeconds,,,DelayBuffer.DelayHistory memory prevDelay) = delayBufferable.delayBufferData();

        assertEq(prevDelay.blockNumber, 0);
        assertEq(prevDelay.timestamp, 0);
        assertEq(prevDelay.delaySeconds, 0);
        assertEq(prevDelay.delayBlocks, 0);
        assertEq(bufferBlocks, configBufferable.maxBufferBlocks);
        assertEq(bufferSeconds, configBufferable.maxBufferSeconds);

        vm.expectRevert();
        delayBufferable.updateBuffers_(10, 10);

        vm.warp(10);
        vm.roll(10);

        delayBufferable.updateBuffers_(10, 10);

        (bufferBlocks, bufferSeconds, ,, prevDelay) = delayBufferable.delayBufferData();
        assertEq(prevDelay.blockNumber, 10);
        assertEq(prevDelay.timestamp, 10);
        assertEq(prevDelay.delaySeconds, 0);
        assertEq(prevDelay.delayBlocks, 0);
        assertEq(bufferBlocks, configBufferable.maxBufferBlocks);
        assertEq(bufferSeconds, configBufferable.maxBufferSeconds);

        vm.warp(11);
        vm.roll(11);

        vm.expectRevert();
        delayBufferable.updateBuffers_(9, 9);

        delayBufferable.updateBuffers_(10, 10);

        (bufferBlocks, bufferSeconds, ,, prevDelay) = delayBufferable.delayBufferData();
        assertEq(prevDelay.blockNumber, 10);
        assertEq(prevDelay.timestamp, 10);
        assertEq(prevDelay.delayBlocks, 1);
        assertEq(prevDelay.delaySeconds, 1);
        assertEq(bufferBlocks, configBufferable.maxBufferBlocks);
        assertEq(bufferSeconds, configBufferable.maxBufferSeconds);

        vm.roll(block.number + configBufferable.thresholdBlocks);
        vm.warp(block.timestamp + configBufferable.thresholdSeconds);

        delayBufferable.updateBuffers_(10, 10);

        (bufferBlocks, bufferSeconds, ,, prevDelay) = delayBufferable.delayBufferData();
        assertEq(prevDelay.blockNumber, 10);
        assertEq(prevDelay.timestamp, 10);
        assertEq(prevDelay.delayBlocks, configBufferable.thresholdBlocks + 1);
        assertEq(prevDelay.delaySeconds, configBufferable.thresholdSeconds + 1);
        assertEq(bufferBlocks, configBufferable.maxBufferBlocks);
        assertEq(bufferSeconds, configBufferable.maxBufferSeconds);

        delayBufferable.updateBuffers_(10, 10);

        (bufferBlocks, bufferSeconds, ,, prevDelay) = delayBufferable.delayBufferData();
        assertEq(prevDelay.blockNumber, 10);
        assertEq(prevDelay.timestamp, 10);
        assertEq(prevDelay.delayBlocks, configBufferable.thresholdBlocks + 1);
        assertEq(prevDelay.delaySeconds, configBufferable.thresholdSeconds + 1);
        assertEq(bufferBlocks, configBufferable.maxBufferBlocks);
        assertEq(bufferSeconds, configBufferable.maxBufferSeconds);

        delayBufferable.updateBuffers_(11, 11);

        (bufferBlocks, bufferSeconds, ,, prevDelay) = delayBufferable.delayBufferData();
        assertEq(prevDelay.blockNumber, 11);
        assertEq(prevDelay.timestamp, 11);
        assertEq(prevDelay.delayBlocks, configBufferable.thresholdBlocks);
        assertEq(prevDelay.delaySeconds, configBufferable.thresholdSeconds);
        assertEq(bufferBlocks, configBufferable.maxBufferBlocks - 1);
        assertEq(bufferSeconds, configBufferable.maxBufferSeconds - 1);

        delayBufferable.updateBuffers_(11, 11);

        uint64 roundOffBlocks;
        uint64 roundOffSeconds;
        (bufferBlocks, bufferSeconds, roundOffBlocks,roundOffSeconds, prevDelay) = delayBufferable.delayBufferData();
        assertEq(prevDelay.blockNumber, 11);
        assertEq(prevDelay.timestamp, 11);
        assertEq(prevDelay.delayBlocks, configBufferable.thresholdBlocks);
        assertEq(prevDelay.delaySeconds, configBufferable.thresholdSeconds);
        assertEq(bufferBlocks, configBufferable.maxBufferBlocks - 1);
        assertEq(bufferSeconds, configBufferable.maxBufferSeconds - 1);

        (, , roundOffBlocks,roundOffSeconds,) = delayBufferable.delayBufferData();
        assertEq(roundOffBlocks, 0);
        assertEq(roundOffSeconds, 0);

        delayBufferable.updateBuffers_(12, 12);

        (bufferBlocks, bufferSeconds, roundOffBlocks,roundOffSeconds, prevDelay) = delayBufferable.delayBufferData();
        assertEq(prevDelay.blockNumber, 12);
        assertEq(prevDelay.timestamp, 12);
        assertEq(roundOffBlocks, 1);
        assertEq(roundOffSeconds, 1);
        assertEq(prevDelay.delayBlocks, configBufferable.thresholdBlocks - 1);
        assertEq(prevDelay.delaySeconds, configBufferable.thresholdSeconds - 1);
        assertEq(bufferBlocks, configBufferable.maxBufferBlocks - 1);
        assertEq(bufferSeconds, configBufferable.maxBufferSeconds - 1);

        delayBufferable.updateBuffers_(24, 24);

        (bufferBlocks, bufferSeconds, roundOffBlocks,roundOffSeconds, prevDelay) = delayBufferable.delayBufferData();
        assertEq(prevDelay.blockNumber, 24);
        assertEq(prevDelay.timestamp, 24);
        assertEq(roundOffBlocks, 13);
        assertEq(roundOffSeconds, 13);
        assertEq(prevDelay.delayBlocks, configBufferable.thresholdBlocks - 13);
        assertEq(prevDelay.delaySeconds, configBufferable.thresholdSeconds - 13);
        assertEq(bufferBlocks, configBufferable.maxBufferBlocks - 1);
        assertEq(bufferSeconds, configBufferable.maxBufferSeconds - 1);

        delayBufferable.updateBuffers_(25, 25);

        (bufferBlocks, bufferSeconds, roundOffBlocks,roundOffSeconds, prevDelay) = delayBufferable.delayBufferData();
        assertEq(prevDelay.blockNumber, 25);
        assertEq(prevDelay.timestamp, 25);
        assertEq(roundOffBlocks, 0);
        assertEq(roundOffSeconds, 0);
        assertEq(prevDelay.delayBlocks, configBufferable.thresholdBlocks - 14);
        assertEq(prevDelay.delaySeconds, configBufferable.thresholdSeconds - 14);
        assertEq(bufferBlocks, configBufferable.maxBufferBlocks);
        assertEq(bufferSeconds, configBufferable.maxBufferSeconds);
    }

    function testUpdateSyncValidityAndCache() public {
        SimpleDelayBufferable delayBufferable = new SimpleDelayBufferable(
            maxTimeVariation,
            replenishRate,
            configBufferable
        );


        (uint64 blockNumberFull, uint64 timestampFull) = delayBufferable.cachedFullBufferSyncExpiry_();
        uint64 blockNumber = delayBufferable.syncExpiryBlockNumber();
        uint64 timestamp = delayBufferable.syncExpiryTimestamp();

        assertEq(blockNumber, 0);
        assertEq(timestamp, 0);
        assertEq(blockNumberFull, 0);
        assertEq(timestampFull, 0);

        vm.expectRevert();
        delayBufferable.updateSyncValidity_(blockNumber + 10, timestamp + 10);

        vm.warp(10);
        vm.roll(10);

        delayBufferable.updateSyncValidity_(10, 10);
        blockNumber = delayBufferable.syncExpiryBlockNumber();
        timestamp = delayBufferable.syncExpiryTimestamp();
        (blockNumberFull, timestampFull) = delayBufferable.cachedFullBufferSyncExpiry_();

        assertEq(blockNumber, 10 + configBufferable.thresholdBlocks);
        assertEq(timestamp, 10 + configBufferable.thresholdSeconds);
        assertEq(blockNumberFull, 10 + configBufferable.thresholdBlocks);
        assertEq(timestampFull, 10 + configBufferable.thresholdSeconds);
    }

    function testForceInclusionDeadline() public {
        SimpleDelayBufferable delayBufferable = new SimpleDelayBufferable(
            maxTimeVariation,
            replenishRate,
            configBufferable
        );
        (uint64 deadlineBlockNumber, uint64 deadlineTimestamp) =
            delayBufferable.forceInclusionDeadline(0, 0);
        assertEq(deadlineBlockNumber, maxTimeVariation.delayBlocks);
        assertEq(deadlineTimestamp, maxTimeVariation.delaySeconds);
        (uint64 bufferBlocks,uint64 bufferSeconds,,,DelayBuffer.DelayHistory memory prevDelay) = delayBufferable.delayBufferData();
        assertEq(prevDelay.blockNumber, 0);
        assertEq(prevDelay.timestamp, 0);
        assertEq(prevDelay.delaySeconds, 0);
        assertEq(prevDelay.delayBlocks, 0);
        assertEq(bufferBlocks, configBufferable.maxBufferBlocks);
        assertEq(bufferSeconds, configBufferable.maxBufferSeconds);

        uint256 delayBlockNumber =
            maxTimeVariation.delayBlocks + configBufferable.thresholdBlocks + 1;
        uint256 delayTimestamp =
            maxTimeVariation.delaySeconds + configBufferable.thresholdSeconds + 1;

        vm.roll(delayBlockNumber);
        vm.warp(delayTimestamp);
        delayBufferable.updateBuffers_(0, 0);

        (bufferBlocks, bufferSeconds,,,) = delayBufferable.delayBufferData();
        assertEq(bufferBlocks, configBufferable.maxBufferBlocks);
        assertEq(bufferSeconds, configBufferable.maxBufferSeconds);

        (deadlineBlockNumber, deadlineTimestamp) =
            delayBufferable.forceInclusionDeadline(uint64(delayBlockNumber), uint64(delayTimestamp));

        assertEq(deadlineBlockNumber, delayBlockNumber + maxTimeVariation.delayBlocks - 1);
        assertEq(deadlineTimestamp, delayTimestamp + maxTimeVariation.delaySeconds - 1);

        delayBufferable.updateBuffers_(
            maxTimeVariation.delayBlocks + configBufferable.thresholdBlocks + 1,
            maxTimeVariation.delaySeconds + configBufferable.thresholdSeconds + 1
        );
        (bufferBlocks, bufferSeconds,,,) = delayBufferable.delayBufferData();
        assertEq(bufferBlocks, maxTimeVariation.delayBlocks - 1);
        assertEq(bufferSeconds, maxTimeVariation.delaySeconds - 1);
    }
}
