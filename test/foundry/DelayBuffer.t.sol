// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/bridge/DelayBuffer.sol";
import "../../src/bridge/ISequencerInbox.sol";
import {L2_MSG} from "../../src/libraries/MessageTypes.sol";

contract DelayBufferableTest is Test {

    uint64 constant maxBuffer = 1000;
    uint64 constant replenishRateInBasis = 333;
    uint64 constant threshold = 5;

    BufferConfig config = BufferConfig({
        threshold: 5,
        max: 1000,
        replenishRateInBasis: 333
    });

    ISequencerInbox.MaxTimeVariation maxTimeVariation = ISequencerInbox.MaxTimeVariation({
        delayBlocks: 24 * 60 * 60 / 12,
        futureBlocks: 32 * 2,
        delaySeconds: 24 * 60 * 60,
        futureSeconds: 32 * 2 * 12
    });
    BufferConfig configBufferable = BufferConfig({
        threshold: 60 * 60 * 2 / 12,
        max: 24 * 60 * 60 / 12 * 2,
        replenishRateInBasis: 714
    });
    using DelayBuffer for BufferData;
    BufferData delayBuffer;
    BufferData delayBufferDefault = BufferData({
            bufferBlocks: configBufferable.max,
            max: configBufferable.max,
            threshold: configBufferable.threshold,
            prevBlockNumber: 0,
            replenishRateInBasis: configBufferable.replenishRateInBasis,
            prevSequencedBlockNumber: 0
        });

    Messages.Message message = Messages.Message({
        kind: L2_MSG,
        sender: address(1),
        blockNumber: uint64(block.number),
        timestamp: uint64(block.timestamp),
        inboxSeqNum: uint256(1),
        baseFeeL1: uint256(1),
        messageDataHash: bytes32(0)
    });

    function testBufferUpdate() public {
        uint64 start = 10;
        uint64 sequenced = 20;
        uint64 buffer = 100;
        uint64 unexpectedDelay = (sequenced - start - threshold);

        assertEq(buffer, DelayBuffer.bufferUpdate(start, start, buffer, sequenced, threshold, maxBuffer, replenishRateInBasis));
        assertEq(buffer - 1, DelayBuffer.bufferUpdate(start, start + 1, buffer, sequenced, threshold, maxBuffer, replenishRateInBasis));
        uint64 replenishAmount = unexpectedDelay * replenishRateInBasis / 10000;
        assertEq(buffer + replenishAmount - unexpectedDelay, DelayBuffer.bufferUpdate(start, start + unexpectedDelay, buffer, sequenced, threshold, maxBuffer, replenishRateInBasis));
        replenishAmount = buffer * replenishRateInBasis / 10000;
        assertEq(threshold, DelayBuffer.bufferUpdate(start, start + buffer, buffer, start + threshold + buffer, threshold, maxBuffer, replenishRateInBasis));
        replenishAmount = (buffer + 100) * replenishRateInBasis / 10000;
        assertEq(threshold, DelayBuffer.bufferUpdate(start, start + buffer + 100, buffer, start + threshold + buffer + 100, threshold, maxBuffer, replenishRateInBasis));

    }

    function testUpdate() public {
        delayBuffer = BufferData({
            bufferBlocks: 10,
            max: config.max,
            threshold: config.threshold,
            prevBlockNumber: 0,
            replenishRateInBasis: config.replenishRateInBasis,
            prevSequencedBlockNumber: 0
        });

        vm.roll(25);

        delayBuffer.update(20);
        assertEq(delayBuffer.bufferBlocks, 10);
        assertEq(delayBuffer.prevBlockNumber, 20);
        assertEq(delayBuffer.prevSequencedBlockNumber, 25);

        delayBuffer = BufferData({
            bufferBlocks: 10,
            max: config.max,
            threshold: config.threshold,
            prevBlockNumber: 0,
            replenishRateInBasis: config.replenishRateInBasis,
            prevSequencedBlockNumber: 0
        });
        uint64 updateBN = delayBuffer.prevBlockNumber + 10000;
        vm.roll(updateBN);

        delayBuffer.update(updateBN);
        assertEq(delayBuffer.bufferBlocks, 10 + config.replenishRateInBasis);

        assertEq(delayBuffer.prevBlockNumber, updateBN);
        assertEq(delayBuffer.prevSequencedBlockNumber, updateBN);
    }

    function testPendingBufferUpdate() public {
        delayBuffer = BufferData({
            bufferBlocks: 10,
            max: config.max,
            threshold: config.threshold,
            prevBlockNumber: 0,
            replenishRateInBasis: config.replenishRateInBasis,
            prevSequencedBlockNumber: 6
        });

        uint64 buffer = delayBuffer.pendingBufferUpdate(15);

        assertEq(buffer, 9);
    }

    function testUpdateDepleteAndReplenish() public {
        delayBuffer = delayBufferDefault;

        assertEq(delayBuffer.prevBlockNumber, 0);
        assertEq(delayBuffer.prevSequencedBlockNumber, 0);
        assertEq(delayBuffer.bufferBlocks, configBufferable.max);

        vm.expectRevert();
        delayBuffer.update(10);

        vm.warp(10);
        vm.roll(10);

        delayBuffer.update(10);

        assertEq(delayBuffer.prevBlockNumber, 10);
        assertEq(delayBuffer.prevSequencedBlockNumber, 10);
        assertEq(delayBuffer.bufferBlocks, configBufferable.max);

        vm.warp(11);
        vm.roll(11);

        vm.expectRevert();
        delayBuffer.update(9);

        delayBuffer.update(10);

        assertEq(delayBuffer.prevBlockNumber, 10);
        assertEq(delayBuffer.prevSequencedBlockNumber, 11);
        assertEq(delayBuffer.bufferBlocks, configBufferable.max);

        vm.roll(block.number + configBufferable.threshold);

        delayBuffer.update(10);

        assertEq(delayBuffer.prevBlockNumber, 10);
        assertEq(delayBuffer.prevSequencedBlockNumber, configBufferable.threshold + 11);
        assertEq(delayBuffer.bufferBlocks, configBufferable.max);

        delayBuffer.update(10);

        assertEq(delayBuffer.prevBlockNumber, 10);
        assertEq(delayBuffer.prevSequencedBlockNumber, configBufferable.threshold + 11);
        assertEq(delayBuffer.bufferBlocks, configBufferable.max);

        delayBuffer.update(11);

        assertEq(delayBuffer.prevBlockNumber, 11);
        assertEq(delayBuffer.prevSequencedBlockNumber, configBufferable.threshold + 11);
        assertEq(delayBuffer.bufferBlocks, configBufferable.max - 1);

        delayBuffer.update(11);

        assertEq(delayBuffer.prevBlockNumber, 11);
        assertEq(delayBuffer.prevSequencedBlockNumber, configBufferable.threshold + 11);
        assertEq(delayBuffer.bufferBlocks, configBufferable.max - 1);

        delayBuffer.update(12);

        assertEq(delayBuffer.prevBlockNumber, 12);
        assertEq(delayBuffer.prevSequencedBlockNumber, configBufferable.threshold + 11);
        assertEq(delayBuffer.bufferBlocks, configBufferable.max - 1);

        delayBuffer.update(24);

        assertEq(delayBuffer.prevBlockNumber, 24);
        assertEq(delayBuffer.prevSequencedBlockNumber, configBufferable.threshold + 11);
        assertEq(delayBuffer.bufferBlocks, configBufferable.max - 1);

        delayBuffer.update(25);

        assertEq(delayBuffer.prevBlockNumber, 25);
        assertEq(delayBuffer.prevSequencedBlockNumber, configBufferable.threshold + 11);
        assertEq(delayBuffer.bufferBlocks, configBufferable.max);
    }
}
