// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/mocks/SimpleDelayBufferable.sol";
import "../../src/bridge/Messages.sol";
import {
    L2_MSG
} from "../../src/libraries/MessageTypes.sol";
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
    IDelayBufferable.DelayConfig configBufferable = IDelayBufferable.DelayConfig({
        thresholdSeconds: 60 * 60 * 2,
        thresholdBlocks: 60 * 60 * 2 / 12,
        maxBufferSeconds: 24 * 60 * 60 * 2,
        maxBufferBlocks: 24 * 60 * 60 / 12 * 2
    });
    IDelayBufferable.DelayConfig configNotBufferable = IDelayBufferable.DelayConfig({
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

    function testIsDelayBufferable() public {
        DelayBufferable bufferable = new SimpleDelayBufferable(
            maxTimeVariation,
            replenishRate,
            configNotBufferable
        );
        assertEq(bufferable.isDelayBufferable(), false);

        bufferable = new SimpleDelayBufferable(
            maxTimeVariation,
            replenishRate,
            configBufferable
        );
        assertEq(bufferable.isDelayBufferable(), true);
    }

    function testSyncProof() public {
        SimpleDelayBufferable bufferable = new SimpleDelayBufferable(
            maxTimeVariation,
            replenishRate,
            configBufferable
        );

        bytes32 beforeDelayedAcc = bytes32(0);
        bytes32 delayedAcc = Messages.accumulateInboxMessage(beforeDelayedAcc, Messages.messageHash(message));
        bytes32 beforeAcc = bytes32(0);
        bytes32 dataHash = bytes32(0);

        Messages.InboxAccPreimage memory preimage = Messages.InboxAccPreimage ({
            beforeAcc: beforeAcc,
            dataHash: dataHash,
            delayedAcc: delayedAcc 
        });
        // first batch reads delayed message
        bytes32 acc = Messages.accumulateSequencerInbox(preimage);

        // initially message if proven with no delay
        bool isValidSyncProof = bufferable.isValidSyncProof_(beforeDelayedAcc, message, acc, preimage);
        assertEq(isValidSyncProof, true);

        // sanity check
        isValidSyncProof = bufferable.isValidSyncProof_(beforeDelayedAcc, message, bytes32(0), preimage);
        assertEq(isValidSyncProof, false);

        // (blockNumber, timestamp)

        // (0, 0) -> (0, thresholdSeconds)
        vm.warp(block.timestamp + configBufferable.thresholdSeconds);
        isValidSyncProof = bufferable.isValidSyncProof_(beforeDelayedAcc, message, acc, preimage);
        assertEq(isValidSyncProof, true);

        // (0, thresholdSeconds) -> (0, thresholdSeconds + 1)
        vm.warp(block.timestamp + 1);
        isValidSyncProof = bufferable.isValidSyncProof_(beforeDelayedAcc, message, acc, preimage);
        assertEq(isValidSyncProof, false);

        // (0, thresholdSeconds + 1) -> (0, 0)
        vm.warp(block.timestamp - 1 - configBufferable.thresholdSeconds);
        isValidSyncProof = bufferable.isValidSyncProof_(beforeDelayedAcc, message, acc, preimage);
        assertEq(isValidSyncProof, true);

        // (0, 0) -> (thresholdBlocks, 0)
        vm.roll(block.number + configBufferable.thresholdBlocks);
        isValidSyncProof = bufferable.isValidSyncProof_(beforeDelayedAcc, message, acc, preimage);
        assertEq(isValidSyncProof, true);

        // (thresholdBlocks, 0) -> (thresholdBlocks + 1, 0)
        vm.roll(block.number + 1);
        isValidSyncProof = bufferable.isValidSyncProof_(beforeDelayedAcc, message, acc, preimage);
        assertEq(isValidSyncProof, false);

        // (thresholdBlocks + 1, 0) -> (0, 0)
        vm.roll(block.number - 1 - configBufferable.thresholdBlocks);
        isValidSyncProof = bufferable.isValidSyncProof_(beforeDelayedAcc, message, acc, preimage);
        assertEq(isValidSyncProof, true);

        // (0, 0) -> (thresholdBlocks, thresholdSeconds)
        vm.roll(block.number + configBufferable.thresholdBlocks);
        vm.warp(block.timestamp + configBufferable.thresholdSeconds);
        isValidSyncProof = bufferable.isValidSyncProof_(beforeDelayedAcc, message, acc, preimage);
        assertEq(isValidSyncProof, true);

        // (thresholdBlocks, thresholdSeconds) -> (thresholdBlocks + 1, thresholdSeconds)
        vm.roll(block.number + 1);
        isValidSyncProof = bufferable.isValidSyncProof_(beforeDelayedAcc, message, acc, preimage);
        assertEq(isValidSyncProof, false);

        // (thresholdBlocks + 1, thresholdSeconds) -> (thresholdBlocks, thresholdSeconds) 
        vm.roll(block.number - 1);
        isValidSyncProof = bufferable.isValidSyncProof_(beforeDelayedAcc, message, acc, preimage);
        assertEq(isValidSyncProof, true);

        // (thresholdBlocks, thresholdSeconds) -> (thresholdBlocks, thresholdSeconds + 1)
        vm.warp(block.timestamp + 1);
        isValidSyncProof = bufferable.isValidSyncProof_(beforeDelayedAcc, message, acc, preimage);
        assertEq(isValidSyncProof, false);

        // (thresholdBlocks, thresholdSeconds + 1) -> (max, max)
        vm.roll(type(uint256).max);
        vm.warp(type(uint256).max);
        isValidSyncProof = bufferable.isValidSyncProof_(beforeDelayedAcc, message, acc, preimage);
        assertEq(isValidSyncProof, false);
    }

    function testUpdateBuffersDepleteAndReplenish() public {
        
        SimpleDelayBufferable bufferable = new SimpleDelayBufferable(
            maxTimeVariation,
            replenishRate,
            configBufferable
        );

        IDelayBufferable.DelayCache memory prevDelay = bufferable.prevDelay_();
        (uint64 bufferBlocks, uint64 bufferSeconds) = bufferable.delayBuffer();
        assertEq(prevDelay.blockNumber, 0);
        assertEq(prevDelay.timestamp, 0);
        assertEq(prevDelay.delaySeconds, 0);
        assertEq(prevDelay.delayBlocks, 0);
        assertEq(bufferBlocks, configBufferable.maxBufferBlocks);
        assertEq(bufferSeconds, configBufferable.maxBufferSeconds);

        vm.expectRevert();
        bufferable.updateBuffers_(10, 10);

        vm.warp(10);
        vm.roll(10);

        bufferable.updateBuffers_(10, 10);

        prevDelay = bufferable.prevDelay_();
        (bufferBlocks, bufferSeconds) = bufferable.delayBuffer();
        assertEq(prevDelay.blockNumber, 10);
        assertEq(prevDelay.timestamp, 10);
        assertEq(prevDelay.delaySeconds, 0);
        assertEq(prevDelay.delayBlocks, 0);
        assertEq(bufferBlocks, configBufferable.maxBufferBlocks);
        assertEq(bufferSeconds, configBufferable.maxBufferSeconds);

        vm.warp(11);
        vm.roll(11);

        vm.expectRevert();
        bufferable.updateBuffers_(9, 9);

        bufferable.updateBuffers_(10, 10);


        prevDelay = bufferable.prevDelay_();
        (bufferBlocks, bufferSeconds) = bufferable.delayBuffer();
        assertEq(prevDelay.blockNumber, 10);
        assertEq(prevDelay.timestamp, 10);
        assertEq(prevDelay.delayBlocks, 1);
        assertEq(prevDelay.delaySeconds, 1);
        assertEq(bufferBlocks, configBufferable.maxBufferBlocks);
        assertEq(bufferSeconds, configBufferable.maxBufferSeconds);

        vm.roll(block.number + configBufferable.thresholdBlocks);
        vm.warp(block.timestamp + configBufferable.thresholdSeconds);

        bufferable.updateBuffers_(10, 10);

        prevDelay = bufferable.prevDelay_();
        (bufferBlocks, bufferSeconds) = bufferable.delayBuffer();
        assertEq(prevDelay.blockNumber, 10);
        assertEq(prevDelay.timestamp, 10);
        assertEq(prevDelay.delayBlocks, configBufferable.thresholdBlocks + 1);
        assertEq(prevDelay.delaySeconds, configBufferable.thresholdSeconds + 1);
        assertEq(bufferBlocks, configBufferable.maxBufferBlocks);
        assertEq(bufferSeconds, configBufferable.maxBufferSeconds);

        bufferable.updateBuffers_(10, 10);

        prevDelay = bufferable.prevDelay_();
        (bufferBlocks, bufferSeconds) = bufferable.delayBuffer();
        assertEq(prevDelay.blockNumber, 10);
        assertEq(prevDelay.timestamp, 10);
        assertEq(prevDelay.delayBlocks, configBufferable.thresholdBlocks + 1);
        assertEq(prevDelay.delaySeconds, configBufferable.thresholdSeconds + 1);
        assertEq(bufferBlocks, configBufferable.maxBufferBlocks);
        assertEq(bufferSeconds, configBufferable.maxBufferSeconds);

        bufferable.updateBuffers_(11, 11);

        prevDelay = bufferable.prevDelay_();
        (bufferBlocks, bufferSeconds) = bufferable.delayBuffer();
        assertEq(prevDelay.blockNumber, 11);
        assertEq(prevDelay.timestamp, 11);
        assertEq(prevDelay.delayBlocks, configBufferable.thresholdBlocks);
        assertEq(prevDelay.delaySeconds, configBufferable.thresholdSeconds);
        assertEq(bufferBlocks, configBufferable.maxBufferBlocks - 1);
        assertEq(bufferSeconds, configBufferable.maxBufferSeconds - 1);

        bufferable.updateBuffers_(11, 11);

        prevDelay = bufferable.prevDelay_();
        (bufferBlocks, bufferSeconds) = bufferable.delayBuffer();
        assertEq(prevDelay.blockNumber, 11);
        assertEq(prevDelay.timestamp, 11);
        assertEq(prevDelay.delayBlocks, configBufferable.thresholdBlocks);
        assertEq(prevDelay.delaySeconds, configBufferable.thresholdSeconds);
        assertEq(bufferBlocks, configBufferable.maxBufferBlocks - 1);
        assertEq(bufferSeconds, configBufferable.maxBufferSeconds - 1);

        (uint64 roundOffBlocks, uint64 roundOffSeconds) = bufferable.roundOff();
        assertEq(roundOffBlocks, 0);
        assertEq(roundOffSeconds, 0);

        bufferable.updateBuffers_(12, 12);

        prevDelay = bufferable.prevDelay_();
        (bufferBlocks, bufferSeconds) = bufferable.delayBuffer();
        (roundOffBlocks, roundOffSeconds) = bufferable.roundOff();
        assertEq(prevDelay.blockNumber, 12);
        assertEq(prevDelay.timestamp, 12);
        assertEq(roundOffBlocks, 1);
        assertEq(roundOffSeconds, 1);
        assertEq(prevDelay.delayBlocks, configBufferable.thresholdBlocks - 1);
        assertEq(prevDelay.delaySeconds, configBufferable.thresholdSeconds - 1);
        assertEq(bufferBlocks, configBufferable.maxBufferBlocks - 1);
        assertEq(bufferSeconds, configBufferable.maxBufferSeconds - 1);

        bufferable.updateBuffers_(24, 24);

        prevDelay = bufferable.prevDelay_();
        (bufferBlocks, bufferSeconds) = bufferable.delayBuffer();
        (roundOffBlocks, roundOffSeconds) = bufferable.roundOff();
        assertEq(prevDelay.blockNumber, 24);
        assertEq(prevDelay.timestamp, 24);
        assertEq(roundOffBlocks, 13);
        assertEq(roundOffSeconds, 13);
        assertEq(prevDelay.delayBlocks, configBufferable.thresholdBlocks - 13);
        assertEq(prevDelay.delaySeconds, configBufferable.thresholdSeconds - 13);
        assertEq(bufferBlocks, configBufferable.maxBufferBlocks - 1);
        assertEq(bufferSeconds, configBufferable.maxBufferSeconds - 1);

        bufferable.updateBuffers_(25, 25);

        prevDelay = bufferable.prevDelay_();
        (bufferBlocks, bufferSeconds) = bufferable.delayBuffer();
        (roundOffBlocks, roundOffSeconds) = bufferable.roundOff();
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
        SimpleDelayBufferable bufferable = new SimpleDelayBufferable(
            maxTimeVariation,
            replenishRate,
            configBufferable
        );

        (uint64 blockNumber, uint64 timestamp) = bufferable.syncExpiry();
        (uint64 blockNumberFull, uint64 timestampFull) = bufferable.cachedFullBufferExpiry_();

        assertEq(blockNumber, 0);
        assertEq(timestamp, 0);
        assertEq(blockNumberFull, 0);
        assertEq(timestampFull, 0);

        vm.expectRevert();
        bufferable.updateSyncValidity_(false, blockNumber + 10, timestamp + 10);

        vm.warp(10);
        vm.roll(10);

        bufferable.updateSyncValidity_(false, 10, 10);

        (blockNumber, timestamp) = bufferable.syncExpiry();
        (blockNumberFull, timestampFull) = bufferable.cachedFullBufferExpiry_();

        assertEq(blockNumber,  configBufferable.thresholdBlocks);
        assertEq(timestamp, configBufferable.thresholdSeconds);
        assertEq(blockNumberFull, 0);
        assertEq(timestampFull, 0);

        bufferable.updateSyncValidity_(true, 10, 10);
        (blockNumber, timestamp) = bufferable.syncExpiry();
        (blockNumberFull, timestampFull) = bufferable.cachedFullBufferExpiry_();

        assertEq(blockNumber,  configBufferable.thresholdBlocks);
        assertEq(timestamp, configBufferable.thresholdSeconds);
        assertEq(blockNumberFull, configBufferable.thresholdBlocks);
        assertEq(timestampFull, configBufferable.thresholdSeconds);
    }
}