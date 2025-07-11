// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./AbsOutbox.t.sol";
import "../../src/bridge/Bridge.sol";
import "../../src/bridge/Outbox.sol";

contract L2ToL1Target {
    address public outbox;

    uint128 public l2Block;
    uint128 public timestamp;
    bytes32 public outputId;
    address public sender;
    uint96 public l1Block;
    uint256 public withdrawalAmount;

    function receiveHook() external payable {
        l2Block = uint128(IOutbox(outbox).l2ToL1Block());
        timestamp = uint128(IOutbox(outbox).l2ToL1Timestamp());
        outputId = IOutbox(outbox).l2ToL1OutputId();
        sender = IOutbox(outbox).l2ToL1Sender();
        l1Block = uint96(IOutbox(outbox).l2ToL1EthBlock());
        withdrawalAmount = msg.value;
    }

    function setOutbox(
        address _outbox
    ) external {
        outbox = _outbox;
    }
}

contract RevertingContract {
    function revertWithoutData() external pure {
        assembly {
            revert(0, 0)
        }
    }

    function revertWithData() external pure {
        revert("Custom revert message");
    }
}

contract OutboxTest is AbsOutboxTest {
    Outbox public ethOutbox;
    Bridge public ethBridge;

    function setUp() public {
        // deploy bridge and outbox
        bridge = IBridge(TestUtil.deployProxy(address(new Bridge())));
        ethBridge = Bridge(address(bridge));
        outbox = IOutbox(TestUtil.deployProxy(address(new Outbox())));
        ethOutbox = Outbox(address(outbox));

        // init bridge and outbox
        ethBridge.initialize(IOwnable(rollup));
        ethOutbox.initialize(IBridge(bridge));

        vm.prank(rollup);
        bridge.setOutbox(address(outbox), true);
    }

    /* solhint-disable func-name-mixedcase */
    function testInitializeRevertAlreadyInit() public {
        vm.expectRevert(abi.encodeWithSelector(AlreadyInit.selector));
        ethOutbox.initialize(IBridge(bridge));
    }

    function testExecuteTransaction() public {
        // fund bridge with some ether
        vm.deal(address(bridge), 100 ether);

        // create msg receiver on L1
        L2ToL1Target target = new L2ToL1Target();
        target.setOutbox(address(outbox));

        //// execute transaction
        uint256 bridgeBalanceBefore = address(bridge).balance;
        uint256 targetBalanceBefore = address(target).balance;

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = bytes32(0);

        uint256 withdrawalAmount = 15 ether;
        bytes memory data = abi.encodeWithSignature("receiveHook()");

        uint256 index = 1;
        bytes32 itemHash = outbox.calculateItemHash({
            l2Sender: user,
            to: address(target),
            l2Block: 300,
            l1Block: 20,
            l2Timestamp: 1234,
            value: withdrawalAmount,
            data: data
        });
        bytes32 root = outbox.calculateMerkleRoot(proof, index, itemHash);
        // store root
        vm.prank(rollup);
        outbox.updateSendRoot(root, bytes32(uint256(1)));

        outbox.executeTransaction({
            proof: proof,
            index: index,
            l2Sender: user,
            to: address(target),
            l2Block: 300,
            l1Block: 20,
            l2Timestamp: 1234,
            value: withdrawalAmount,
            data: data
        });

        uint256 bridgeBalanceAfter = address(bridge).balance;
        assertEq(
            bridgeBalanceBefore - bridgeBalanceAfter, withdrawalAmount, "Invalid bridge balance"
        );

        uint256 targetBalanceAfter = address(target).balance;
        assertEq(
            targetBalanceAfter - targetBalanceBefore, withdrawalAmount, "Invalid target balance"
        );

        /// check context was properly set during execution
        assertEq(uint256(target.l2Block()), 300, "Invalid l2Block");
        assertEq(uint256(target.timestamp()), 1234, "Invalid timestamp");
        assertEq(uint256(target.outputId()), index, "Invalid outputId");
        assertEq(target.sender(), user, "Invalid sender");
        assertEq(uint256(target.l1Block()), 20, "Invalid l1Block");
        assertEq(uint256(target.withdrawalAmount()), withdrawalAmount, "Invalid withdrawalAmount");

        vm.expectRevert(abi.encodeWithSignature("AlreadySpent(uint256)", index));
        outbox.executeTransaction({
            proof: proof,
            index: index,
            l2Sender: user,
            to: address(target),
            l2Block: 300,
            l1Block: 20,
            l2Timestamp: 1234,
            value: withdrawalAmount,
            data: data
        });
    }

    function testUpdateRollupAddressRevertRollupNotChanged() public {
        // Setup owner mock
        vm.mockCall(
            rollup, abi.encodeWithSelector(IOwnable.owner.selector), abi.encode(address(this))
        );

        // Try to update to same rollup address - should revert
        vm.expectRevert(RollupNotChanged.selector);
        ethOutbox.updateRollupAddress();
    }

    function testRecordOutputAsSpentRevertProofTooLong() public {
        // Create a proof that's too long (256 elements)
        bytes32[] memory proof = new bytes32[](256);
        for (uint256 i = 0; i < 256; i++) {
            proof[i] = bytes32(i);
        }

        uint256 index = 1;

        vm.expectRevert(abi.encodeWithSelector(ProofTooLong.selector, 256));
        ethOutbox.executeTransaction({
            proof: proof,
            index: index,
            l2Sender: user,
            to: address(100),
            l2Block: 1,
            l1Block: 1,
            l2Timestamp: 1,
            value: 0,
            data: ""
        });
    }

    function testRecordOutputAsSpentRevertPathNotMinimal() public {
        // Create a proof of length 2, but use index >= 2^2
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = bytes32(0);
        proof[1] = bytes32(0);

        uint256 index = 4; // 2^2 = 4, so index must be < 4

        vm.expectRevert(abi.encodeWithSelector(PathNotMinimal.selector, index, 4));
        ethOutbox.executeTransaction({
            proof: proof,
            index: index,
            l2Sender: user,
            to: address(100),
            l2Block: 1,
            l1Block: 1,
            l2Timestamp: 1,
            value: 0,
            data: ""
        });
    }

    function testRecordOutputAsSpentRevertUnknownRoot() public {
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = bytes32(0);

        uint256 index = 1;
        bytes32 itemHash = ethOutbox.calculateItemHash({
            l2Sender: user,
            to: address(100),
            l2Block: 1,
            l1Block: 1,
            l2Timestamp: 1,
            value: 0,
            data: ""
        });

        bytes32 calculatedRoot = ethOutbox.calculateMerkleRoot(proof, index, itemHash);

        // Don't set the root, so it will be unknown
        vm.expectRevert(abi.encodeWithSelector(UnknownRoot.selector, calculatedRoot));
        ethOutbox.executeTransaction({
            proof: proof,
            index: index,
            l2Sender: user,
            to: address(100),
            l2Block: 1,
            l1Block: 1,
            l2Timestamp: 1,
            value: 0,
            data: ""
        });
    }

    function testExecuteBridgeCallRevertBridgeCallFailedNoReturnData() public {
        // Fund bridge
        vm.deal(address(bridge), 10 ether);

        // Create a contract that will revert without return data
        RevertingContract reverter = new RevertingContract();

        // Setup valid merkle proof
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = bytes32(0);
        uint256 index = 1;

        bytes32 itemHash = ethOutbox.calculateItemHash({
            l2Sender: user,
            to: address(reverter),
            l2Block: 1,
            l1Block: 1,
            l2Timestamp: 1,
            value: 0,
            data: abi.encodeWithSignature("revertWithoutData()")
        });

        bytes32 root = ethOutbox.calculateMerkleRoot(proof, index, itemHash);
        vm.prank(rollup);
        ethOutbox.updateSendRoot(root, bytes32(uint256(1)));

        vm.expectRevert(BridgeCallFailed.selector);
        ethOutbox.executeTransaction({
            proof: proof,
            index: index,
            l2Sender: user,
            to: address(reverter),
            l2Block: 1,
            l1Block: 1,
            l2Timestamp: 1,
            value: 0,
            data: abi.encodeWithSignature("revertWithoutData()")
        });
    }

    function testExecuteBridgeCallRevertWithReturnData() public {
        // Fund bridge
        vm.deal(address(bridge), 10 ether);

        // Create a contract that will revert with return data
        RevertingContract reverter = new RevertingContract();

        // Setup valid merkle proof
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = bytes32(0);
        uint256 index = 1;

        bytes32 itemHash = ethOutbox.calculateItemHash({
            l2Sender: user,
            to: address(reverter),
            l2Block: 1,
            l1Block: 1,
            l2Timestamp: 1,
            value: 0,
            data: abi.encodeWithSignature("revertWithData()")
        });

        bytes32 root = ethOutbox.calculateMerkleRoot(proof, index, itemHash);
        vm.prank(rollup);
        ethOutbox.updateSendRoot(root, bytes32(uint256(1)));

        vm.expectRevert("Custom revert message");
        ethOutbox.executeTransaction({
            proof: proof,
            index: index,
            l2Sender: user,
            to: address(reverter),
            l2Block: 1,
            l1Block: 1,
            l2Timestamp: 1,
            value: 0,
            data: abi.encodeWithSignature("revertWithData()")
        });
    }

    function testIsSpent() public {
        // First execute a transaction to mark it as spent
        bytes32[] memory proof = new bytes32[](6); // Need enough proof length for index 42
        proof[0] = bytes32(0);
        proof[1] = bytes32(0);
        proof[2] = bytes32(0);
        proof[3] = bytes32(0);
        proof[4] = bytes32(0);
        proof[5] = bytes32(0);
        uint256 index = 42;

        bytes32 itemHash = ethOutbox.calculateItemHash({
            l2Sender: user,
            to: address(100),
            l2Block: 1,
            l1Block: 1,
            l2Timestamp: 1,
            value: 0,
            data: ""
        });

        bytes32 root = ethOutbox.calculateMerkleRoot(proof, index, itemHash);
        vm.prank(rollup);
        ethOutbox.updateSendRoot(root, bytes32(uint256(1)));

        // Check it's not spent before execution
        assertFalse(ethOutbox.isSpent(index), "Should not be spent before execution");

        // Execute transaction
        ethOutbox.executeTransaction({
            proof: proof,
            index: index,
            l2Sender: user,
            to: address(100),
            l2Block: 1,
            l1Block: 1,
            l2Timestamp: 1,
            value: 0,
            data: ""
        });

        // Check it's spent after execution
        assertTrue(ethOutbox.isSpent(index), "Should be spent after execution");
    }

    function testL2ToL1BatchNum() public {
        // This function is deprecated and always returns 0
        assertEq(ethOutbox.l2ToL1BatchNum(), 0, "l2ToL1BatchNum should always return 0");
    }
}
