// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/bridge/DelayBuffer.sol";
import "../../src/bridge/ISequencerInbox.sol";
import {L2_MSG} from "../../src/libraries/MessageTypes.sol";

contract DelayBufferableTest is Test {

    uint64 constant maxBuffer = 1000;
    uint64 constant period = 30;
    uint64 constant threshold = 5;

    BufferConfig config = BufferConfig({
        thresholdBlocks: 5,
        thresholdSeconds: 5,
        maxBufferBlocks: 1000,
        maxBufferSeconds: 1000,
        periodBlocks: 30,
        periodSeconds: 30
    });

    ISequencerInbox.MaxTimeVariation maxTimeVariation = ISequencerInbox.MaxTimeVariation({
        delayBlocks: 24 * 60 * 60 / 12,
        futureBlocks: 32 * 2,
        delaySeconds: 24 * 60 * 60,
        futureSeconds: 32 * 2 * 12
    });
    BufferConfig configBufferable = BufferConfig({
        thresholdBlocks: 60 * 60 * 2 / 12,
        thresholdSeconds: 60 * 60 * 2,
        maxBufferBlocks: 24 * 60 * 60 / 12 * 2,
        maxBufferSeconds: 24 * 60 * 60 * 2,
        periodSeconds: 14,
        periodBlocks: 14
    });
    using DelayBuffer for BufferData;
    BufferData delayBuffer;
    BufferData delayBufferDefault = BufferData({
            bufferBlocks: configBufferable.maxBufferBlocks,
            bufferSeconds: configBufferable.maxBufferSeconds,
            syncExpiryBlockNumber: 0,
            syncExpiryTimestamp: 0,
            prevDelay: DelayHistory({
                blockNumber: 0,
                timestamp: 0,
                delayBlocks: 0,
                delaySeconds: 0
            })
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

    function testDeplete() public {
        uint64 start = 10;
        uint64 delay = 10;
        uint64 buffer = 100;
        uint64 unexpectedDelay = (delay - threshold);

        assertEq(buffer, DelayBuffer.deplete(start, start, delay, threshold, buffer));
        assertEq(buffer - 1, DelayBuffer.deplete(start, start + 1, delay, threshold, buffer));
        assertEq(buffer - unexpectedDelay, DelayBuffer.deplete(start, start + unexpectedDelay, delay, threshold, buffer));
        assertEq(threshold, DelayBuffer.deplete(start, start + buffer, threshold + buffer, threshold, buffer));
        assertEq(threshold, DelayBuffer.deplete(start, start + buffer + 100, threshold + buffer + 100, threshold, buffer));
    }

    function testReplenish() public {
        uint64 start = 10;
        uint64 buffer = 100;

        uint64 newBuffer = DelayBuffer.replenish(start, start, buffer, maxBuffer, period);
        assertEq(newBuffer, buffer);

        newBuffer = DelayBuffer.replenish(start, start + 1, buffer, maxBuffer, period);
        assertEq(newBuffer, buffer);

        newBuffer = DelayBuffer.replenish(start, start + period - 1, buffer, maxBuffer, period);
        assertEq(newBuffer, buffer);

        newBuffer = DelayBuffer.replenish(start, start + 1, buffer, maxBuffer, period);
        assertEq(newBuffer, buffer);

        newBuffer = DelayBuffer.replenish(start, start + period, buffer, maxBuffer, period);
        assertEq(newBuffer, buffer + 1);

        uint64 remaining = ((maxBuffer - buffer) + 1)*period;

        newBuffer = DelayBuffer.replenish(start, start + remaining, buffer, maxBuffer, period);
        assertEq(newBuffer, maxBuffer);

        newBuffer = DelayBuffer.replenish(start, start + remaining + period, buffer, maxBuffer, period);
        assertEq(newBuffer, maxBuffer);
    }

    function testUpdate() public {
        uint64 start = 10;
        uint64 delay = 10;
        uint64 buffer = 100;
        
        uint64 newBuffer = DelayBuffer.update(start, start, delay, threshold, buffer, maxBuffer, period);
        assertEq(newBuffer, buffer);

        newBuffer = DelayBuffer.update(start, start + 1, delay, threshold, buffer, maxBuffer, period);
        assertEq(newBuffer, buffer - 1);

        newBuffer = DelayBuffer.update(start, start + 1, 0, threshold, buffer, maxBuffer, period);
        assertEq(newBuffer, buffer);


        newBuffer = DelayBuffer.update(start, start + period, 0, threshold, buffer, maxBuffer, period);
        assertEq(newBuffer, buffer + 1);
    }

    function testUpdateBuffers() public {
        delayBuffer = BufferData({
            bufferBlocks: 10,
            bufferSeconds: 10,
            syncExpiryBlockNumber: 0,
            syncExpiryTimestamp: 0,
            prevDelay: DelayHistory({
                blockNumber: 10,
                timestamp: 10,
                delayBlocks: 10,
                delaySeconds: 10
            })
        });

        vm.warp(25);
        vm.roll(25);

        delayBuffer.updateBuffers(config, 20, 20);
        assertEq(delayBuffer.bufferBlocks, 5);
        assertEq(delayBuffer.bufferSeconds, 5);
        assertEq(delayBuffer.prevDelay.blockNumber, 20);
        assertEq(delayBuffer.prevDelay.delayBlocks, 5);
        assertEq(delayBuffer.prevDelay.timestamp, 20);
        assertEq(delayBuffer.prevDelay.delaySeconds, 5);

        delayBuffer = BufferData({
            bufferBlocks: 10,
            bufferSeconds: 10,
            syncExpiryBlockNumber: 0,
            syncExpiryTimestamp: 0,
            prevDelay: DelayHistory({
                blockNumber: 10,
                timestamp: 10,
                delayBlocks: 3,
                delaySeconds: 3
            })
        });
        uint64 updateTS = delayBuffer.prevDelay.timestamp + period;
        uint64 updateBN = delayBuffer.prevDelay.timestamp + period;
        vm.warp(updateTS);
        vm.roll(updateBN);

        delayBuffer.updateBuffers(config, updateBN, updateTS);
        assertEq(delayBuffer.bufferBlocks, 10 + 1);
        assertEq(delayBuffer.bufferSeconds, 10 + 1);

        assertEq(delayBuffer.prevDelay.blockNumber, updateBN);
        assertEq(delayBuffer.prevDelay.delayBlocks, 0);
        assertEq(delayBuffer.prevDelay.timestamp, updateTS);
        assertEq(delayBuffer.prevDelay.delaySeconds, 0);
    }

    function testPendingDelay() public {
        delayBuffer = BufferData({
            bufferBlocks: 10,
            bufferSeconds: 10,
            syncExpiryBlockNumber: 0,
            syncExpiryTimestamp: 0,
            prevDelay: DelayHistory({
                blockNumber: 10,
                timestamp: 10,
                delayBlocks: 10,
                delaySeconds: 10
            })
        });

        (uint64 bufferBlocks, uint64 bufferSeconds) = delayBuffer.pendingDelay(15, 15, threshold, threshold);

        assertEq(bufferBlocks, 5);
        assertEq(bufferSeconds, 5);
    }

    function testBufferProof() public {
        delayBuffer = delayBufferDefault;

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
        delayBuffer = delayBufferDefault;
        delayBuffer.sync(configBufferable, acc, BufferProof({beforeDelayedAcc: beforeDelayedAcc, delayedMessage: message, preimage: preimage}));

        // sanity check
        delayBuffer = delayBufferDefault;
        vm.expectRevert();
        delayBuffer.sync(configBufferable, bytes32(0), BufferProof({beforeDelayedAcc: beforeDelayedAcc, delayedMessage: message, preimage: preimage}));

        // (blockNumber, timestamp)

        // (0, 0) -> (0, thresholdSeconds)
        vm.warp(block.timestamp + configBufferable.thresholdSeconds);
        
        delayBuffer = delayBufferDefault;
        delayBuffer.sync(configBufferable, acc, BufferProof({beforeDelayedAcc: beforeDelayedAcc, delayedMessage: message, preimage: preimage}));

        // (0, thresholdSeconds) -> (0, thresholdSeconds + 1)
        vm.warp(block.timestamp + 1);

        delayBuffer = delayBufferDefault;
        vm.expectRevert();
        delayBuffer.sync(configBufferable, acc, BufferProof({beforeDelayedAcc: beforeDelayedAcc, delayedMessage: message, preimage: preimage}));

        // (0, thresholdSeconds + 1) -> (0, 0)
        vm.warp(block.timestamp - 1 - configBufferable.thresholdSeconds);

        delayBuffer = delayBufferDefault;
        delayBuffer.sync(configBufferable, acc, BufferProof({beforeDelayedAcc: beforeDelayedAcc, delayedMessage: message, preimage: preimage}));

        // (0, 0) -> (thresholdBlocks, 0)
        vm.roll(block.number + configBufferable.thresholdBlocks);

        delayBuffer = delayBufferDefault;
        delayBuffer.sync(configBufferable, acc, BufferProof({beforeDelayedAcc: beforeDelayedAcc, delayedMessage: message, preimage: preimage}));

        // (thresholdBlocks, 0) -> (thresholdBlocks + 1, 0)
        vm.roll(block.number + 1);
        
        delayBuffer = delayBufferDefault;
        vm.expectRevert();
        delayBuffer.sync(configBufferable, acc, BufferProof({beforeDelayedAcc: beforeDelayedAcc, delayedMessage: message, preimage: preimage}));

        // (thresholdBlocks + 1, 0) -> (0, 0)
        vm.roll(block.number - 1 - configBufferable.thresholdBlocks);

        delayBuffer = delayBufferDefault;
        vm.expectRevert();
        delayBuffer.sync(configBufferable, acc, BufferProof({beforeDelayedAcc: beforeDelayedAcc, delayedMessage: message, preimage: preimage}));

        // (0, 0) -> (thresholdBlocks, thresholdSeconds)
        vm.roll(block.number + configBufferable.thresholdBlocks);
        vm.warp(block.timestamp + configBufferable.thresholdSeconds);
        delayBuffer = delayBufferDefault;
        delayBuffer.sync(configBufferable, acc, BufferProof({beforeDelayedAcc: beforeDelayedAcc, delayedMessage: message, preimage: preimage}));

        // (thresholdBlocks, thresholdSeconds) -> (thresholdBlocks + 1, thresholdSeconds)
        vm.roll(block.number + 1);
        delayBuffer = delayBufferDefault;
        vm.expectRevert();
        delayBuffer.sync(configBufferable, acc, BufferProof({beforeDelayedAcc: beforeDelayedAcc, delayedMessage: message, preimage: preimage}));

        // (thresholdBlocks + 1, thresholdSeconds) -> (thresholdBlocks, thresholdSeconds)
        vm.roll(block.number - 1);
        delayBuffer = delayBufferDefault;
        delayBuffer.sync(configBufferable, acc, BufferProof({beforeDelayedAcc: beforeDelayedAcc, delayedMessage: message, preimage: preimage}));

        // (thresholdBlocks, thresholdSeconds) -> (thresholdBlocks, thresholdSeconds + 1)
        vm.warp(block.timestamp + 1);
        delayBuffer = delayBufferDefault;
        vm.expectRevert();
        delayBuffer.sync(configBufferable, acc, BufferProof({beforeDelayedAcc: beforeDelayedAcc, delayedMessage: message, preimage: preimage}));

        // (thresholdBlocks, thresholdSeconds + 1) -> (max, max)
        vm.roll(type(uint256).max);
        vm.warp(type(uint256).max);
        delayBuffer = delayBufferDefault;
        vm.expectRevert();
        delayBuffer.sync(configBufferable, acc, BufferProof({beforeDelayedAcc: beforeDelayedAcc, delayedMessage: message, preimage: preimage}));
    }

    function testUpdateBuffersDepleteAndReplenish() public {
        delayBuffer = delayBufferDefault;

        assertEq(delayBuffer.prevDelay.blockNumber, 0);
        assertEq(delayBuffer.prevDelay.timestamp, 0);
        assertEq(delayBuffer.prevDelay.delaySeconds, 0);
        assertEq(delayBuffer.prevDelay.delayBlocks, 0);
        assertEq(delayBuffer.bufferBlocks, configBufferable.maxBufferBlocks);
        assertEq(delayBuffer.bufferSeconds, configBufferable.maxBufferSeconds);

        vm.expectRevert();
        delayBuffer.updateBuffers(configBufferable, 10, 10);

        vm.warp(10);
        vm.roll(10);

        delayBuffer.updateBuffers(configBufferable, 10, 10);

        assertEq(delayBuffer.prevDelay.blockNumber, 10);
        assertEq(delayBuffer.prevDelay.timestamp, 10);
        assertEq(delayBuffer.prevDelay.delaySeconds, 0);
        assertEq(delayBuffer.prevDelay.delayBlocks, 0);
        assertEq(delayBuffer.bufferBlocks, configBufferable.maxBufferBlocks);
        assertEq(delayBuffer.bufferSeconds, configBufferable.maxBufferSeconds);

        vm.warp(11);
        vm.roll(11);

        vm.expectRevert();
        delayBuffer.updateBuffers(configBufferable, 9, 9);

        delayBuffer.updateBuffers(configBufferable, 10, 10);

        assertEq(delayBuffer.prevDelay.blockNumber, 10);
        assertEq(delayBuffer.prevDelay.timestamp, 10);
        assertEq(delayBuffer.prevDelay.delayBlocks, 1);
        assertEq(delayBuffer.prevDelay.delaySeconds, 1);
        assertEq(delayBuffer.bufferBlocks, configBufferable.maxBufferBlocks);
        assertEq(delayBuffer.bufferSeconds, configBufferable.maxBufferSeconds);

        vm.roll(block.number + configBufferable.thresholdBlocks);
        vm.warp(block.timestamp + configBufferable.thresholdSeconds);

        delayBuffer.updateBuffers(configBufferable, 10, 10);

        assertEq(delayBuffer.prevDelay.blockNumber, 10);
        assertEq(delayBuffer.prevDelay.timestamp, 10);
        assertEq(delayBuffer.prevDelay.delayBlocks, configBufferable.thresholdBlocks + 1);
        assertEq(delayBuffer.prevDelay.delaySeconds, configBufferable.thresholdSeconds + 1);
        assertEq(delayBuffer.bufferBlocks, configBufferable.maxBufferBlocks);
        assertEq(delayBuffer.bufferSeconds, configBufferable.maxBufferSeconds);

        delayBuffer.updateBuffers(configBufferable, 10, 10);

        assertEq(delayBuffer.prevDelay.blockNumber, 10);
        assertEq(delayBuffer.prevDelay.timestamp, 10);
        assertEq(delayBuffer.prevDelay.delayBlocks, configBufferable.thresholdBlocks + 1);
        assertEq(delayBuffer.prevDelay.delaySeconds, configBufferable.thresholdSeconds + 1);
        assertEq(delayBuffer.bufferBlocks, configBufferable.maxBufferBlocks);
        assertEq(delayBuffer.bufferSeconds, configBufferable.maxBufferSeconds);

        delayBuffer.updateBuffers(configBufferable, 11, 11);

        assertEq(delayBuffer.prevDelay.blockNumber, 11);
        assertEq(delayBuffer.prevDelay.timestamp, 11);
        assertEq(delayBuffer.prevDelay.delayBlocks, configBufferable.thresholdBlocks);
        assertEq(delayBuffer.prevDelay.delaySeconds, configBufferable.thresholdSeconds);
        assertEq(delayBuffer.bufferBlocks, configBufferable.maxBufferBlocks - 1);
        assertEq(delayBuffer.bufferSeconds, configBufferable.maxBufferSeconds - 1);

        delayBuffer.updateBuffers(configBufferable, 11, 11);

        assertEq(delayBuffer.prevDelay.blockNumber, 11);
        assertEq(delayBuffer.prevDelay.timestamp, 11);
        assertEq(delayBuffer.prevDelay.delayBlocks, configBufferable.thresholdBlocks);
        assertEq(delayBuffer.prevDelay.delaySeconds, configBufferable.thresholdSeconds);
        assertEq(delayBuffer.bufferBlocks, configBufferable.maxBufferBlocks - 1);
        assertEq(delayBuffer.bufferSeconds, configBufferable.maxBufferSeconds - 1);

        delayBuffer.updateBuffers(configBufferable, 12, 12);

        assertEq(delayBuffer.prevDelay.blockNumber, 12);
        assertEq(delayBuffer.prevDelay.timestamp, 12);
        assertEq(delayBuffer.prevDelay.delayBlocks, configBufferable.thresholdBlocks - 1);
        assertEq(delayBuffer.prevDelay.delaySeconds, configBufferable.thresholdSeconds - 1);
        assertEq(delayBuffer.bufferBlocks, configBufferable.maxBufferBlocks - 1);
        assertEq(delayBuffer.bufferSeconds, configBufferable.maxBufferSeconds - 1);

        delayBuffer.updateBuffers(configBufferable, 24, 24);

        assertEq(delayBuffer.prevDelay.blockNumber, 24);
        assertEq(delayBuffer.prevDelay.timestamp, 24);
        assertEq(delayBuffer.prevDelay.delayBlocks, configBufferable.thresholdBlocks - 13);
        assertEq(delayBuffer.prevDelay.delaySeconds, configBufferable.thresholdSeconds - 13);
        assertEq(delayBuffer.bufferBlocks, configBufferable.maxBufferBlocks - 1);
        assertEq(delayBuffer.bufferSeconds, configBufferable.maxBufferSeconds - 1);

        delayBuffer.updateBuffers(configBufferable, 25, 25);

        assertEq(delayBuffer.prevDelay.blockNumber, 25);
        assertEq(delayBuffer.prevDelay.timestamp, 25);
        assertEq(delayBuffer.prevDelay.delayBlocks, configBufferable.thresholdBlocks - 14);
        assertEq(delayBuffer.prevDelay.delaySeconds, configBufferable.thresholdSeconds - 14);
        assertEq(delayBuffer.bufferBlocks, configBufferable.maxBufferBlocks);
        assertEq(delayBuffer.bufferSeconds, configBufferable.maxBufferSeconds);
    }
}
