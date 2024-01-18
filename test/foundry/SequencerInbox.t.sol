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
    // cannot reference events outside of the original contract until 0.8.21
    // we currently use 0.8.9
    event MessageDelivered(
        uint256 indexed messageIndex,
        bytes32 indexed beforeInboxAcc,
        address inbox,
        uint8 kind,
        address sender,
        bytes32 messageDataHash,
        uint256 baseFeeL1,
        uint64 timestamp
    );
    event InboxMessageDelivered(uint256 indexed messageNum, bytes data);
    event SequencerBatchDelivered(
        uint256 indexed batchSequenceNumber,
        bytes32 indexed beforeAcc,
        bytes32 indexed afterAcc,
        bytes32 delayedAcc,
        uint256 afterDelayedMessagesRead,
        IBridge.TimeBounds timeBounds,
        IBridge.BatchDataLocation dataLocation
    );


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
    IDataHashReader dummyDataHashReader = IDataHashReader(address(141));
    IBlobBasefeeReader dummyBlobBasefeeReader = IBlobBasefeeReader(address(142));

    function deploy() public returns(SequencerInbox, Bridge) {
        RollupMock rollupMock = new RollupMock(rollupOwner);
        Bridge bridgeImpl = new Bridge();
        Bridge bridge = Bridge(address(new TransparentUpgradeableProxy(address(bridgeImpl), proxyAdmin, "")));

        bridge.initialize(IOwnable(address(rollupMock)));
        vm.prank(rollupOwner);
        bridge.setDelayedInbox(dummyInbox, true);

        SequencerInbox seqInboxImpl = new SequencerInbox(
            maxDataSize,
            dummyDataHashReader,
            dummyBlobBasefeeReader
        );
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
        IBridge.TimeBounds memory timeBounds;
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
        emit MessageDelivered(
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
        emit InboxMessageDelivered(
            delayedMessagesRead,
            spendingReportMsg
        );

        // sequencer batch delivered
        vm.expectEmit();
        emit SequencerBatchDelivered(
            sequenceNumber, 
            beforeAcc,
            afterAcc,
            delayedAcc,
            delayedMessagesRead,
            timeBounds,
            IBridge.BatchDataLocation.TxInput
        );
    }

    function testAddSequencerL2BatchFromOrigin() public {
        (SequencerInbox seqInbox, Bridge bridge) = deploy();
        address delayedInboxSender = address(140);
        uint8 delayedInboxKind = 3;
        bytes32 messageDataHash = RAND.Bytes32();
        bytes memory data = hex"00a4567890"; // CHRIS: TODO: bigger data; // 00 is BROTLI_MESSAGE_HEADER_FLAG

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
        bytes memory data = hex"00567890"; // CHRIS: TODO: bigger data; // 00 is BROTLI_MESSAGE_HEADER_FLAG

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

        bytes memory bigData = bytes.concat(seqInbox.BROTLI_MESSAGE_HEADER_FLAG(), RAND.Bytes(maxDataSize - seqInbox.HEADER_LENGTH()));
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

        bytes memory authenticatedData = bytes.concat(seqInbox.DATA_BLOB_HEADER_FLAG(), data); // TODO: unsure
        vm.expectRevert(abi.encodeWithSelector(InvalidHeaderFlag.selector, authenticatedData[0]));
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

    function testPostUpgradeInitAlreadyInit() public returns (SequencerInbox, SequencerInbox){
        (SequencerInbox seqInbox, ) = deploy();
        SequencerInbox seqInboxImpl = new SequencerInbox(
            maxDataSize,
            dummyDataHashReader,
            dummyBlobBasefeeReader
        );

        vm.expectRevert(abi.encodeWithSelector(AlreadyInit.selector));
        vm.prank(proxyAdmin);
        TransparentUpgradeableProxy(payable(address(seqInbox))).upgradeToAndCall(address(seqInboxImpl), abi.encodeWithSelector(SequencerInbox.postUpgradeInit.selector));
        return (seqInbox, seqInboxImpl);
    }

    function testPostUpgradeInit(uint64 delayBlocks, uint64 futureBlocks, uint64 delaySeconds, uint64 futureSeconds) public {
        vm.assume(delayBlocks != 0 || futureBlocks != 0 || delaySeconds != 0 || futureSeconds != 0);

        (SequencerInbox seqInbox, SequencerInbox seqInboxImpl) = testPostUpgradeInitAlreadyInit();

        vm.expectRevert(abi.encodeWithSelector(AlreadyInit.selector));
        vm.prank(proxyAdmin);
        TransparentUpgradeableProxy(payable(address(seqInbox))).upgradeToAndCall(address(seqInboxImpl), abi.encodeWithSelector(SequencerInbox.postUpgradeInit.selector));

        vm.store(address(seqInbox), bytes32(uint256(4)), bytes32(uint256(delayBlocks))); // slot 4: delayBlocks
        vm.store(address(seqInbox), bytes32(uint256(5)), bytes32(uint256(futureBlocks))); // slot 5: futureBlocks
        vm.store(address(seqInbox), bytes32(uint256(6)), bytes32(uint256(delaySeconds))); // slot 6: delaySeconds
        vm.store(address(seqInbox), bytes32(uint256(7)), bytes32(uint256(futureSeconds))); // slot 7: futureSeconds
        vm.prank(proxyAdmin);
        TransparentUpgradeableProxy(payable(address(seqInbox))).upgradeToAndCall(address(seqInboxImpl), abi.encodeWithSelector(SequencerInbox.postUpgradeInit.selector));

        (uint256 delayBlocks_, uint256 futureBlocks_, uint256 delaySeconds_, uint256 futureSeconds_) = seqInbox.maxTimeVariation();
        assertEq(delayBlocks_, delayBlocks);
        assertEq(futureBlocks_, futureBlocks);
        assertEq(delaySeconds_, delaySeconds);
        assertEq(futureSeconds_, futureSeconds);

        vm.expectRevert(abi.encodeWithSelector(AlreadyInit.selector));
        vm.prank(proxyAdmin);
        TransparentUpgradeableProxy(payable(address(seqInbox))).upgradeToAndCall(address(seqInboxImpl), abi.encodeWithSelector(SequencerInbox.postUpgradeInit.selector));
    }

    function testPostUpgradeInitBadInit(uint256 delayBlocks, uint256 futureBlocks, uint256 delaySeconds, uint256 futureSeconds) public {
        vm.assume(delayBlocks > uint256(type(uint64).max));
        vm.assume(futureBlocks > uint256(type(uint64).max));
        vm.assume(delaySeconds > uint256(type(uint64).max));
        vm.assume(futureSeconds > uint256(type(uint64).max));

        (SequencerInbox seqInbox, SequencerInbox seqInboxImpl) = testPostUpgradeInitAlreadyInit();

        vm.store(address(seqInbox), bytes32(uint256(4)), bytes32(delayBlocks)); // slot 4: delayBlocks
        vm.store(address(seqInbox), bytes32(uint256(5)), bytes32(futureBlocks)); // slot 5: futureBlocks
        vm.store(address(seqInbox), bytes32(uint256(6)), bytes32(delaySeconds)); // slot 6: delaySeconds
        vm.store(address(seqInbox), bytes32(uint256(7)), bytes32(futureSeconds)); // slot 7: futureSeconds
        vm.expectRevert(abi.encodeWithSelector(BadPostUpgradeInit.selector));
        vm.prank(proxyAdmin);
        TransparentUpgradeableProxy(payable(address(seqInbox))).upgradeToAndCall(address(seqInboxImpl), abi.encodeWithSelector(SequencerInbox.postUpgradeInit.selector));
    }
}