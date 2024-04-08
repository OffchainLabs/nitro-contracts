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
        threshold: 5,
        max: 1000,
        period: 30
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
        period: 14
    });
    using DelayBuffer for BufferData;
    BufferData delayBuffer;
    BufferData delayBufferDefault = BufferData({
            buffer: configBufferable.max,
            syncExpiry: 0,
            prevBlockNumber: 0,
            prevDelay: 0
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

        assertEq(buffer, DelayBuffer.deplete(start, start, buffer, delay, threshold));
        assertEq(buffer - 1, DelayBuffer.deplete(start, start + 1, buffer, delay, threshold));
        assertEq(buffer - unexpectedDelay, DelayBuffer.deplete(start, start + unexpectedDelay, buffer, delay, threshold));
        assertEq(threshold, DelayBuffer.deplete(start, start + buffer, buffer, threshold + buffer, threshold));
        assertEq(threshold, DelayBuffer.deplete(start, start + buffer + 100, buffer, threshold + buffer + 100, threshold));
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
        delayBuffer = BufferData({
            buffer: 10,
            syncExpiry: 0,
            prevBlockNumber: 0,
            prevDelay: 0
        });

        vm.warp(25);
        vm.roll(25);

        delayBuffer.update(config, 20);
        assertEq(delayBuffer.buffer, 10);
        assertEq(delayBuffer.prevBlockNumber, 20);
        assertEq(delayBuffer.prevDelay, 5);

        delayBuffer = BufferData({
            buffer: 10,
            syncExpiry: 0,
            prevBlockNumber: 0,
            prevDelay: 0
        });
        uint64 updateBN = delayBuffer.prevBlockNumber + period;
        vm.roll(updateBN);

        delayBuffer.update(config, updateBN);
        assertEq(delayBuffer.buffer, 10 + 1);

        assertEq(delayBuffer.prevBlockNumber, updateBN);
        assertEq(delayBuffer.prevDelay, 0);
    }

    function testPendingUpdate() public {
        delayBuffer = BufferData({
            buffer: 10,
            syncExpiry: 0,
            prevBlockNumber: 0,
            prevDelay: 6
        });

        uint64 buffer = delayBuffer.pendingUpdate(config, 15);

        assertEq(buffer, 9);
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
        
        delayBuffer = delayBufferDefault;
        delayBuffer.sync(configBufferable, acc, BufferProof({beforeDelayedAcc: beforeDelayedAcc, delayedMessage: message, preimage: preimage}));

        delayBuffer = delayBufferDefault;
        vm.expectRevert();
        delayBuffer.sync(configBufferable, acc, BufferProof({beforeDelayedAcc: beforeDelayedAcc, delayedMessage: message, preimage: preimage}));


        delayBuffer = delayBufferDefault;
        delayBuffer.sync(configBufferable, acc, BufferProof({beforeDelayedAcc: beforeDelayedAcc, delayedMessage: message, preimage: preimage}));

        // (0, 0) -> (threshold, 0)
        vm.roll(block.number + configBufferable.threshold);

        delayBuffer = delayBufferDefault;
        delayBuffer.sync(configBufferable, acc, BufferProof({beforeDelayedAcc: beforeDelayedAcc, delayedMessage: message, preimage: preimage}));

        // (threshold, 0) -> (threshold + 1, 0)
        vm.roll(block.number + 1);
        
        delayBuffer = delayBufferDefault;
        vm.expectRevert();
        delayBuffer.sync(configBufferable, acc, BufferProof({beforeDelayedAcc: beforeDelayedAcc, delayedMessage: message, preimage: preimage}));

        // (threshold + 1, 0) -> (0, 0)
        vm.roll(block.number - 1 - configBufferable.threshold);

        delayBuffer = delayBufferDefault;
        vm.expectRevert();
        delayBuffer.sync(configBufferable, acc, BufferProof({beforeDelayedAcc: beforeDelayedAcc, delayedMessage: message, preimage: preimage}));

        // (0, 0) -> (threshold, thresholdSeconds)
        vm.roll(block.number + configBufferable.threshold);
        delayBuffer = delayBufferDefault;
        delayBuffer.sync(configBufferable, acc, BufferProof({beforeDelayedAcc: beforeDelayedAcc, delayedMessage: message, preimage: preimage}));

        // (threshold, thresholdSeconds) -> (threshold + 1, thresholdSeconds)
        vm.roll(block.number + 1);
        delayBuffer = delayBufferDefault;
        vm.expectRevert();
        delayBuffer.sync(configBufferable, acc, BufferProof({beforeDelayedAcc: beforeDelayedAcc, delayedMessage: message, preimage: preimage}));

        // (threshold + 1, thresholdSeconds) -> (threshold, thresholdSeconds)
        vm.roll(block.number - 1);
        delayBuffer = delayBufferDefault;
        delayBuffer.sync(configBufferable, acc, BufferProof({beforeDelayedAcc: beforeDelayedAcc, delayedMessage: message, preimage: preimage}));

        // (threshold, thresholdSeconds) -> (threshold, thresholdSeconds + 1)
        vm.warp(block.timestamp + 1);
        delayBuffer = delayBufferDefault;
        vm.expectRevert();
        delayBuffer.sync(configBufferable, acc, BufferProof({beforeDelayedAcc: beforeDelayedAcc, delayedMessage: message, preimage: preimage}));

        // (threshold, thresholdSeconds + 1) -> (max, max)
        vm.roll(type(uint256).max);
        vm.warp(type(uint256).max);
        delayBuffer = delayBufferDefault;
        vm.expectRevert();
        delayBuffer.sync(configBufferable, acc, BufferProof({beforeDelayedAcc: beforeDelayedAcc, delayedMessage: message, preimage: preimage}));
    }

    function testupdateDepleteAndReplenish() public {
        delayBuffer = delayBufferDefault;

        assertEq(delayBuffer.prevBlockNumber, 0);
        assertEq(delayBuffer.prevDelay, 0);
        assertEq(delayBuffer.buffer, configBufferable.max);

        vm.expectRevert();
        delayBuffer.update(configBufferable, 10);

        vm.warp(10);
        vm.roll(10);

        delayBuffer.update(configBufferable, 10);

        assertEq(delayBuffer.prevBlockNumber, 10);
        assertEq(delayBuffer.prevDelay, 0);
        assertEq(delayBuffer.buffer, configBufferable.max);

        vm.warp(11);
        vm.roll(11);

        vm.expectRevert();
        delayBuffer.update(configBufferable, 9);

        delayBuffer.update(configBufferable, 10);

        assertEq(delayBuffer.prevBlockNumber, 10);
        assertEq(delayBuffer.prevDelay, 1);
        assertEq(delayBuffer.buffer, configBufferable.max);

        vm.roll(block.number + configBufferable.threshold);

        delayBuffer.update(configBufferable, 10);

        assertEq(delayBuffer.prevBlockNumber, 10);
        assertEq(delayBuffer.prevDelay, configBufferable.threshold + 1);
        assertEq(delayBuffer.buffer, configBufferable.max);

        delayBuffer.update(configBufferable, 10);

        assertEq(delayBuffer.prevBlockNumber, 10);
        assertEq(delayBuffer.prevDelay, configBufferable.threshold + 1);
        assertEq(delayBuffer.buffer, configBufferable.max);

        delayBuffer.update(configBufferable, 11);

        assertEq(delayBuffer.prevBlockNumber, 11);
        assertEq(delayBuffer.prevDelay, configBufferable.threshold);
        assertEq(delayBuffer.buffer, configBufferable.max - 1);

        delayBuffer.update(configBufferable, 11);

        assertEq(delayBuffer.prevBlockNumber, 11);
        assertEq(delayBuffer.prevDelay, configBufferable.threshold);
        assertEq(delayBuffer.buffer, configBufferable.max - 1);

        delayBuffer.update(configBufferable, 12);

        assertEq(delayBuffer.prevBlockNumber, 12);
        assertEq(delayBuffer.prevDelay, configBufferable.threshold - 1);
        assertEq(delayBuffer.buffer, configBufferable.max - 1);

        delayBuffer.update(configBufferable, 24);

        assertEq(delayBuffer.prevBlockNumber, 24);
        assertEq(delayBuffer.prevDelay, configBufferable.threshold - 13);
        assertEq(delayBuffer.buffer, configBufferable.max - 1);

        delayBuffer.update(configBufferable, 25);

        assertEq(delayBuffer.prevBlockNumber, 25);
        assertEq(delayBuffer.prevDelay, configBufferable.threshold - 14);
        assertEq(delayBuffer.buffer, configBufferable.max);
    }
}
