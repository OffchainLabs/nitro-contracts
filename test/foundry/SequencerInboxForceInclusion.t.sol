// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "./util/TestUtil.sol";
import "../../src/bridge/Bridge.sol";
import "../../src/bridge/Inbox.sol";
import "../../src/bridge/IInbox.sol";
import "../../src/bridge/SequencerInbox.sol";
import "../../src/bridge/IEthBridge.sol";
import "../../src/bridge/Messages.sol";
import "../../src/libraries/AddressAliasHelper.sol";
import {
    L2_MSG,
    L2MessageType_unsignedEOATx
} from "../../src/libraries/MessageTypes.sol";
import {
    DelayedBackwards,
    ForceIncludeBlockTooSoon,
    IncorrectMessagePreimage
} from "../../src/libraries/Error.sol";

contract ForceInclusionRollupMock {
    address public immutable owner;

    constructor(address _owner) {
        owner = _owner;
    }
}

/// forge-config: default.allow_internal_expect_revert = true
contract SequencerInboxForceInclusionTest is Test {
    event SequencerBatchDelivered(
        uint256 indexed batchSequenceNumber,
        bytes32 indexed beforeAcc,
        bytes32 indexed afterAcc,
        bytes32 delayedAcc,
        uint256 afterDelayedMessagesRead,
        IBridge.TimeBounds timeBounds,
        IBridge.BatchDataLocation dataLocation
    );
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

    Bridge public bridge;
    Inbox public inbox;
    SequencerInbox public seqInbox;

    address rollupOwner = address(137);
    address user = address(1000);
    address batchPoster = address(2000);
    address proxyAdmin = address(140);
    IReader4844 dummyReader4844 = IReader4844(address(137));

    uint256 constant MAX_DATA_SIZE = 117964;
    uint64 constant DELAY_BLOCKS = 10;
    uint64 constant DELAY_SECONDS = 100;

    struct DelayedMsgInfo {
        uint8 kind;
        address sender;
        uint64 blockNumber;
        uint64 blockTimestamp;
        uint256 baseFeeL1;
        bytes32 messageDataHash;
        uint256 count; // the index+1 (i.e., totalDelayedMessagesRead after this msg)
    }

    function setUp() public {
        // deploy rollup mock
        ForceInclusionRollupMock rollupMock = new ForceInclusionRollupMock(rollupOwner);

        // deploy bridge via proxy
        Bridge bridgeImpl = new Bridge();
        bridge = Bridge(
            address(new TransparentUpgradeableProxy(address(bridgeImpl), proxyAdmin, ""))
        );
        bridge.initialize(IOwnable(address(rollupMock)));

        // deploy sequencer inbox via proxy (not delay bufferable)
        SequencerInbox seqInboxImpl = new SequencerInbox(
            MAX_DATA_SIZE,
            dummyReader4844,
            false,
            false
        );
        seqInbox = SequencerInbox(
            address(new TransparentUpgradeableProxy(address(seqInboxImpl), proxyAdmin, ""))
        );
        ISequencerInbox.MaxTimeVariation memory mtv = ISequencerInbox.MaxTimeVariation({
            delayBlocks: DELAY_BLOCKS,
            futureBlocks: 10,
            delaySeconds: DELAY_SECONDS,
            futureSeconds: 3000
        });
        BufferConfig memory bufferConfig = BufferConfig({threshold: 0, max: 0, replenishRateInBasis: 0});
        seqInbox.initialize(bridge, mtv, bufferConfig, IFeeTokenPricer(address(0)));

        // deploy inbox via proxy
        Inbox inboxImpl = new Inbox(MAX_DATA_SIZE);
        inbox = Inbox(
            address(new TransparentUpgradeableProxy(address(inboxImpl), proxyAdmin, ""))
        );
        inbox.initialize(bridge, ISequencerInbox(address(seqInbox)));

        // configure bridge
        vm.startPrank(rollupOwner);
        bridge.setDelayedInbox(address(inbox), true);
        bridge.setSequencerInbox(address(seqInbox));
        seqInbox.setIsBatchPoster(batchPoster, true);
        vm.stopPrank();

        // fund user
        vm.deal(user, 10 ether);
    }

    function _sendDelayedL2Msg(bytes memory msgData) internal returns (DelayedMsgInfo memory info) {
        uint256 countBefore = bridge.delayedMessageCount();

        vm.prank(user, user);
        inbox.sendL2Message(msgData);

        uint256 countAfter = bridge.delayedMessageCount();
        assertEq(countAfter, countBefore + 1, "Delayed msg count should increment");

        // The delayed message was recorded at the current block
        address aliasedSender = AddressAliasHelper.applyL1ToL2Alias(user);
        bytes32 messageDataHash = keccak256(msgData);

        info = DelayedMsgInfo({
            kind: L2_MSG,
            sender: aliasedSender,
            blockNumber: uint64(block.number),
            blockTimestamp: uint64(block.timestamp),
            baseFeeL1: block.basefee,
            messageDataHash: messageDataHash,
            count: countAfter
        });
    }

    function _sendDelayedUnsignedTx(
        uint256 gasLimit,
        uint256 maxFeePerGas,
        uint256 nonce,
        address to,
        uint256 value,
        bytes memory data
    ) internal returns (DelayedMsgInfo memory info) {
        uint256 countBefore = bridge.delayedMessageCount();

        vm.prank(user, user);
        inbox.sendUnsignedTransaction(gasLimit, maxFeePerGas, nonce, to, value, data);

        uint256 countAfter = bridge.delayedMessageCount();
        assertEq(countAfter, countBefore + 1);

        address aliasedSender = AddressAliasHelper.applyL1ToL2Alias(user);
        bytes32 messageDataHash = keccak256(
            abi.encodePacked(
                L2MessageType_unsignedEOATx,
                gasLimit,
                maxFeePerGas,
                nonce,
                uint256(uint160(to)),
                value,
                data
            )
        );

        info = DelayedMsgInfo({
            kind: L2_MSG,
            sender: aliasedSender,
            blockNumber: uint64(block.number),
            blockTimestamp: uint64(block.timestamp),
            baseFeeL1: block.basefee,
            messageDataHash: messageDataHash,
            count: countAfter
        });
    }

    // --- Force inclusion happy path ---

    function test_forceInclusion_happyPath() public {
        DelayedMsgInfo memory msg1 = _sendDelayedL2Msg(abi.encodePacked("hello"));

        // advance past the delay
        vm.roll(block.number + DELAY_BLOCKS + 1);
        vm.warp(block.timestamp + DELAY_SECONDS + 1);

        uint256 batchCountBefore = seqInbox.batchCount();

        seqInbox.forceInclusion(
            msg1.count,
            msg1.kind,
            [msg1.blockNumber, msg1.blockTimestamp],
            msg1.baseFeeL1,
            msg1.sender,
            msg1.messageDataHash
        );

        assertEq(seqInbox.totalDelayedMessagesRead(), msg1.count, "totalDelayedMessagesRead mismatch");
        assertEq(seqInbox.batchCount(), batchCountBefore + 1, "batchCount should increment");
    }

    // --- ForceIncludeBlockTooSoon ---

    function test_forceInclusion_revert_BlockTooSoon() public {
        DelayedMsgInfo memory msg1 = _sendDelayedL2Msg(abi.encodePacked("hello"));

        // advance less than delay
        vm.roll(block.number + DELAY_BLOCKS - 1);

        vm.expectRevert(ForceIncludeBlockTooSoon.selector);
        seqInbox.forceInclusion(
            msg1.count,
            msg1.kind,
            [msg1.blockNumber, msg1.blockTimestamp],
            msg1.baseFeeL1,
            msg1.sender,
            msg1.messageDataHash
        );
    }

    // --- DelayedBackwards ---

    function test_forceInclusion_revert_DelayedBackwards() public {
        DelayedMsgInfo memory msg1 = _sendDelayedL2Msg(abi.encodePacked("hello"));

        vm.roll(block.number + DELAY_BLOCKS + 1);
        vm.warp(block.timestamp + DELAY_SECONDS + 1);

        // first force include succeeds
        seqInbox.forceInclusion(
            msg1.count,
            msg1.kind,
            [msg1.blockNumber, msg1.blockTimestamp],
            msg1.baseFeeL1,
            msg1.sender,
            msg1.messageDataHash
        );

        // trying again with same count should revert DelayedBackwards
        vm.expectRevert(DelayedBackwards.selector);
        seqInbox.forceInclusion(
            msg1.count,
            msg1.kind,
            [msg1.blockNumber, msg1.blockTimestamp],
            msg1.baseFeeL1,
            msg1.sender,
            msg1.messageDataHash
        );
    }

    // --- IncorrectMessagePreimage ---

    function test_forceInclusion_revert_IncorrectMessagePreimage() public {
        DelayedMsgInfo memory msg1 = _sendDelayedL2Msg(abi.encodePacked("hello"));

        vm.roll(block.number + DELAY_BLOCKS + 1);
        vm.warp(block.timestamp + DELAY_SECONDS + 1);

        // pass wrong messageDataHash
        vm.expectRevert(IncorrectMessagePreimage.selector);
        seqInbox.forceInclusion(
            msg1.count,
            msg1.kind,
            [msg1.blockNumber, msg1.blockTimestamp],
            msg1.baseFeeL1,
            msg1.sender,
            bytes32(uint256(0xdeadbeef))
        );
    }

    // --- Sequential force includes ---

    function test_forceInclusion_sequential() public {
        DelayedMsgInfo memory msg1 = _sendDelayedL2Msg(abi.encodePacked("msg1"));
        DelayedMsgInfo memory msg2 = _sendDelayedL2Msg(abi.encodePacked("msg2"));

        vm.roll(block.number + DELAY_BLOCKS + 1);
        vm.warp(block.timestamp + DELAY_SECONDS + 1);

        // force include first message
        seqInbox.forceInclusion(
            msg1.count,
            msg1.kind,
            [msg1.blockNumber, msg1.blockTimestamp],
            msg1.baseFeeL1,
            msg1.sender,
            msg1.messageDataHash
        );
        assertEq(seqInbox.totalDelayedMessagesRead(), msg1.count);
        assertEq(seqInbox.batchCount(), 1);

        // force include second message
        seqInbox.forceInclusion(
            msg2.count,
            msg2.kind,
            [msg2.blockNumber, msg2.blockTimestamp],
            msg2.baseFeeL1,
            msg2.sender,
            msg2.messageDataHash
        );
        assertEq(seqInbox.totalDelayedMessagesRead(), msg2.count);
        assertEq(seqInbox.batchCount(), 2);
    }

    // --- Batch force include (3 at once) ---

    function test_forceInclusion_threeAtOnce() public {
        _sendDelayedL2Msg(abi.encodePacked("a"));
        _sendDelayedL2Msg(abi.encodePacked("b"));
        DelayedMsgInfo memory msg3 = _sendDelayedL2Msg(abi.encodePacked("c"));

        vm.roll(block.number + DELAY_BLOCKS + 1);
        vm.warp(block.timestamp + DELAY_SECONDS + 1);

        // force include all 3 at once by specifying last msg's data
        seqInbox.forceInclusion(
            msg3.count,
            msg3.kind,
            [msg3.blockNumber, msg3.blockTimestamp],
            msg3.baseFeeL1,
            msg3.sender,
            msg3.messageDataHash
        );
        assertEq(seqInbox.totalDelayedMessagesRead(), 3);
        assertEq(seqInbox.batchCount(), 1);
    }

    // --- Force include using sendUnsignedTransaction ---

    function test_forceInclusion_sendUnsignedTx() public {
        DelayedMsgInfo memory msg1 = _sendDelayedUnsignedTx(
            1000000,  // gasLimit
            21 gwei,  // maxFeePerGas
            0,        // nonce
            user,     // to
            10,       // value
            hex"1010" // data
        );

        vm.roll(block.number + DELAY_BLOCKS + 1);
        vm.warp(block.timestamp + DELAY_SECONDS + 1);

        seqInbox.forceInclusion(
            msg1.count,
            msg1.kind,
            [msg1.blockNumber, msg1.blockTimestamp],
            msg1.baseFeeL1,
            msg1.sender,
            msg1.messageDataHash
        );

        assertEq(seqInbox.totalDelayedMessagesRead(), msg1.count);
        assertEq(seqInbox.batchCount(), 1);
    }

    // --- Verify SequencerBatchDelivered event is emitted ---

    function test_forceInclusion_emitsEvent() public {
        DelayedMsgInfo memory msg1 = _sendDelayedL2Msg(abi.encodePacked("event test"));

        vm.roll(block.number + DELAY_BLOCKS + 1);
        vm.warp(block.timestamp + DELAY_SECONDS + 1);

        // just check that the event is emitted (indexed topics only)
        vm.expectEmit(true, false, false, false);
        emit SequencerBatchDelivered(
            0,
            bytes32(0),
            bytes32(0),
            bytes32(0),
            0,
            IBridge.TimeBounds(0, 0, 0, 0),
            IBridge.BatchDataLocation.NoData
        );

        seqInbox.forceInclusion(
            msg1.count,
            msg1.kind,
            [msg1.blockNumber, msg1.blockTimestamp],
            msg1.baseFeeL1,
            msg1.sender,
            msg1.messageDataHash
        );
    }

    // --- Force include at exact boundary (block.number == l1BlockNumber + delayBlocks) should revert ---

    function test_forceInclusion_revert_exactBoundary() public {
        DelayedMsgInfo memory msg1 = _sendDelayedL2Msg(abi.encodePacked("boundary"));

        // advance exactly to the boundary (l1Block + delay == block.number), which means >= so still too soon
        vm.roll(msg1.blockNumber + DELAY_BLOCKS);

        vm.expectRevert(ForceIncludeBlockTooSoon.selector);
        seqInbox.forceInclusion(
            msg1.count,
            msg1.kind,
            [msg1.blockNumber, msg1.blockTimestamp],
            msg1.baseFeeL1,
            msg1.sender,
            msg1.messageDataHash
        );
    }

    // --- Force include count=0 should revert ---

    function test_forceInclusion_revert_zeroCount() public {
        vm.expectRevert(DelayedBackwards.selector);
        seqInbox.forceInclusion(
            0,
            3,
            [uint64(0), uint64(0)],
            0,
            address(0),
            bytes32(0)
        );
    }
}
