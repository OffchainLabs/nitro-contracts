// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/bridge/DelayBuffer.sol";

contract SimpleDelayBufferableTest is Test {

    uint64 constant maxBuffer = 1000;
    uint64 constant amountPerPeriod = 100;
    uint64 constant period = 30;
    uint64 constant threshold = 5;

    using DelayBuffer for DelayBuffer.DelayBufferData;
    DelayBuffer.DelayBufferData delayBufferData;

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
        uint64 roundOff = 0;

        (uint64 newBuffer, uint64 newRoundOff) = DelayBuffer.replenish(start, start, buffer, maxBuffer, amountPerPeriod, period, roundOff);
        assertEq(newBuffer, buffer);
        assertEq(newRoundOff, roundOff);

        (newBuffer, newRoundOff) = DelayBuffer.replenish(start, start + 1, buffer, maxBuffer, amountPerPeriod, period, roundOff);
        assertEq(newBuffer, buffer);
        assertEq(newRoundOff, roundOff + 1);

        (newBuffer, newRoundOff) = DelayBuffer.replenish(start, start + period - 1, buffer, maxBuffer, amountPerPeriod, period, roundOff);
        assertEq(newBuffer, buffer);
        assertEq(newRoundOff, roundOff + period - 1);

        (newBuffer, newRoundOff) = DelayBuffer.replenish(start, start + 1, buffer, maxBuffer, amountPerPeriod, period, period - 1);
        assertEq(newBuffer, buffer + amountPerPeriod);
        assertEq(newRoundOff, 0);

        (newBuffer, newRoundOff) = DelayBuffer.replenish(start, start + period, buffer, maxBuffer, amountPerPeriod, period, roundOff);
        assertEq(newBuffer, buffer + amountPerPeriod);
        assertEq(newRoundOff, roundOff);

        uint64 remaining = ((maxBuffer - buffer)/amountPerPeriod + 1)*period;

        (newBuffer, newRoundOff) = DelayBuffer.replenish(start, start + remaining, buffer, maxBuffer, amountPerPeriod, period, roundOff);
        assertEq(newBuffer, maxBuffer);
        assertEq(newRoundOff, roundOff);

        (newBuffer, newRoundOff) = DelayBuffer.replenish(start, start + remaining + period, buffer, maxBuffer, amountPerPeriod, period, roundOff);
        assertEq(newBuffer, maxBuffer);
        assertEq(newRoundOff, roundOff);
    }

    function testUpdate() public {
        uint64 start = 10;
        uint64 delay = 10;
        uint64 buffer = 100;
        uint64 roundOff = 10;
        
        (uint64 newBuffer, uint64 newRoundOff) = DelayBuffer.update(start, start, delay, threshold, buffer, maxBuffer, amountPerPeriod, period, roundOff);
        assertEq(newBuffer, buffer);
        assertEq(newRoundOff, 0);

        (newBuffer, newRoundOff) = DelayBuffer.update(start, start + 1, delay, threshold, buffer, maxBuffer, amountPerPeriod, period, roundOff);
        assertEq(newBuffer, buffer - 1);
        assertEq(newRoundOff, 0);

        (newBuffer, newRoundOff) = DelayBuffer.update(start, start + 1, 0, threshold, buffer, maxBuffer, amountPerPeriod, period, roundOff);
        assertEq(newBuffer, buffer);
        assertEq(newRoundOff, roundOff + 1);

        (newBuffer, newRoundOff) = DelayBuffer.update(start, start + period - roundOff, 0, threshold, buffer, maxBuffer, amountPerPeriod, period, roundOff);
        assertEq(newBuffer, buffer + amountPerPeriod);
        assertEq(newRoundOff, 0);

        (newBuffer, newRoundOff) = DelayBuffer.update(start, start + period, 0, threshold, buffer, maxBuffer, amountPerPeriod, period, roundOff);
        assertEq(newBuffer, buffer + amountPerPeriod);
        assertEq(newRoundOff, roundOff);
    }

    function testUpdateBlockNumber() public {
        delayBufferData = DelayBuffer.DelayBufferData({
            bufferBlocks: 10,
            bufferSeconds: 10,
            roundOffBlocks: 10,
            roundOffSeconds: 10,
            prevDelay: DelayBuffer.DelayHistory({
                blockNumber: 10,
                timestamp: 10,
                delayBlocks: 10,
                delaySeconds: 10
            })
        });

        vm.roll(25);

        delayBufferData.updateBlockNumber(20, threshold, maxBuffer, amountPerPeriod, period);
        assertEq(delayBufferData.bufferBlocks, 5);
        assertEq(delayBufferData.bufferSeconds, 10);
        assertEq(delayBufferData.roundOffBlocks, 0);
        assertEq(delayBufferData.roundOffSeconds, 10);
        assertEq(delayBufferData.prevDelay.blockNumber, 20);
        assertEq(delayBufferData.prevDelay.delayBlocks, 5);
        assertEq(delayBufferData.prevDelay.timestamp, 10);
        assertEq(delayBufferData.prevDelay.delaySeconds, 10);

        delayBufferData = DelayBuffer.DelayBufferData({
            bufferBlocks: 10,
            bufferSeconds: 10,
            roundOffBlocks: 10,
            roundOffSeconds: 10,
            prevDelay: DelayBuffer.DelayHistory({
                blockNumber: 10,
                timestamp: 10,
                delayBlocks: 3,
                delaySeconds: 3
            })
        });
        uint64 updateBN = delayBufferData.prevDelay.blockNumber + period;
        vm.roll(updateBN);

        delayBufferData.updateBlockNumber(updateBN, threshold, maxBuffer, amountPerPeriod, period);
        assertEq(delayBufferData.bufferBlocks, 10 + amountPerPeriod);
        assertEq(delayBufferData.bufferSeconds, 10);
        assertEq(delayBufferData.roundOffBlocks, 10);
        assertEq(delayBufferData.roundOffSeconds, 10);
        
        assertEq(delayBufferData.prevDelay.blockNumber, updateBN);
        assertEq(delayBufferData.prevDelay.delayBlocks, 0);
        assertEq(delayBufferData.prevDelay.timestamp, 10);
        assertEq(delayBufferData.prevDelay.delaySeconds, 3);
    }

    function testUpdateTimestamp() public {
        delayBufferData = DelayBuffer.DelayBufferData({
            bufferBlocks: 10,
            bufferSeconds: 10,
            roundOffBlocks: 10,
            roundOffSeconds: 10,
            prevDelay: DelayBuffer.DelayHistory({
                blockNumber: 10,
                timestamp: 10,
                delayBlocks: 10,
                delaySeconds: 10
            })
        });

        vm.warp(25);

        delayBufferData.updateTimestamp(20, threshold, maxBuffer, amountPerPeriod, period);
        assertEq(delayBufferData.bufferBlocks, 10);
        assertEq(delayBufferData.bufferSeconds, 5);
        assertEq(delayBufferData.roundOffBlocks, 10);
        assertEq(delayBufferData.roundOffSeconds, 0);
        assertEq(delayBufferData.prevDelay.blockNumber, 10);
        assertEq(delayBufferData.prevDelay.delayBlocks, 10);
        assertEq(delayBufferData.prevDelay.timestamp, 20);
        assertEq(delayBufferData.prevDelay.delaySeconds, 5);

        delayBufferData = DelayBuffer.DelayBufferData({
            bufferBlocks: 10,
            bufferSeconds: 10,
            roundOffBlocks: 10,
            roundOffSeconds: 10,
            prevDelay: DelayBuffer.DelayHistory({
                blockNumber: 10,
                timestamp: 10,
                delayBlocks: 3,
                delaySeconds: 3
            })
        });
        uint64 updateTS = delayBufferData.prevDelay.timestamp + period;
        vm.warp(updateTS);

        delayBufferData.updateTimestamp(updateTS, threshold, maxBuffer, amountPerPeriod, period);
        assertEq(delayBufferData.bufferBlocks, 10);
        assertEq(delayBufferData.bufferSeconds, 10 + amountPerPeriod);
        assertEq(delayBufferData.roundOffBlocks, 10);
        assertEq(delayBufferData.roundOffSeconds, 10);
        
        assertEq(delayBufferData.prevDelay.blockNumber, 10);
        assertEq(delayBufferData.prevDelay.delayBlocks, 3);
        assertEq(delayBufferData.prevDelay.timestamp, updateTS);
        assertEq(delayBufferData.prevDelay.delaySeconds, 0);
    }

    function testUpdateBuffers() public {
        delayBufferData = DelayBuffer.DelayBufferData({
            bufferBlocks: 10,
            bufferSeconds: 10,
            roundOffBlocks: 10,
            roundOffSeconds: 10,
            prevDelay: DelayBuffer.DelayHistory({
                blockNumber: 10,
                timestamp: 10,
                delayBlocks: 10,
                delaySeconds: 10
            })
        });

        vm.warp(25);
        vm.roll(25);

        delayBufferData.updateBuffers(20, threshold, maxBuffer, amountPerPeriod, period, 20, threshold, maxBuffer, amountPerPeriod, period);
        assertEq(delayBufferData.bufferBlocks, 5);
        assertEq(delayBufferData.bufferSeconds, 5);
        assertEq(delayBufferData.roundOffBlocks, 0);
        assertEq(delayBufferData.roundOffSeconds, 0);
        assertEq(delayBufferData.prevDelay.blockNumber, 20);
        assertEq(delayBufferData.prevDelay.delayBlocks, 5);
        assertEq(delayBufferData.prevDelay.timestamp, 20);
        assertEq(delayBufferData.prevDelay.delaySeconds, 5);

        delayBufferData = DelayBuffer.DelayBufferData({
            bufferBlocks: 10,
            bufferSeconds: 10,
            roundOffBlocks: 10,
            roundOffSeconds: 10,
            prevDelay: DelayBuffer.DelayHistory({
                blockNumber: 10,
                timestamp: 10,
                delayBlocks: 3,
                delaySeconds: 3
            })
        });
        uint64 updateTS = delayBufferData.prevDelay.timestamp + period;
        uint64 updateBN = delayBufferData.prevDelay.timestamp + period;
        vm.warp(updateTS);
        vm.roll(updateBN);

        delayBufferData.updateBuffers(updateBN, threshold, maxBuffer, amountPerPeriod, period, updateTS, threshold, maxBuffer, amountPerPeriod, period);
        assertEq(delayBufferData.bufferBlocks, 10 + amountPerPeriod);
        assertEq(delayBufferData.bufferSeconds, 10 + amountPerPeriod);
        assertEq(delayBufferData.roundOffBlocks, 10);
        assertEq(delayBufferData.roundOffSeconds, 10);
        
        assertEq(delayBufferData.prevDelay.blockNumber, updateBN);
        assertEq(delayBufferData.prevDelay.delayBlocks, 0);
        assertEq(delayBufferData.prevDelay.timestamp, updateTS);
        assertEq(delayBufferData.prevDelay.delaySeconds, 0);
    }

    function testPendingDelay() public {
        delayBufferData = DelayBuffer.DelayBufferData({
            bufferBlocks: 10,
            bufferSeconds: 10,
            roundOffBlocks: 10,
            roundOffSeconds: 10,
            prevDelay: DelayBuffer.DelayHistory({
                blockNumber: 10,
                timestamp: 10,
                delayBlocks: 10,
                delaySeconds: 10
            })
        });

        (uint64 bufferBlocks, uint64 bufferSeconds) = delayBufferData.pendingDelay(15, 15, threshold, threshold);

        assertEq(bufferBlocks, 5);
        assertEq(bufferSeconds, 5);
    }
}
