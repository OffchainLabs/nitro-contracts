// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./AbsInbox.t.sol";
import "./util/TestUtil.sol";
import "../../src/bridge/Inbox.sol";
import "../../src/bridge/IInbox.sol";
import "../../src/bridge/Bridge.sol";
import "../../src/bridge/ISequencerInbox.sol";
import "../../src/libraries/AddressAliasHelper.sol";
import {NotForked} from "../../src/libraries/Error.sol";

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
    function test_initialize() public {
        assertEq(address(inbox.bridge()), address(bridge), "Invalid bridge ref");
        assertEq(address(inbox.sequencerInbox()), seqInbox, "Invalid seqInbox ref");
        assertEq(inbox.allowListEnabled(), false, "Invalid allowListEnabled");
        assertEq((PausableUpgradeable(address(inbox))).paused(), false, "Invalid paused state");
    }

    function test_depositEth_FromEOA() public {
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

    function test_depositEth_FromContract() public {
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

    function test_depositEth_revert_EthTransferFails() public {
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

    function test_createRetryableTicket_FromEOA() public {
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

    function test_createRetryableTicket_FromContract() public {
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

    function test_createRetryableTicket_revert_WhenPaused() public {
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

    function test_createRetryableTicket_revert_OnlyAllowed() public {
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

    function test_createRetryableTicket_revert_InsufficientValue() public {
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

    function test_createRetryableTicket_revert_RetryableDataTracer() public {
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

    function test_createRetryableTicket_revert_GasLimitTooLarge() public {
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

    function test_createRetryableTicket_revert_InsufficientSubmissionCost() public {
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

    function test_unsafeCreateRetryableTicket_FromEOA() public {
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

    function test_unsafeCreateRetryableTicket_FromContract() public {
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

    function test_unsafeCreateRetryableTicket_NotRevertingOnInsufficientValue() public {
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

    function test_sendL1FundedUnsignedTransaction() public {
        uint256 gasLimit = type(uint64).max; // max valid gas limit
        uint256 maxFeePerGas = 1 gwei;
        uint256 nonce = 1;
        uint256 ethToSend = 0.1 ether;

        vm.prank(user, user);
        uint256 msgNum = ethInbox.sendL1FundedUnsignedTransaction{value: ethToSend}(
            gasLimit, maxFeePerGas, nonce, user, ""
        );

        assertEq(msgNum, 0, "Invalid msgNum");
        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function test_sendL1FundedUnsignedTransaction_revert_GasLimitTooLarge() public {
        uint256 tooBigGasLimit = uint256(type(uint64).max) + 1;

        vm.prank(user, user);
        vm.expectRevert(GasLimitTooLarge.selector);
        ethInbox.sendL1FundedUnsignedTransaction{value: 0.1 ether}(
            tooBigGasLimit, 1 gwei, 1, user, ""
        );
    }

    function test_sendL1FundedContractTransaction() public {
        uint256 gasLimit = type(uint64).max; // max valid gas limit
        uint256 maxFeePerGas = 1 gwei;
        uint256 ethToSend = 0.1 ether;

        vm.prank(user);
        uint256 msgNum = ethInbox.sendL1FundedContractTransaction{value: ethToSend}(
            gasLimit, maxFeePerGas, user, ""
        );

        assertEq(msgNum, 0, "Invalid msgNum");
        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function test_sendL1FundedContractTransaction_revert_GasLimitTooLarge() public {
        uint256 tooBigGasLimit = uint256(type(uint64).max) + 1;

        vm.prank(user);
        vm.expectRevert(GasLimitTooLarge.selector);
        ethInbox.sendL1FundedContractTransaction{value: 0.1 ether}(
            tooBigGasLimit, 1 gwei, user, ""
        );
    }

    function test_sendL1FundedUnsignedTransactionToFork() public {
        vm.chainId(10);
        uint256 ethToSend = 0.1 ether;

        vm.prank(user, user);
        uint256 msgNum = ethInbox.sendL1FundedUnsignedTransactionToFork{value: ethToSend}(
            100_000, 1 gwei, 1, user, ""
        );

        assertEq(msgNum, 0, "Invalid msgNum");
        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function test_sendL1FundedUnsignedTransactionToFork_revert_NotForked() public {
        vm.prank(user, user);
        vm.expectRevert(NotForked.selector);
        ethInbox.sendL1FundedUnsignedTransactionToFork{value: 0.1 ether}(
            100_000, 1 gwei, 1, user, ""
        );
    }

    function test_sendL1FundedUnsignedTransactionToFork_revert_NotOrigin() public {
        vm.chainId(10);
        vm.prank(user);
        vm.expectRevert(NotOrigin.selector);
        ethInbox.sendL1FundedUnsignedTransactionToFork{value: 0.1 ether}(
            100_000, 1 gwei, 1, user, ""
        );
    }

    function test_sendL1FundedUnsignedTransactionToFork_OriginPassesEOA() public {
        vm.chainId(10);
        vm.prank(user, user);
        uint256 msgNum = ethInbox.sendL1FundedUnsignedTransactionToFork{value: 0.1 ether}(
            100_000, 1 gwei, 1, user, ""
        );
        assertEq(msgNum, 0, "Invalid msgNum");
        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function test_sendL1FundedUnsignedTransactionToFork_ValidGasLimit() public {
        vm.chainId(10);
        vm.prank(user, user);
        uint256 msgNum = ethInbox.sendL1FundedUnsignedTransactionToFork{value: 0.1 ether}(
            uint256(type(uint64).max), 1 gwei, 1, user, ""
        );
        assertEq(msgNum, 0, "Invalid msgNum");
        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function test_sendL1FundedUnsignedTransactionToFork_revert_GasLimitTooLarge() public {
        vm.chainId(10);
        uint256 tooBigGasLimit = uint256(type(uint64).max) + 1;

        vm.prank(user, user);
        vm.expectRevert(GasLimitTooLarge.selector);
        ethInbox.sendL1FundedUnsignedTransactionToFork{value: 0.1 ether}(
            tooBigGasLimit, 1 gwei, 1, user, ""
        );
    }

    function test_sendUnsignedTransactionToFork() public {
        vm.chainId(10);

        vm.prank(user, user);
        uint256 msgNum = ethInbox.sendUnsignedTransactionToFork(
            100_000, 1 gwei, 1, user, 0, ""
        );

        assertEq(msgNum, 0, "Invalid msgNum");
        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function test_sendUnsignedTransactionToFork_revert_NotForked() public {
        vm.prank(user, user);
        vm.expectRevert(NotForked.selector);
        ethInbox.sendUnsignedTransactionToFork(100_000, 1 gwei, 1, user, 0, "");
    }

    function test_sendUnsignedTransactionToFork_revert_NotOrigin() public {
        vm.chainId(10);
        vm.prank(user);
        vm.expectRevert(NotOrigin.selector);
        ethInbox.sendUnsignedTransactionToFork(100_000, 1 gwei, 1, user, 0, "");
    }

    function test_sendUnsignedTransactionToFork_OriginPassesEOA() public {
        vm.chainId(10);
        vm.prank(user, user);
        uint256 msgNum = ethInbox.sendUnsignedTransactionToFork(100_000, 1 gwei, 1, user, 0, "");
        assertEq(msgNum, 0, "Invalid msgNum");
        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function test_sendUnsignedTransactionToFork_ValidGasLimit() public {
        vm.chainId(10);
        vm.prank(user, user);
        uint256 msgNum = ethInbox.sendUnsignedTransactionToFork(
            uint256(type(uint64).max), 1 gwei, 1, user, 0, ""
        );
        assertEq(msgNum, 0, "Invalid msgNum");
        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function test_sendUnsignedTransactionToFork_revert_GasLimitTooLarge() public {
        vm.chainId(10);
        uint256 tooBigGasLimit = uint256(type(uint64).max) + 1;

        vm.prank(user, user);
        vm.expectRevert(GasLimitTooLarge.selector);
        ethInbox.sendUnsignedTransactionToFork(tooBigGasLimit, 1 gwei, 1, user, 0, "");
    }

    function test_sendWithdrawEthToFork() public {
        vm.chainId(10);

        vm.prank(user, user);
        uint256 msgNum = ethInbox.sendWithdrawEthToFork(
            100_000, 1 gwei, 1, 0.05 ether, user
        );

        assertEq(msgNum, 0, "Invalid msgNum");
        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function test_sendWithdrawEthToFork_revert_NotForked() public {
        vm.prank(user, user);
        vm.expectRevert(NotForked.selector);
        ethInbox.sendWithdrawEthToFork(100_000, 1 gwei, 1, 0.05 ether, user);
    }

    function test_sendWithdrawEthToFork_revert_NotOrigin() public {
        vm.chainId(10);
        vm.prank(user);
        vm.expectRevert(NotOrigin.selector);
        ethInbox.sendWithdrawEthToFork(100_000, 1 gwei, 1, 0.05 ether, user);
    }

    function test_sendWithdrawEthToFork_OriginPassesEOA() public {
        vm.chainId(10);
        vm.prank(user, user);
        uint256 msgNum = ethInbox.sendWithdrawEthToFork(100_000, 1 gwei, 1, 0.05 ether, user);
        assertEq(msgNum, 0, "Invalid msgNum");
    }

    function test_sendWithdrawEthToFork_ValidGasLimit() public {
        vm.chainId(10);
        vm.prank(user, user);
        uint256 msgNum = ethInbox.sendWithdrawEthToFork(
            uint256(type(uint64).max), 1 gwei, 1, 0.05 ether, user
        );
        assertEq(msgNum, 0, "Invalid msgNum");
        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function test_sendWithdrawEthToFork_revert_GasLimitTooLarge() public {
        vm.chainId(10);
        uint256 tooBigGasLimit = uint256(type(uint64).max) + 1;

        vm.prank(user, user);
        vm.expectRevert(GasLimitTooLarge.selector);
        ethInbox.sendWithdrawEthToFork(tooBigGasLimit, 1 gwei, 1, 0.05 ether, user);
    }

    function test_calculateRetryableSubmissionFee() public {
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

    // AI generated test case to catch a mutated required value calculation
    // KILLS MUTANT in src/bridge/AbsInbox.sol
    // BinaryOpMutation(`*` |==> `+`) of: `if (amountToBeMintedOnL2 < (maxSubmissionCost + l2CallValue + gasLimit * maxFeePerGas)) {`
    // if (amountToBeMintedOnL2 < (maxSubmissionCost + l2CallValue + gasLimit+maxFeePerGas)) {
    //     revert InsufficientValue(
    function test_createRetryableTicket_revert_InsufficientValue_MulVsAdd() public {
        // Choose values where gasLimit * maxFeePerGas >> gasLimit + maxFeePerGas
        // gasLimit=1000, maxFeePerGas=0.000001 ether => product = 0.001 ether, sum = 1000 + 1e12
        uint256 l2CallValue = 0;
        uint256 maxSubmissionCost = 0.1 ether;
        uint256 gasLimit = 1000;
        uint256 maxFeePerGas = 0.000001 ether;
        // required with *: 0.1 ether + 0 + 1000 * 0.000001 ether = 0.1 + 0.001 = 0.101 ether
        // required with +: 0.1 ether + 0 + 1000 + 1e12 = ~0.100000001001 ether
        // send amount between the two so only * triggers revert
        uint256 ethToSend = 0.1001 ether;

        vm.prank(user, user);
        vm.expectRevert(
            abi.encodeWithSelector(
                InsufficientValue.selector,
                maxSubmissionCost + l2CallValue + gasLimit * maxFeePerGas,
                ethToSend
            )
        );
        ethInbox.createRetryableTicket{value: ethToSend}({
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
}
