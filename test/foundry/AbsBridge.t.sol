// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "./util/TestUtil.sol";
import "../../src/bridge/IBridge.sol";
import "../../src/bridge/ERC20Bridge.sol";
import "../../src/bridge/Bridge.sol";
import "../../src/bridge/ERC20Inbox.sol";
import "../../src/bridge/IEthBridge.sol";
import "../../src/libraries/AddressAliasHelper.sol";
import "../../src/test-helpers/EthVault.sol";

// todo: this might have another more appropriate home
contract ActiveOutboxChecker {
    IBridge public immutable bridge;
    address public activeOutboxDuringCall;

    constructor(IBridge _bridge) {
        bridge = _bridge;
    }

    receive() external payable {
        activeOutboxDuringCall = bridge.activeOutbox();
    }
}

abstract contract AbsBridgeTest is Test {
    IBridge public bridge;

    address public user = address(100);
    address public userB = address(101);

    address public rollup = address(1000);
    address public inbox;
    address public outbox = address(1002);
    address public seqInbox = address(1003);

    /* solhint-disable func-name-mixedcase */
    function test_enqueueSequencerMessage_NoDelayedMsgs() public {
        vm.prank(rollup);
        bridge.setSequencerInbox(seqInbox);

        // enqueue sequencer msg
        vm.prank(seqInbox);
        bytes32 dataHash = keccak256("blob");
        uint256 afterDelayedMessagesRead = 0;
        uint256 prevMessageCount = 0;
        uint256 newMessageCount = 15;
        (uint256 seqMessageIndex, bytes32 beforeAcc, bytes32 delayedAcc, bytes32 acc) = bridge
            .enqueueSequencerMessage(
            dataHash, afterDelayedMessagesRead, prevMessageCount, newMessageCount
        );

        // checks
        assertEq(
            bridge.sequencerReportedSubMessageCount(), newMessageCount, "Invalid newMessageCount"
        );
        bytes32 seqInboxEntry = keccak256(abi.encodePacked(bytes32(0), dataHash, bytes32(0)));
        assertEq(bridge.sequencerInboxAccs(0), seqInboxEntry, "Invalid sequencerInboxAccs entry");
        assertEq(bridge.sequencerMessageCount(), 1, "Invalid sequencerMessageCount");
        assertEq(seqMessageIndex, 0, "Invalid seqMessageIndex");
        assertEq(beforeAcc, 0, "Invalid beforeAcc");
        assertEq(delayedAcc, 0, "Invalid delayedAcc");
        assertEq(acc, seqInboxEntry, "Invalid acc");
    }

    function test_enqueueSequencerMessage_IncludeDelayedMsgs() public {
        vm.prank(rollup);
        bridge.setSequencerInbox(seqInbox);

        // put some msgs to delayed inbox
        vm.startPrank(seqInbox);
        bridge.submitBatchSpendingReport(address(1), keccak256("1"));
        bridge.submitBatchSpendingReport(address(2), keccak256("2"));
        bridge.submitBatchSpendingReport(address(3), keccak256("3"));
        vm.stopPrank();

        // enqueue sequencer msg with 2 delayed msgs
        vm.prank(seqInbox);
        bytes32 dataHash = keccak256("blob");
        uint256 afterDelayedMessagesRead = 2;
        uint256 prevMessageCount = 0;
        uint256 newMessageCount = 15;
        (uint256 seqMessageIndex, bytes32 beforeAcc, bytes32 delayedAcc, bytes32 acc) = bridge
            .enqueueSequencerMessage(
            dataHash, afterDelayedMessagesRead, prevMessageCount, newMessageCount
        );

        // checks
        assertEq(
            bridge.sequencerReportedSubMessageCount(),
            newMessageCount,
            "Invalid sequencerReportedSubMessageCount"
        );
        bytes32 seqInboxEntry =
            keccak256(abi.encodePacked(bytes32(0), dataHash, bridge.delayedInboxAccs(1)));
        assertEq(bridge.sequencerInboxAccs(0), seqInboxEntry, "Invalid sequencerInboxAccs entry");
        assertEq(bridge.sequencerMessageCount(), 1, "Invalid sequencerMessageCount");
        assertEq(seqMessageIndex, 0, "Invalid seqMessageIndex");
        assertEq(beforeAcc, 0, "Invalid beforeAcc");
        assertEq(delayedAcc, bridge.delayedInboxAccs(1), "Invalid delayedAcc");
        assertEq(acc, seqInboxEntry, "Invalid acc");
    }

    function test_enqueueSequencerMessage_SecondEnqueuedMsg() public {
        vm.prank(rollup);
        bridge.setSequencerInbox(seqInbox);

        // put some msgs to delayed inbox and seq inbox
        vm.startPrank(seqInbox);
        bridge.submitBatchSpendingReport(address(1), keccak256("1"));
        bridge.submitBatchSpendingReport(address(2), keccak256("2"));
        bridge.submitBatchSpendingReport(address(3), keccak256("3"));
        bridge.enqueueSequencerMessage(keccak256("seq"), 2, 0, 10);
        vm.stopPrank();

        // enqueue 2nd sequencer msg with additional delayed msgs
        vm.prank(seqInbox);
        bytes32 dataHash = keccak256("blob");
        uint256 afterDelayedMessagesRead = 3;
        uint256 prevMessageCount = 10;
        uint256 newMessageCount = 20;
        (uint256 seqMessageIndex, bytes32 beforeAcc, bytes32 delayedAcc, bytes32 acc) = bridge
            .enqueueSequencerMessage(
            dataHash, afterDelayedMessagesRead, prevMessageCount, newMessageCount
        );

        // checks
        assertEq(
            bridge.sequencerReportedSubMessageCount(),
            newMessageCount,
            "Invalid sequencerReportedSubMessageCount"
        );
        bytes32 seqInboxEntry = keccak256(
            abi.encodePacked(bridge.sequencerInboxAccs(0), dataHash, bridge.delayedInboxAccs(2))
        );
        assertEq(bridge.sequencerInboxAccs(1), seqInboxEntry, "Invalid sequencerInboxAccs entry");
        assertEq(bridge.sequencerMessageCount(), 2, "Invalid sequencerMessageCount");
        assertEq(seqMessageIndex, 1, "Invalid seqMessageIndex");
        assertEq(beforeAcc, bridge.sequencerInboxAccs(0), "Invalid beforeAcc");
        assertEq(delayedAcc, bridge.delayedInboxAccs(2), "Invalid delayedAcc");
        assertEq(acc, seqInboxEntry, "Invalid acc");
    }

    function test_enqueueSequencerMessage_revert_BadSequencerMessageNumber() public {
        vm.prank(rollup);
        bridge.setSequencerInbox(seqInbox);

        // put some msgs to delayed inbox and seq inbox
        vm.startPrank(seqInbox);
        bridge.submitBatchSpendingReport(address(1), keccak256("1"));
        bridge.submitBatchSpendingReport(address(2), keccak256("2"));
        bridge.submitBatchSpendingReport(address(3), keccak256("3"));
        bridge.enqueueSequencerMessage(keccak256("seq"), 2, 0, 10);
        vm.stopPrank();

        //  setting wrong msg counter shall revert
        vm.prank(seqInbox);
        uint256 incorrectPrevMsgCount = 300;
        vm.expectRevert(
            abi.encodeWithSelector(BadSequencerMessageNumber.selector, 10, incorrectPrevMsgCount)
        );
        bridge.enqueueSequencerMessage(keccak256("seq"), 2, incorrectPrevMsgCount, 10);
    }

    function test_enqueueSequencerMessage_revert_NonSeqInboxCall() public {
        // enqueueSequencerMessage shall revert
        vm.expectRevert(abi.encodeWithSelector(NotSequencerInbox.selector, address(this)));
        bridge.enqueueSequencerMessage(keccak256("msg"), 0, 0, 10);
    }

    function test_submitBatchSpendingReport() public {
        address sender = address(250);
        bytes32 messageDataHash = keccak256(abi.encode("msg"));

        vm.prank(rollup);
        bridge.setSequencerInbox(seqInbox);

        // expect event
        vm.expectEmit(true, true, true, true);
        emit MessageDelivered(
            0, 0, seqInbox, 13, sender, messageDataHash, block.basefee, uint64(block.timestamp)
        );

        // submit report
        vm.prank(seqInbox);
        uint256 count = bridge.submitBatchSpendingReport(sender, messageDataHash);

        // checks
        assertEq(count, 0, "Invalid count");
        assertEq(bridge.delayedMessageCount(), 1, "Invalid msg count");
    }

    function test_submitBatchSpendingReport_TwoInRow() public {
        address sender = address(250);
        bytes32 messageDataHash = keccak256(abi.encode("msg"));

        // submit 1st report
        vm.prank(rollup);
        bridge.setSequencerInbox(seqInbox);
        vm.prank(seqInbox);
        bridge.submitBatchSpendingReport(sender, messageDataHash);

        // expect event
        vm.expectEmit(true, true, true, true);
        emit MessageDelivered(
            1,
            bridge.delayedInboxAccs(0),
            seqInbox,
            13,
            sender,
            messageDataHash,
            block.basefee,
            uint64(block.timestamp)
        );

        // submit 2nd report
        vm.prank(seqInbox);
        uint256 count = bridge.submitBatchSpendingReport(sender, messageDataHash);

        // checks
        assertEq(count, 1, "Invalid count");
        assertEq(bridge.delayedMessageCount(), 2, "Invalid msg count");
    }

    function test_submitBatchSpendingReport_revert_NonSeqInboxCall() public {
        // submitBatchSpendingReport shall revert
        vm.expectRevert(abi.encodeWithSelector(NotSequencerInbox.selector, address(this)));
        bridge.submitBatchSpendingReport(address(2), keccak256("msg"));
    }

    function test_setSequencerInbox() public {
        // expect event
        vm.expectEmit(true, true, true, true);
        emit SequencerInboxUpdated(seqInbox);

        // set seqInbox
        vm.prank(address(bridge.rollup()));
        bridge.setSequencerInbox(seqInbox);

        // checks
        assertEq(bridge.sequencerInbox(), seqInbox, "Invalid seqInbox");
    }

    function test_setSequencerInbox_revert_NonOwnerCall() public {
        // mock the owner() call on rollup
        address mockRollupOwner = address(10000);
        vm.mockCall(
            rollup, abi.encodeWithSelector(IOwnable.owner.selector), abi.encode(mockRollupOwner)
        );

        // setSequencerInbox shall revert
        vm.expectRevert(
            abi.encodeWithSelector(
                NotRollupOrOwner.selector, address(this), rollup, mockRollupOwner
            )
        );
        bridge.setSequencerInbox(seqInbox);
    }

    function test_setDelayedInbox_enableInbox() public {
        assertEq(bridge.allowedDelayedInboxes(inbox), false, "Invalid allowedDelayedInboxes");

        // expect event
        vm.expectEmit(true, true, true, true);
        emit InboxToggle(inbox, true);

        // enable inbox
        vm.prank(rollup);
        bridge.setDelayedInbox(inbox, true);

        // checks
        assertEq(bridge.allowedDelayedInboxes(inbox), true, "Invalid allowedDelayedInboxes");
        assertEq(inbox, bridge.allowedDelayedInboxList(0), "Invalid allowedDelayedInboxList");
    }

    function test_setDelayedInbox_disableInbox() public {
        // initially enable inbox
        vm.prank(rollup);
        bridge.setDelayedInbox(inbox, true);
        assertEq(bridge.allowedDelayedInboxes(inbox), true, "Invalid allowedDelayedInboxes");

        // expect event
        vm.expectEmit(true, true, true, true);
        emit InboxToggle(inbox, false);

        // disable inbox
        vm.prank(rollup);
        bridge.setDelayedInbox(inbox, false);

        // checks
        assertEq(bridge.allowedDelayedInboxes(inbox), false, "Invalid allowedDelayedInboxes");
        vm.expectRevert();
        bridge.allowedDelayedInboxList(0);
    }

    function test_setDelayedInbox_ReEnableInbox() public {
        // initially enable inbox
        vm.prank(rollup);
        bridge.setDelayedInbox(inbox, true);
        assertEq(bridge.allowedDelayedInboxes(inbox), true, "Invalid allowedDelayedInboxes");

        // expect event
        vm.expectEmit(true, true, true, true);
        emit InboxToggle(inbox, true);

        // enable again inbox
        vm.prank(rollup);
        bridge.setDelayedInbox(inbox, true);

        // checks
        assertEq(bridge.allowedDelayedInboxes(inbox), true, "Invalid allowedDelayedInboxes");
        assertEq(inbox, bridge.allowedDelayedInboxList(0), "Invalid allowedDelayedInboxList");
    }

    function test_setDelayedInbox_ReDisableInbox() public {
        assertEq(bridge.allowedDelayedInboxes(inbox), false, "Invalid allowedDelayedInboxes");

        // expect event
        vm.expectEmit(true, true, true, true);
        emit InboxToggle(inbox, false);

        // disable again inbox
        vm.prank(rollup);
        bridge.setDelayedInbox(inbox, false);

        // checks
        assertEq(bridge.allowedDelayedInboxes(inbox), false, "Invalid allowedDelayedInboxes");
        vm.expectRevert();
        bridge.allowedDelayedInboxList(0);
    }

    function test_setDelayedInbox_revert_NonOwnerCall() public {
        // mock the owner() call on rollup
        address mockRollupOwner = address(10000);
        vm.mockCall(
            rollup, abi.encodeWithSelector(IOwnable.owner.selector), abi.encode(mockRollupOwner)
        );

        // setDelayedInbox shall revert
        vm.expectRevert(
            abi.encodeWithSelector(
                NotRollupOrOwner.selector, address(this), rollup, mockRollupOwner
            )
        );
        bridge.setDelayedInbox(inbox, true);
    }

    function test_setOutbox_EnableOutbox() public {
        assertEq(bridge.allowedOutboxes(outbox), false, "Invalid allowedOutboxes");

        // expect event
        vm.expectEmit(true, true, true, true);
        emit OutboxToggle(outbox, true);

        // enable outbox
        vm.prank(rollup);
        bridge.setOutbox(outbox, true);

        // checks
        assertEq(bridge.allowedOutboxes(outbox), true, "Invalid allowedOutboxes");
        assertEq(outbox, bridge.allowedOutboxList(0), "Invalid allowedOutboxList");
    }

    function test_setOutbox_DisableOutbox() public {
        // initially enable outbox
        vm.prank(rollup);
        bridge.setOutbox(outbox, true);
        assertEq(bridge.allowedOutboxes(outbox), true, "Invalid allowedOutboxes");

        // expect event
        vm.expectEmit(true, true, true, true);
        emit OutboxToggle(outbox, false);

        //  disable outbox
        vm.prank(rollup);
        bridge.setOutbox(outbox, false);

        // checks
        assertEq(bridge.allowedOutboxes(outbox), false, "Invalid allowedOutboxes");
        vm.expectRevert();
        bridge.allowedOutboxList(0);
    }

    function test_setOutbox_ReEnableOutbox() public {
        // initially enable outbox
        vm.prank(rollup);
        bridge.setOutbox(outbox, true);
        assertEq(bridge.allowedOutboxes(outbox), true, "Invalid allowedOutboxes");

        // expect event
        vm.expectEmit(true, true, true, true);
        emit OutboxToggle(outbox, true);

        // enable outbox
        vm.prank(rollup);
        bridge.setOutbox(outbox, true);

        // checks
        assertEq(bridge.allowedOutboxes(outbox), true, "Invalid allowedOutboxes");
        assertEq(outbox, bridge.allowedOutboxList(0), "Invalid allowedOutboxList");
    }

    function test_setOutbox_ReDisableOutbox() public {
        // expect event
        vm.expectEmit(true, true, true, true);
        emit OutboxToggle(outbox, false);

        //  disable outbox
        vm.prank(rollup);
        bridge.setOutbox(outbox, false);

        // checks
        assertEq(bridge.allowedOutboxes(outbox), false, "Invalid allowedOutboxes");
        vm.expectRevert();
        bridge.allowedOutboxList(0);
    }

    function test_setOutbox_revert_NonOwnerCall() public {
        // mock the owner() call on rollup
        address mockRollupOwner = address(10000);
        vm.mockCall(
            rollup, abi.encodeWithSelector(IOwnable.owner.selector), abi.encode(mockRollupOwner)
        );

        // setOutbox shall revert
        vm.expectRevert(
            abi.encodeWithSelector(
                NotRollupOrOwner.selector, address(this), rollup, mockRollupOwner
            )
        );
        bridge.setOutbox(outbox, true);
    }

    function test_setOutbox_revert_InvalidOutboxSet() public {
        address invalidOutbox = address(type(uint160).max);

        // setOutbox shall revert
        vm.expectRevert(abi.encodeWithSelector(InvalidOutboxSet.selector, invalidOutbox));
        vm.prank(rollup);
        bridge.setOutbox(invalidOutbox, true);
    }

    function test_setSequencerReportedSubMessageCount() public {
        uint256 newCount = 1234;

        vm.prank(rollup);
        AbsBridge(address(bridge)).setSequencerReportedSubMessageCount(newCount);

        assertEq(
            bridge.sequencerReportedSubMessageCount(),
            newCount,
            "Invalid sequencerReportedSubMessageCount"
        );
    }

    function test_setSequencerReportedSubMessageCount_revert_NonOwnerCall() public {
        // mock the owner() call on rollup
        address mockRollupOwner = address(10000);
        vm.mockCall(
            rollup, abi.encodeWithSelector(IOwnable.owner.selector), abi.encode(mockRollupOwner)
        );

        // setOutbox shall revert
        vm.expectRevert(
            abi.encodeWithSelector(
                NotRollupOrOwner.selector, address(this), rollup, mockRollupOwner
            )
        );
        AbsBridge(address(bridge)).setSequencerReportedSubMessageCount(123);
    }

    function test_updateRollupAddress() public {
        vm.prank(rollup);
        bridge.updateRollupAddress(IOwnable(address(1337)));
        assertEq(address(bridge.rollup()), address(1337), "Invalid rollup");
    }

    function test_updateRollupAddress_revert_NotOwner() public {
        vm.mockCall(
            address(rollup),
            0,
            abi.encodeWithSelector(IOwnable.owner.selector),
            abi.encode(address(1337))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                NotRollupOrOwner.selector, address(this), address(rollup), address(1337)
            )
        );
        bridge.updateRollupAddress(IOwnable(address(1234)));
    }

    function test_setDelayedInbox_disableMiddleFromThree() public {
        address inboxA = address(2001);
        address inboxB = address(2002);
        address inboxC = address(2003);

        vm.startPrank(rollup);
        bridge.setDelayedInbox(inboxA, true);
        bridge.setDelayedInbox(inboxB, true);
        bridge.setDelayedInbox(inboxC, true);

        // disable the middle inbox (index 1) — last element (C) swaps into its slot
        bridge.setDelayedInbox(inboxB, false);
        assertEq(bridge.allowedDelayedInboxList(0), inboxA, "A should remain at index 0");
        assertEq(bridge.allowedDelayedInboxList(1), inboxC, "C should move to index 1");
        assertEq(bridge.allowedDelayedInboxes(inboxA), true, "A should still be allowed");
        assertEq(bridge.allowedDelayedInboxes(inboxB), false, "B should be disallowed");
        assertEq(bridge.allowedDelayedInboxes(inboxC), true, "C should still be allowed");

        // disable C — verifies the swapped element's index was updated correctly
        bridge.setDelayedInbox(inboxC, false);
        assertEq(bridge.allowedDelayedInboxList(0), inboxA, "A should remain at index 0 after second disable");
        assertEq(bridge.allowedDelayedInboxes(inboxA), true, "A should still be allowed");
        assertEq(bridge.allowedDelayedInboxes(inboxB), false, "B should be disallowed");
        assertEq(bridge.allowedDelayedInboxes(inboxC), false, "C should be disallowed");
        vm.stopPrank();
    }

    function test_setDelayedInbox_disableFirstFromThree() public {
        address inboxA = address(2001);
        address inboxB = address(2002);
        address inboxC = address(2003);

        vm.startPrank(rollup);
        bridge.setDelayedInbox(inboxA, true);
        bridge.setDelayedInbox(inboxB, true);
        bridge.setDelayedInbox(inboxC, true);

        // disable first inbox (index 0) — C swaps into slot 0
        bridge.setDelayedInbox(inboxA, false);
        assertEq(bridge.allowedDelayedInboxList(0), inboxC, "C should move to index 0");
        assertEq(bridge.allowedDelayedInboxList(1), inboxB, "B should remain at index 1");
        assertEq(bridge.allowedDelayedInboxes(inboxA), false, "A should be disallowed");
        assertEq(bridge.allowedDelayedInboxes(inboxB), true, "B should still be allowed");
        assertEq(bridge.allowedDelayedInboxes(inboxC), true, "C should still be allowed");
        

        // disable C — verifies the swapped element's index was updated correctly
        bridge.setDelayedInbox(inboxC, false);
        assertEq(bridge.allowedDelayedInboxList(0), inboxB, "B should remain at index 0");
        assertEq(bridge.allowedDelayedInboxes(inboxA), false, "A should be disallowed");
        assertEq(bridge.allowedDelayedInboxes(inboxB), true, "B should still be allowed");
        assertEq(bridge.allowedDelayedInboxes(inboxC), false, "C should be disallowed");
        vm.stopPrank();
    }

    function test_setOutbox_disableMiddleFromThree() public {
        address outboxA = address(3001);
        address outboxB = address(3002);
        address outboxC = address(3003);

        vm.startPrank(rollup);
        bridge.setOutbox(outboxA, true);
        bridge.setOutbox(outboxB, true);
        bridge.setOutbox(outboxC, true);

        // disable middle outbox (index 1) — C swaps into slot 1
        bridge.setOutbox(outboxB, false);
        assertEq(bridge.allowedOutboxList(0), outboxA, "A should remain at index 0");
        assertEq(bridge.allowedOutboxList(1), outboxC, "C should move to index 1");
        assertEq(bridge.allowedOutboxes(outboxA), true, "A should still be allowed");
        assertEq(bridge.allowedOutboxes(outboxB), false, "B should be disallowed");
        assertEq(bridge.allowedOutboxes(outboxC), true, "C should still be allowed");

        // disable C — verifies the swapped element's index was updated correctly
        bridge.setOutbox(outboxC, false);
        assertEq(bridge.allowedOutboxList(0), outboxA, "A should remain at index 0 after second disable");
        assertEq(bridge.allowedOutboxes(outboxA), true, "A should still be allowed");
        assertEq(bridge.allowedOutboxes(outboxB), false, "B should be disallowed");
        assertEq(bridge.allowedOutboxes(outboxC), false, "C should be disallowed");
        vm.stopPrank();
    }

    function test_setOutbox_disableFirstFromThree() public {
        address outboxA = address(3001);
        address outboxB = address(3002);
        address outboxC = address(3003);

        vm.startPrank(rollup);
        bridge.setOutbox(outboxA, true);
        bridge.setOutbox(outboxB, true);
        bridge.setOutbox(outboxC, true);

        // disable first outbox (index 0) — C swaps into slot 0
        bridge.setOutbox(outboxA, false);
        assertEq(bridge.allowedOutboxList(0), outboxC, "C should move to index 0");
        assertEq(bridge.allowedOutboxList(1), outboxB, "B should remain at index 1");
        assertEq(bridge.allowedOutboxes(outboxA), false, "A should be disallowed");
        assertEq(bridge.allowedOutboxes(outboxB), true, "B should still be allowed");
        assertEq(bridge.allowedOutboxes(outboxC), true, "C should still be allowed");

        // disable C — verifies the swapped element's index was updated correctly
        bridge.setOutbox(outboxC, false);
        assertEq(bridge.allowedOutboxList(0), outboxB, "B should remain at index 0");
        assertEq(bridge.allowedOutboxes(outboxA), false, "A should be disallowed");
        assertEq(bridge.allowedOutboxes(outboxB), true, "B should still be allowed");
        assertEq(bridge.allowedOutboxes(outboxC), false, "C should be disallowed");
        vm.stopPrank();
    }

    function test_enqueueSequencerMessage_ThirdEnqueuedMsg() public {
        vm.prank(rollup);
        bridge.setSequencerInbox(seqInbox);

        vm.startPrank(seqInbox);
        bridge.submitBatchSpendingReport(address(1), keccak256("1"));
        bridge.enqueueSequencerMessage(keccak256("seq1"), 0, 0, 10);
        bridge.enqueueSequencerMessage(keccak256("seq2"), 0, 10, 20);

        // 3rd sequencer message — beforeAcc should be sequencerInboxAccs[1], not [0]
        bytes32 dataHash = keccak256("seq3");
        (uint256 seqMessageIndex, bytes32 beforeAcc,,) =
            bridge.enqueueSequencerMessage(dataHash, 1, 20, 30);
        vm.stopPrank();

        assertEq(seqMessageIndex, 2, "Invalid seqMessageIndex");
        assertEq(beforeAcc, bridge.sequencerInboxAccs(1), "beforeAcc should be second seq entry");
        assertTrue(beforeAcc != bridge.sequencerInboxAccs(0), "beforeAcc should differ from first seq entry");
    }

    // test that the third delayed inbox acc chains from the second, not the first
    function test_accumulatesFromPrev() public {
        vm.prank(rollup);
        bridge.setSequencerInbox(seqInbox);

        vm.startPrank(seqInbox);
        bridge.submitBatchSpendingReport(address(1), keccak256("1"));
        bridge.submitBatchSpendingReport(address(2), keccak256("2"));
        bridge.submitBatchSpendingReport(address(3), keccak256("3"));
        vm.stopPrank();

        // verify the third accumulator chains from the second (not the first)
        bytes32 acc0 = bridge.delayedInboxAccs(0);
        bytes32 acc1 = bridge.delayedInboxAccs(1);
        bytes32 acc2 = bridge.delayedInboxAccs(2);

        // acc2 should be derived from acc1, not acc0
        // recompute: messageHash for 3rd message (count=2 at time of insertion)
        // todo: avoid magic number use
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                uint8(13), address(3), uint64(block.number), uint64(block.timestamp),
                uint256(2), block.basefee, keccak256("3")
            )
        );
        bytes32 expectedAcc2 = keccak256(abi.encodePacked(acc1, msgHash));
        assertEq(acc2, expectedAcc2, "Third accumulator should chain from second");

        // sanity: acc2 should differ if computed from acc0
        bytes32 wrongAcc2 = keccak256(abi.encodePacked(acc0, msgHash));
        assertTrue(acc2 != wrongAcc2, "Accumulator should not chain from first");
    }

    /**
     *
     * Event declarations
     *
     */
    event SequencerInboxUpdated(address newSequencerInbox);
    event InboxToggle(address indexed inbox, bool enabled);
    event OutboxToggle(address indexed outbox, bool enabled);
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
    event BridgeCallTriggered(
        address indexed outbox, address indexed to, uint256 value, bytes data
    );
}
