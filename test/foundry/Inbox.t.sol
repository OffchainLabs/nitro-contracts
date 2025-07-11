// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./AbsInbox.t.sol";
import "./util/TestUtil.sol";
import "../../src/bridge/Inbox.sol";
import "../../src/bridge/IInbox.sol";
import "../../src/bridge/Bridge.sol";
import "../../src/bridge/ISequencerInbox.sol";
import "../../src/libraries/AddressAliasHelper.sol";
import {
    NotOrigin, NotForked, GasLimitTooLarge, RetryableData
} from "../../src/libraries/Error.sol";
import {
    L2MessageType_unsignedEOATx,
    L2MessageType_unsignedContractTx
} from "../../src/libraries/MessageTypes.sol";
import "../../src/bridge/IOwnable.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/// forge-config: default.allow_internal_expect_revert = true
contract InboxTest is AbsInboxTest {
    IInbox public ethInbox;

    function setUp() public {
        // deploy token, bridge and inbox
        bridge = IBridge(TestUtil.deployProxy(address(new Bridge())));
        inbox = IInboxBase(TestUtil.deployProxy(address(new Inbox(MAX_DATA_SIZE))));
        ethInbox = IInbox(address(inbox));

        // init bridge and inbox
        IEthBridge(address(bridge)).initialize(IOwnable(rollup));
        inbox.initialize(bridge, ISequencerInbox(seqInbox));
        vm.prank(rollup);
        bridge.setDelayedInbox(address(inbox), true);

        // fund user account
        vm.deal(user, 10 ether);
    }

    /* solhint-disable func-name-mixedcase */
    function testInitialize() public {
        assertEq(address(inbox.bridge()), address(bridge), "Invalid bridge ref");
        assertEq(address(inbox.sequencerInbox()), seqInbox, "Invalid seqInbox ref");
        assertEq(inbox.allowListEnabled(), false, "Invalid allowListEnabled");
        assertEq((PausableUpgradeable(address(inbox))).paused(), false, "Invalid paused state");
    }

    function testDepositEthFromEOA() public {
        uint256 depositAmount = 2 ether;

        uint256 bridgeEthBalanceBefore = address(bridge).balance;
        uint256 userEthBalanceBefore = address(user).balance;

        // expect event
        vm.expectEmit(true, true, true, true);
        emit InboxMessageDelivered(0, abi.encodePacked(user, depositAmount));

        // deposit tokens -> tx.origin == msg.sender
        vm.prank(user, user);
        ethInbox.depositEth{value: depositAmount}();

        //// checks

        uint256 bridgeEthBalanceAfter = address(bridge).balance;
        assertEq(
            bridgeEthBalanceAfter - bridgeEthBalanceBefore,
            depositAmount,
            "Invalid bridge eth balance"
        );

        uint256 userEthBalanceAfter = address(user).balance;
        assertEq(
            userEthBalanceBefore - userEthBalanceAfter, depositAmount, "Invalid user eth balance"
        );

        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function testDepositEthFromContract() public {
        uint256 depositAmount = 1.2 ether;

        uint256 bridgeEthBalanceBefore = address(bridge).balance;
        uint256 userEthBalanceBefore = address(user).balance;

        // expect event
        vm.expectEmit(true, true, true, true);
        emit InboxMessageDelivered(
            0, abi.encodePacked(AddressAliasHelper.applyL1ToL2Alias(user), depositAmount)
        );

        // deposit tokens -> tx.origin != msg.sender
        vm.prank(user);
        ethInbox.depositEth{value: depositAmount}();

        //// checks

        uint256 bridgeEthBalanceAfter = address(bridge).balance;
        assertEq(
            bridgeEthBalanceAfter - bridgeEthBalanceBefore,
            depositAmount,
            "Invalid bridge eth balance"
        );

        uint256 userEthBalanceAfter = address(user).balance;
        assertEq(
            userEthBalanceBefore - userEthBalanceAfter, depositAmount, "Invalid eth token balance"
        );

        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function testDepositEthRevertEthTransferFails() public {
        uint256 bridgeEthBalanceBefore = address(bridge).balance;
        uint256 userEthBalanceBefore = address(user).balance;

        // deposit too many eth shall fail
        vm.prank(user);
        uint256 invalidDepositAmount = 300 ether;
        vm.expectRevert();
        ethInbox.depositEth{value: invalidDepositAmount}();

        //// checks

        uint256 bridgeEthBalanceAfter = address(bridge).balance;
        assertEq(bridgeEthBalanceAfter, bridgeEthBalanceBefore, "Invalid bridge token balance");

        uint256 userEthBalanceAfter = address(user).balance;
        assertEq(userEthBalanceBefore, userEthBalanceAfter, "Invalid user token balance");

        assertEq(bridge.delayedMessageCount(), 0, "Invalid delayed message count");
    }

    function testCreateRetryableTicketFromEOA() public {
        uint256 bridgeEthBalanceBefore = address(bridge).balance;
        uint256 userEthBalanceBefore = address(user).balance;

        uint256 ethToSend = 0.3 ether;

        // retryable params
        uint256 l2CallValue = 0.1 ether;
        uint256 maxSubmissionCost = 0.1 ether;
        uint256 gasLimit = 100_000;
        uint256 maxFeePerGas = 0.000000002 ether;
        bytes memory data = abi.encodePacked("some msg");

        // expect event
        vm.expectEmit(true, true, true, true);
        emit InboxMessageDelivered(
            0,
            abi.encodePacked(
                uint256(uint160(user)),
                l2CallValue,
                ethToSend,
                maxSubmissionCost,
                uint256(uint160(user)),
                uint256(uint160(user)),
                gasLimit,
                maxFeePerGas,
                data.length,
                data
            )
        );

        // create retryable -> tx.origin == msg.sender
        vm.prank(user, user);
        ethInbox.createRetryableTicket{value: ethToSend}({
            to: address(user),
            l2CallValue: l2CallValue,
            maxSubmissionCost: maxSubmissionCost,
            excessFeeRefundAddress: user,
            callValueRefundAddress: user,
            gasLimit: gasLimit,
            maxFeePerGas: maxFeePerGas,
            data: data
        });

        //// checks

        uint256 bridgeEthBalanceAfter = address(bridge).balance;
        assertEq(
            bridgeEthBalanceAfter - bridgeEthBalanceBefore,
            ethToSend,
            "Invalid bridge token balance"
        );

        uint256 userEthBalanceAfter = address(user).balance;
        assertEq(
            userEthBalanceBefore - userEthBalanceAfter, ethToSend, "Invalid user token balance"
        );

        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function testCreateRetryableTicketFromContract() public {
        address sender = address(new Sender());
        vm.deal(sender, 10 ether);

        uint256 bridgeEthBalanceBefore = address(bridge).balance;
        uint256 senderEthBalanceBefore = sender.balance;

        uint256 ethToSend = 0.3 ether;

        // retryable params
        uint256 l2CallValue = 0.1 ether;
        uint256 maxSubmissionCost = 0.1 ether;
        uint256 gasLimit = 100_000;
        uint256 maxFeePerGas = 0.000000001 ether;

        // expect event
        uint256 uintAlias = uint256(uint160(AddressAliasHelper.applyL1ToL2Alias(sender)));
        vm.expectEmit(true, true, true, true);
        emit InboxMessageDelivered(
            0,
            abi.encodePacked(
                uint256(uint160(sender)),
                l2CallValue,
                ethToSend,
                maxSubmissionCost,
                uintAlias,
                uintAlias,
                gasLimit,
                maxFeePerGas,
                abi.encodePacked("some msg").length,
                abi.encodePacked("some msg")
            )
        );

        // create retryable
        vm.prank(sender);
        ethInbox.createRetryableTicket{value: ethToSend}({
            to: sender,
            l2CallValue: l2CallValue,
            maxSubmissionCost: maxSubmissionCost,
            excessFeeRefundAddress: sender,
            callValueRefundAddress: sender,
            gasLimit: gasLimit,
            maxFeePerGas: maxFeePerGas,
            data: abi.encodePacked("some msg")
        });

        //// checks

        uint256 bridgeEthBalanceAfter = address(bridge).balance;
        assertEq(
            bridgeEthBalanceAfter - bridgeEthBalanceBefore,
            ethToSend,
            "Invalid bridge token balance"
        );

        uint256 senderEthBalanceAfter = address(sender).balance;
        assertEq(
            senderEthBalanceBefore - senderEthBalanceAfter,
            ethToSend,
            "Invalid sender token balance"
        );

        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function testCreateRetryableTicketRevertWhenPaused() public {
        vm.prank(rollup);
        inbox.pause();

        vm.expectRevert("Pausable: paused");
        ethInbox.createRetryableTicket({
            to: user,
            l2CallValue: 100,
            maxSubmissionCost: 0,
            excessFeeRefundAddress: user,
            callValueRefundAddress: user,
            gasLimit: 10,
            maxFeePerGas: 1,
            data: abi.encodePacked("data")
        });
    }

    function testCreateRetryableTicketRevertOnlyAllowed() public {
        vm.prank(rollup);
        inbox.setAllowListEnabled(true);

        vm.prank(user, user);
        vm.expectRevert(abi.encodeWithSelector(NotAllowedOrigin.selector, user));
        ethInbox.createRetryableTicket({
            to: user,
            l2CallValue: 100,
            maxSubmissionCost: 0,
            excessFeeRefundAddress: user,
            callValueRefundAddress: user,
            gasLimit: 10,
            maxFeePerGas: 1,
            data: abi.encodePacked("data")
        });
    }

    function testCreateRetryableTicketRevertInsufficientValue() public {
        uint256 tooSmallEthAmount = 1 ether;
        uint256 l2CallValue = 2 ether;
        uint256 maxSubmissionCost = 0.1 ether;
        uint256 gasLimit = 200000;
        uint256 maxFeePerGas = 0.00000002 ether;

        vm.prank(user, user);
        vm.expectRevert(
            abi.encodeWithSelector(
                InsufficientValue.selector,
                maxSubmissionCost + l2CallValue + gasLimit * maxFeePerGas,
                tooSmallEthAmount
            )
        );
        ethInbox.createRetryableTicket{value: tooSmallEthAmount}({
            to: user,
            l2CallValue: l2CallValue,
            maxSubmissionCost: maxSubmissionCost,
            excessFeeRefundAddress: user,
            callValueRefundAddress: user,
            gasLimit: gasLimit,
            maxFeePerGas: maxFeePerGas,
            data: abi.encodePacked("data")
        });
    }

    function testCreateRetryableTicketRevertRetryableDataTracer() public {
        uint256 msgValue = 3 ether;
        uint256 l2CallValue = 1 ether;
        uint256 maxSubmissionCost = 0.1 ether;
        uint256 gasLimit = 100000;
        uint256 maxFeePerGas = 1;
        bytes memory data = abi.encodePacked("xy");

        // revert as maxFeePerGas == 1 is magic value
        vm.prank(user, user);
        vm.expectRevert(
            abi.encodeWithSelector(
                RetryableData.selector,
                user,
                user,
                l2CallValue,
                msgValue,
                maxSubmissionCost,
                user,
                user,
                gasLimit,
                maxFeePerGas,
                data
            )
        );
        ethInbox.createRetryableTicket{value: msgValue}({
            to: user,
            l2CallValue: l2CallValue,
            maxSubmissionCost: maxSubmissionCost,
            excessFeeRefundAddress: user,
            callValueRefundAddress: user,
            gasLimit: gasLimit,
            maxFeePerGas: maxFeePerGas,
            data: data
        });

        gasLimit = 1;
        maxFeePerGas = 2;

        // revert as gasLimit == 1 is magic value
        vm.prank(user, user);
        vm.expectRevert(
            abi.encodeWithSelector(
                RetryableData.selector,
                user,
                user,
                l2CallValue,
                msgValue,
                maxSubmissionCost,
                user,
                user,
                gasLimit,
                maxFeePerGas,
                data
            )
        );
        ethInbox.createRetryableTicket{value: msgValue}({
            to: user,
            l2CallValue: l2CallValue,
            maxSubmissionCost: maxSubmissionCost,
            excessFeeRefundAddress: user,
            callValueRefundAddress: user,
            gasLimit: gasLimit,
            maxFeePerGas: maxFeePerGas,
            data: data
        });
    }

    function testCreateRetryableTicketRevertGasLimitTooLarge() public {
        uint256 tooBigGasLimit = uint256(type(uint64).max) + 1;

        vm.deal(user, uint256(type(uint64).max) * 3);
        vm.prank(user, user);
        vm.expectRevert(GasLimitTooLarge.selector);
        ethInbox.createRetryableTicket{value: uint256(type(uint64).max) * 3}({
            to: user,
            l2CallValue: 100,
            maxSubmissionCost: 0,
            excessFeeRefundAddress: user,
            callValueRefundAddress: user,
            gasLimit: tooBigGasLimit,
            maxFeePerGas: 2,
            data: abi.encodePacked("data")
        });
    }

    function testCreateRetryableTicketRevertInsufficientSubmissionCost() public {
        uint256 tooSmallMaxSubmissionCost = 5;
        bytes memory data = abi.encodePacked("msg");

        // simulate 23 gwei basefee
        vm.fee(23000000000);
        uint256 submissionFee = ethInbox.calculateRetryableSubmissionFee(data.length, block.basefee);

        // call shall revert
        vm.prank(user, user);
        vm.expectRevert(
            abi.encodePacked(
                InsufficientSubmissionCost.selector, submissionFee, tooSmallMaxSubmissionCost
            )
        );
        ethInbox.createRetryableTicket{value: 1 ether}({
            to: user,
            l2CallValue: 100,
            maxSubmissionCost: tooSmallMaxSubmissionCost,
            excessFeeRefundAddress: user,
            callValueRefundAddress: user,
            gasLimit: 60000,
            maxFeePerGas: 0.00000001 ether,
            data: data
        });
    }

    function testUnsafeCreateRetryableTicketFromEOA() public {
        uint256 bridgeEthBalanceBefore = address(bridge).balance;
        uint256 userEthBalanceBefore = address(user).balance;

        uint256 ethToSend = 0.3 ether;

        // retryable params
        uint256 l2CallValue = 0.1 ether;
        uint256 maxSubmissionCost = 0.1 ether;
        uint256 gasLimit = 100_000;
        uint256 maxFeePerGas = 0.000000002 ether;
        bytes memory data = abi.encodePacked("some msg");

        // expect event
        vm.expectEmit(true, true, true, true);
        emit InboxMessageDelivered(
            0,
            abi.encodePacked(
                uint256(uint160(user)),
                l2CallValue,
                ethToSend,
                maxSubmissionCost,
                uint256(uint160(user)),
                uint256(uint160(user)),
                gasLimit,
                maxFeePerGas,
                data.length,
                data
            )
        );

        // create retryable -> tx.origin == msg.sender
        vm.prank(user, user);
        ethInbox.unsafeCreateRetryableTicket{value: ethToSend}({
            to: address(user),
            l2CallValue: l2CallValue,
            maxSubmissionCost: maxSubmissionCost,
            excessFeeRefundAddress: user,
            callValueRefundAddress: user,
            gasLimit: gasLimit,
            maxFeePerGas: maxFeePerGas,
            data: data
        });

        //// checks

        uint256 bridgeEthBalanceAfter = address(bridge).balance;
        assertEq(
            bridgeEthBalanceAfter - bridgeEthBalanceBefore,
            ethToSend,
            "Invalid bridge token balance"
        );

        uint256 userEthBalanceAfter = address(user).balance;
        assertEq(
            userEthBalanceBefore - userEthBalanceAfter, ethToSend, "Invalid user token balance"
        );

        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function testUnsafeCreateRetryableTicketFromContract() public {
        address sender = address(new Sender());
        vm.deal(sender, 10 ether);

        uint256 bridgeEthBalanceBefore = address(bridge).balance;
        uint256 senderEthBalanceBefore = sender.balance;

        uint256 ethToSend = 0.3 ether;

        // retryable params
        uint256 l2CallValue = 0.1 ether;
        uint256 maxSubmissionCost = 0.1 ether;
        uint256 gasLimit = 100_000;
        uint256 maxFeePerGas = 0.000000001 ether;

        // expect event
        vm.expectEmit(true, true, true, true);
        emit InboxMessageDelivered(
            0,
            abi.encodePacked(
                uint256(uint160(sender)),
                l2CallValue,
                ethToSend,
                maxSubmissionCost,
                uint256(uint160(sender)),
                uint256(uint160(sender)),
                gasLimit,
                maxFeePerGas,
                abi.encodePacked("some msg").length,
                abi.encodePacked("some msg")
            )
        );

        // create retryable
        vm.prank(sender);
        ethInbox.unsafeCreateRetryableTicket{value: ethToSend}({
            to: sender,
            l2CallValue: l2CallValue,
            maxSubmissionCost: maxSubmissionCost,
            excessFeeRefundAddress: sender,
            callValueRefundAddress: sender,
            gasLimit: gasLimit,
            maxFeePerGas: maxFeePerGas,
            data: abi.encodePacked("some msg")
        });

        //// checks

        uint256 bridgeEthBalanceAfter = address(bridge).balance;
        assertEq(
            bridgeEthBalanceAfter - bridgeEthBalanceBefore,
            ethToSend,
            "Invalid bridge token balance"
        );

        uint256 senderEthBalanceAfter = address(sender).balance;
        assertEq(
            senderEthBalanceBefore - senderEthBalanceAfter,
            ethToSend,
            "Invalid sender token balance"
        );

        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function testUnsafeCreateRetryableTicketNotRevertingOnInsufficientValue() public {
        uint256 bridgeEthBalanceBefore = address(bridge).balance;
        uint256 userEthBalanceBefore = address(user).balance;

        uint256 tooSmallEthAmount = 1 ether;
        uint256 l2CallValue = 2 ether;
        uint256 maxSubmissionCost = 0.1 ether;
        uint256 gasLimit = 200000;
        uint256 maxFeePerGas = 0.00000002 ether;

        // expect event
        vm.expectEmit(true, true, true, true);
        emit InboxMessageDelivered(
            0,
            abi.encodePacked(
                uint256(uint160(user)),
                l2CallValue,
                tooSmallEthAmount,
                maxSubmissionCost,
                uint256(uint160(user)),
                uint256(uint160(user)),
                gasLimit,
                maxFeePerGas,
                abi.encodePacked("data").length,
                abi.encodePacked("data")
            )
        );

        vm.prank(user, user);
        ethInbox.unsafeCreateRetryableTicket{value: tooSmallEthAmount}({
            to: user,
            l2CallValue: l2CallValue,
            maxSubmissionCost: maxSubmissionCost,
            excessFeeRefundAddress: user,
            callValueRefundAddress: user,
            gasLimit: gasLimit,
            maxFeePerGas: maxFeePerGas,
            data: abi.encodePacked("data")
        });

        //// checks

        uint256 bridgeEthBalanceAfter = address(bridge).balance;
        assertEq(
            bridgeEthBalanceAfter - bridgeEthBalanceBefore,
            tooSmallEthAmount,
            "Invalid bridge token balance"
        );

        uint256 userEthBalanceAfter = address(user).balance;
        assertEq(
            userEthBalanceBefore - userEthBalanceAfter,
            tooSmallEthAmount,
            "Invalid user token balance"
        );

        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function testCalculateRetryableSubmissionFee() public {
        // 30 gwei fee
        uint256 basefee = 30000000000;
        vm.fee(basefee);
        uint256 datalength = 10;

        assertEq(
            inbox.calculateRetryableSubmissionFee(datalength, 0),
            (1400 + 6 * datalength) * basefee,
            "Invalid eth retryable submission fee"
        );
    }

    function testSendL1FundedUnsignedTransaction() public {
        uint256 depositAmount = 1 ether;
        uint256 gasLimit = 100_000;
        uint256 maxFeePerGas = 0.000000002 ether;
        uint256 nonce = 5;
        bytes memory data = abi.encodePacked("test data");

        uint256 bridgeEthBalanceBefore = address(bridge).balance;
        uint256 userEthBalanceBefore = address(user).balance;

        // expect event
        vm.expectEmit(true, true, true, true);
        emit InboxMessageDelivered(
            0,
            abi.encodePacked(
                L2MessageType_unsignedEOATx,
                gasLimit,
                maxFeePerGas,
                nonce,
                uint256(uint160(user)),
                depositAmount,
                data
            )
        );

        // send transaction
        vm.prank(user);
        uint256 msgNum = ethInbox.sendL1FundedUnsignedTransaction{value: depositAmount}(
            gasLimit, maxFeePerGas, nonce, user, data
        );

        // checks
        assertEq(msgNum, 0, "Invalid message number");
        assertEq(
            address(bridge).balance - bridgeEthBalanceBefore,
            depositAmount,
            "Invalid bridge balance"
        );
        assertEq(
            userEthBalanceBefore - address(user).balance, depositAmount, "Invalid user balance"
        );
        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function testSendL1FundedUnsignedTransactionRevertGasLimitTooLarge() public {
        uint256 tooBigGasLimit = uint256(type(uint64).max) + 1;

        vm.deal(user, 10 ether);
        vm.prank(user);
        vm.expectRevert(GasLimitTooLarge.selector);
        ethInbox.sendL1FundedUnsignedTransaction{value: 1 ether}(tooBigGasLimit, 1, 0, user, "");
    }

    function testSendL1FundedContractTransaction() public {
        address contractAddress = address(new Sender());
        uint256 depositAmount = 0.5 ether;
        uint256 gasLimit = 200_000;
        uint256 maxFeePerGas = 0.000000003 ether;
        bytes memory data = abi.encodePacked("contract call data");

        uint256 bridgeEthBalanceBefore = address(bridge).balance;
        uint256 userEthBalanceBefore = address(user).balance;

        // expect event
        vm.expectEmit(true, true, true, true);
        emit InboxMessageDelivered(
            0,
            abi.encodePacked(
                L2MessageType_unsignedContractTx,
                gasLimit,
                maxFeePerGas,
                uint256(uint160(contractAddress)),
                depositAmount,
                data
            )
        );

        // send transaction
        vm.prank(user);
        uint256 msgNum = ethInbox.sendL1FundedContractTransaction{value: depositAmount}(
            gasLimit, maxFeePerGas, contractAddress, data
        );

        // checks
        assertEq(msgNum, 0, "Invalid message number");
        assertEq(
            address(bridge).balance - bridgeEthBalanceBefore,
            depositAmount,
            "Invalid bridge balance"
        );
        assertEq(
            userEthBalanceBefore - address(user).balance, depositAmount, "Invalid user balance"
        );
        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function testSendL1FundedContractTransactionRevertGasLimitTooLarge() public {
        uint256 tooBigGasLimit = uint256(type(uint64).max) + 1;

        vm.deal(user, 10 ether);
        vm.prank(user);
        vm.expectRevert(GasLimitTooLarge.selector);
        ethInbox.sendL1FundedContractTransaction{value: 1 ether}(tooBigGasLimit, 1, user, "");
    }

    function testSendL1FundedUnsignedTransactionToFork() public {
        // This test requires simulating a fork by changing the chain ID
        // Since deployTimeChainId is immutable, we need to deploy a new inbox with different chainId
        uint256 currentChainId = block.chainid;

        // Change chain ID to simulate fork
        vm.chainId(currentChainId + 1);

        // Deploy new inbox through proxy with new chain ID
        address inboxImpl = address(new Inbox(MAX_DATA_SIZE));
        address proxyAddress = TestUtil.deployProxy(inboxImpl);
        Inbox forkInbox = Inbox(proxyAddress);
        forkInbox.initialize(bridge, ISequencerInbox(seqInbox));
        vm.prank(rollup);
        bridge.setDelayedInbox(address(forkInbox), true);

        // Change back to original chain ID (simulating we're on forked chain)
        vm.chainId(currentChainId);

        uint256 depositAmount = 0.8 ether;
        uint256 gasLimit = 150_000;
        uint256 maxFeePerGas = 0.000000002 ether;
        uint256 nonce = 10;
        bytes memory data = abi.encodePacked("fork test data");

        uint256 bridgeEthBalanceBefore = address(bridge).balance;

        // send transaction from EOA (tx.origin == msg.sender)
        vm.prank(user, user);
        uint256 msgNum = IInbox(address(forkInbox)).sendL1FundedUnsignedTransactionToFork{
            value: depositAmount
        }(gasLimit, maxFeePerGas, nonce, user, data);

        assertEq(msgNum, 0, "Invalid message number");
        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
        assertEq(
            address(bridge).balance - bridgeEthBalanceBefore,
            depositAmount,
            "Invalid bridge balance"
        );
    }

    function testSendL1FundedUnsignedTransactionToForkRevertNotForked() public {
        // Should revert when chain ID hasn't changed
        vm.prank(user, user);
        vm.expectRevert(NotForked.selector);
        ethInbox.sendL1FundedUnsignedTransactionToFork{value: 1 ether}(100_000, 1, 0, user, "");
    }

    function testSendL1FundedUnsignedTransactionToForkRevertNotOrigin() public {
        // Deploy inbox with different chain ID to simulate fork
        uint256 currentChainId = block.chainid;
        vm.chainId(currentChainId + 1);
        address inboxImpl = address(new Inbox(MAX_DATA_SIZE));
        address proxyAddress = TestUtil.deployProxy(inboxImpl);
        Inbox forkInbox = Inbox(proxyAddress);
        forkInbox.initialize(bridge, ISequencerInbox(seqInbox));
        vm.chainId(currentChainId);

        // Call from contract (tx.origin != msg.sender)
        vm.prank(user);
        vm.expectRevert(NotOrigin.selector);
        IInbox(address(forkInbox)).sendL1FundedUnsignedTransactionToFork{value: 1 ether}(
            100_000, 1, 0, user, ""
        );
    }

    function testSendUnsignedTransactionToFork() public {
        // Deploy inbox with different chain ID
        uint256 currentChainId = block.chainid;
        vm.chainId(currentChainId + 1);
        address inboxImpl = address(new Inbox(MAX_DATA_SIZE));
        address proxyAddress = TestUtil.deployProxy(inboxImpl);
        Inbox forkInbox = Inbox(proxyAddress);
        forkInbox.initialize(bridge, ISequencerInbox(seqInbox));
        vm.prank(rollup);
        bridge.setDelayedInbox(address(forkInbox), true);
        vm.chainId(currentChainId);

        uint256 gasLimit = 100_000;
        uint256 maxFeePerGas = 0.000000002 ether;
        uint256 nonce = 15;
        uint256 value = 0.5 ether;
        bytes memory data = abi.encodePacked("unsigned fork tx");

        // send transaction from EOA
        vm.prank(user, user);
        uint256 msgNum = IInbox(address(forkInbox)).sendUnsignedTransactionToFork(
            gasLimit, maxFeePerGas, nonce, user, value, data
        );

        assertEq(msgNum, 0, "Invalid message number");
        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function testSendUnsignedTransactionToForkRevertNotForked() public {
        vm.prank(user, user);
        vm.expectRevert(NotForked.selector);
        ethInbox.sendUnsignedTransactionToFork(100_000, 1, 0, user, 0.1 ether, "");
    }

    function testSendUnsignedTransactionToForkRevertGasLimitTooLarge() public {
        // Deploy inbox with different chain ID
        uint256 currentChainId = block.chainid;
        vm.chainId(currentChainId + 1);
        address inboxImpl = address(new Inbox(MAX_DATA_SIZE));
        address proxyAddress = TestUtil.deployProxy(inboxImpl);
        Inbox forkInbox = Inbox(proxyAddress);
        forkInbox.initialize(bridge, ISequencerInbox(seqInbox));
        vm.chainId(currentChainId);

        uint256 tooBigGasLimit = uint256(type(uint64).max) + 1;

        vm.prank(user, user);
        vm.expectRevert(GasLimitTooLarge.selector);
        IInbox(address(forkInbox)).sendUnsignedTransactionToFork(
            tooBigGasLimit, 1, 0, user, 0.1 ether, ""
        );
    }

    function testSendWithdrawEthToFork() public {
        // Deploy inbox with different chain ID
        uint256 currentChainId = block.chainid;
        vm.chainId(currentChainId + 1);
        address inboxImpl = address(new Inbox(MAX_DATA_SIZE));
        address proxyAddress = TestUtil.deployProxy(inboxImpl);
        Inbox forkInbox = Inbox(proxyAddress);
        forkInbox.initialize(bridge, ISequencerInbox(seqInbox));
        vm.prank(rollup);
        bridge.setDelayedInbox(address(forkInbox), true);
        vm.chainId(currentChainId);

        uint256 gasLimit = 80_000;
        uint256 maxFeePerGas = 0.000000002 ether;
        uint256 nonce = 20;
        uint256 withdrawValue = 1.5 ether;
        address withdrawTo = address(0x1234);

        // send withdrawal from EOA
        vm.prank(user, user);
        uint256 msgNum = IInbox(address(forkInbox)).sendWithdrawEthToFork(
            gasLimit, maxFeePerGas, nonce, withdrawValue, withdrawTo
        );

        assertEq(msgNum, 0, "Invalid message number");
        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function testSendWithdrawEthToForkRevertNotForked() public {
        vm.prank(user, user);
        vm.expectRevert(NotForked.selector);
        ethInbox.sendWithdrawEthToFork(100_000, 1, 0, 1 ether, address(0x1234));
    }

    function testSendWithdrawEthToForkRevertNotOrigin() public {
        // Deploy inbox with different chain ID
        uint256 currentChainId = block.chainid;
        vm.chainId(currentChainId + 1);
        address inboxImpl = address(new Inbox(MAX_DATA_SIZE));
        address proxyAddress = TestUtil.deployProxy(inboxImpl);
        Inbox forkInbox = Inbox(proxyAddress);
        forkInbox.initialize(bridge, ISequencerInbox(seqInbox));
        vm.chainId(currentChainId);

        // Call from contract
        vm.prank(user);
        vm.expectRevert(NotOrigin.selector);
        IInbox(address(forkInbox)).sendWithdrawEthToFork(100_000, 1, 0, 1 ether, address(0x1234));
    }

    function testCreateRetryableTicketNoRefundAliasRewrite() public {
        // This deprecated function should work the same as unsafeCreateRetryableTicket
        uint256 ethToSend = 0.3 ether;
        uint256 l2CallValue = 0.1 ether;
        uint256 maxSubmissionCost = 0.1 ether;
        uint256 gasLimit = 100_000;
        uint256 maxFeePerGas = 0.000000002 ether;
        bytes memory data = abi.encodePacked("deprecated method test");

        uint256 bridgeEthBalanceBefore = address(bridge).balance;
        uint256 userEthBalanceBefore = address(user).balance;

        // expect event
        vm.expectEmit(true, true, true, true);
        emit InboxMessageDelivered(
            0,
            abi.encodePacked(
                uint256(uint160(user)),
                l2CallValue,
                ethToSend,
                maxSubmissionCost,
                uint256(uint160(user)),
                uint256(uint160(user)),
                gasLimit,
                maxFeePerGas,
                data.length,
                data
            )
        );

        // call deprecated method
        vm.prank(user, user);
        uint256 msgNum = Inbox(address(ethInbox)).createRetryableTicketNoRefundAliasRewrite{
            value: ethToSend
        }(user, l2CallValue, maxSubmissionCost, user, user, gasLimit, maxFeePerGas, data);

        // checks
        assertEq(msgNum, 0, "Invalid message number");
        assertEq(
            address(bridge).balance - bridgeEthBalanceBefore, ethToSend, "Invalid bridge balance"
        );
        assertEq(userEthBalanceBefore - address(user).balance, ethToSend, "Invalid user balance");
        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function testCreateRetryableTicketNoRefundAliasRewriteRevertGasLimitTooLarge() public {
        uint256 tooBigGasLimit = uint256(type(uint64).max) + 1;
        uint256 l2CallValue = 0.1 ether;
        uint256 maxSubmissionCost = 0.1 ether;
        uint256 msgValue = 1 ether;

        vm.deal(user, 10 ether);
        vm.prank(user);
        // The deprecated function calls unsafeCreateRetryableTicket which reverts with RetryableData
        // when gasLimit or maxFeePerGas is set to 1 (magic value)
        vm.expectRevert(
            abi.encodeWithSelector(
                RetryableData.selector,
                user,
                user,
                l2CallValue,
                msgValue,
                maxSubmissionCost,
                user,
                user,
                tooBigGasLimit,
                1,
                ""
            )
        );
        Inbox(address(ethInbox)).createRetryableTicketNoRefundAliasRewrite{value: msgValue}(
            user, l2CallValue, maxSubmissionCost, user, user, tooBigGasLimit, 1, ""
        );
    }

    function testPostUpgradeInit() public {
        Inbox testInbox = new Inbox(MAX_DATA_SIZE);

        // Attempting to call it directly should fail due to onlyDelegated
        vm.expectRevert("Function must be called through delegatecall");
        testInbox.postUpgradeInit(bridge);
    }
}
