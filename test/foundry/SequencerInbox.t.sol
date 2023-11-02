// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "./util/TestUtil.sol";
import "../../src/bridge/Bridge.sol";
import "../../src/bridge/SequencerInbox.sol";

contract RollupMock {
    address immutable public owner;
    constructor(address _owner) {
        owner = _owner;
    }
}

contract SequencerInboxTest is Test {
    Random RAND = new Random();
    address rollupOwner = address(137);
    uint256 maxDataSize = 10000;
    ISequencerInbox.MaxTimeVariation maxTimeVariation = ISequencerInbox.MaxTimeVariation({
        delayBlocks: 10,
        futureBlocks: 10,
        delaySeconds: 100,
        futureSeconds: 100
    });
    address dummyInbox = address(139);
    address proxyAdmin = address(140);
    


    function deploy() public returns(SequencerInbox, Bridge) {
        RollupMock rollupMock = new RollupMock(rollupOwner);
        Bridge bridgeImpl = new Bridge();
        Bridge bridge = Bridge(address(new TransparentUpgradeableProxy(address(bridgeImpl), proxyAdmin, "")));

        bridge.initialize(IOwnable(address(rollupMock)));
        vm.prank(rollupOwner);
        bridge.setDelayedInbox(dummyInbox, true);

        SequencerInbox seqInboxImpl = new SequencerInbox(maxDataSize);
        SequencerInbox seqInbox = SequencerInbox(address(new TransparentUpgradeableProxy(address(seqInboxImpl), proxyAdmin, "")));
        seqInbox.initialize(
            bridge,
            maxTimeVariation
        );

        vm.prank(rollupOwner);
        seqInbox.setIsBatchPoster(tx.origin, true);

        vm.prank(rollupOwner);
        bridge.setSequencerInbox(address(seqInbox));

        return (seqInbox, bridge);
    }

    function expectEvents(Bridge bridge, SequencerInbox seqInbox, bytes memory data) internal {
        uint256 delayedMessagesRead = bridge.delayedMessageCount();
        uint256 sequenceNumber = bridge.sequencerMessageCount();
        ISequencerInbox.TimeBounds memory timeBounds;
        if (block.timestamp > maxTimeVariation.delaySeconds) {
            timeBounds.minTimestamp = uint64(block.timestamp - maxTimeVariation.delaySeconds);
        }
        timeBounds.maxTimestamp = uint64(block.timestamp + maxTimeVariation.futureSeconds);
        if (block.number > maxTimeVariation.delayBlocks) {
            timeBounds.minBlockNumber = uint64(block.number - maxTimeVariation.delayBlocks);
        }
        timeBounds.maxBlockNumber = uint64(block.number + maxTimeVariation.futureBlocks);
        bytes32 dataHash = keccak256(bytes.concat(abi.encodePacked(
            timeBounds.minTimestamp,
            timeBounds.maxTimestamp,
            timeBounds.minBlockNumber,
            timeBounds.maxBlockNumber,
            uint64(delayedMessagesRead)
        ), data));

        bytes memory spendingReportMsg  = abi.encodePacked(
            block.timestamp,
            msg.sender,
            dataHash,
            sequenceNumber,
            block.basefee
        );
        bytes32 beforeAcc = bytes32(0);
        bytes32 delayedAcc = bridge.delayedInboxAccs(delayedMessagesRead - 1);
        bytes32 afterAcc = keccak256(abi.encodePacked(beforeAcc, dataHash, delayedAcc));

        // spending report
        vm.expectEmit();
        emit IBridge.MessageDelivered(
            delayedMessagesRead,
            delayedAcc,
            address(seqInbox),
            L1MessageType_batchPostingReport,
            tx.origin,
            keccak256(spendingReportMsg),
            block.basefee,
            uint64(block.timestamp)
        );

        // spending report event in seq inbox
        vm.expectEmit();
        emit IDelayedMessageProvider.InboxMessageDelivered(
            delayedMessagesRead,
            spendingReportMsg
        );

        // sequencer batch delivered
        vm.expectEmit();
        emit ISequencerInbox.SequencerBatchDelivered(
            sequenceNumber, 
            beforeAcc,
            afterAcc,
            delayedAcc,
            delayedMessagesRead,
            timeBounds,
            ISequencerInbox.BatchDataLocation.TxInput
        );
    }

    function testAddSequencerL2BatchFromOrigin() public {
        (SequencerInbox seqInbox, Bridge bridge) = deploy();
        address delayedInboxSender = address(140);
        uint8 delayedInboxKind = 3;
        bytes32 messageDataHash = RAND.Bytes32();
        bytes memory data = hex"a4567890"; // CHRIS: TODO: bigger data;

        vm.prank(dummyInbox);
        bridge.enqueueDelayedMessage(
            delayedInboxKind,
            delayedInboxSender,
            messageDataHash
        );

        uint256 subMessageCount = bridge.sequencerReportedSubMessageCount();
        uint256 sequenceNumber = bridge.sequencerMessageCount();
        uint256 delayedMessagesRead = bridge.delayedMessageCount();

        expectEvents(bridge, seqInbox, data);

        vm.prank(tx.origin);
        seqInbox.addSequencerL2BatchFromOrigin(
            sequenceNumber,
            data,
            delayedMessagesRead,
            IGasRefunder(address(0)),
            subMessageCount,
            subMessageCount + 1
        );
    }

    function testAddSequencerL2BatchFromOriginRevers() public {
        (SequencerInbox seqInbox, Bridge bridge) = deploy();
        address delayedInboxSender = address(140);
        uint8 delayedInboxKind = 3;
        bytes32 messageDataHash = RAND.Bytes32();
        bytes memory data = hex"a4567890"; // CHRIS: TODO: bigger data;

        vm.prank(dummyInbox);
        bridge.enqueueDelayedMessage(
            delayedInboxKind,
            delayedInboxSender,
            messageDataHash
        );

        uint256 subMessageCount = bridge.sequencerReportedSubMessageCount();
        uint256 sequenceNumber = bridge.sequencerMessageCount();
        uint256 delayedMessagesRead = bridge.delayedMessageCount();

        vm.expectRevert(abi.encodeWithSelector(NotOrigin.selector));
        seqInbox.addSequencerL2BatchFromOrigin(
            sequenceNumber,
            data,
            delayedMessagesRead,
            IGasRefunder(address(0)),
            subMessageCount,
            subMessageCount + 1
        );


        vm.prank(rollupOwner);
        seqInbox.setIsBatchPoster(tx.origin, false);

        vm.expectRevert(abi.encodeWithSelector(NotBatchPoster.selector));
        vm.prank(tx.origin);
        seqInbox.addSequencerL2BatchFromOrigin(
            sequenceNumber,
            data,
            delayedMessagesRead,
            IGasRefunder(address(0)),
            subMessageCount,
            subMessageCount + 1
        );

        vm.prank(rollupOwner);
        seqInbox.setIsBatchPoster(tx.origin, true);

        bytes memory bigData = bytes.concat(hex"20", RAND.Bytes(maxDataSize - seqInbox.HEADER_LENGTH()));
        vm.expectRevert(abi.encodeWithSelector(DataTooLarge.selector, bigData.length + seqInbox.HEADER_LENGTH(), maxDataSize));
        vm.prank(tx.origin);
        seqInbox.addSequencerL2BatchFromOrigin(
            sequenceNumber,
            bigData,
            delayedMessagesRead,
            IGasRefunder(address(0)),
            subMessageCount,
            subMessageCount + 1
        );

        bytes memory authenticatedData = bytes.concat(seqInbox.DATA_AUTHENTICATED_FLAG(), data);
        vm.expectRevert(abi.encodeWithSelector(DataNotAuthenticated.selector));
        vm.prank(tx.origin);
        seqInbox.addSequencerL2BatchFromOrigin(
            sequenceNumber,
            authenticatedData,
            delayedMessagesRead,
            IGasRefunder(address(0)),
            subMessageCount,
            subMessageCount + 1
        );

        vm.expectRevert(abi.encodeWithSelector(BadSequencerNumber.selector, sequenceNumber, sequenceNumber + 5));
        vm.prank(tx.origin);
        seqInbox.addSequencerL2BatchFromOrigin(
            sequenceNumber + 5,
            data,
            delayedMessagesRead,
            IGasRefunder(address(0)),
            subMessageCount,
            subMessageCount + 1
        );
    }
}