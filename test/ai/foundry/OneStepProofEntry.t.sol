// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../../src/osp/OneStepProofEntry.sol";
import "../../../src/osp/OneStepProver0.sol";
import "../../../src/osp/OneStepProverMemory.sol";
import "../../../src/osp/OneStepProverMath.sol";
import "../../../src/osp/OneStepProverHostIo.sol";

// Covers OneStepProofEntry.proveOneStep's halted-machine path, which is exercised by no
// existing test.
//
// For a halted machine MachineLib.hash is just keccak256("Machine finished:", globalStateHash),
// so we can hand-serialize a minimal all-empty machine whose hash depends only on the
// globalStateHash, then append a serialized GlobalState + MELState as proveOneStep expects:
//   proof = [serialized machine][serialized GlobalState][serialized MELState]
contract OneStepProofEntryHaltedMachineTest is Test {
    using GlobalStateLib for GlobalState;
    using MELStateLib for MELState;

    OneStepProofEntry osp;
    bytes32 constant WASM_ROOT = keccak256("INITIAL_WASM_MODULE_ROOT");

    function setUp() public {
        osp = new OneStepProofEntry(
            new OneStepProver0(),
            new OneStepProverMemory(),
            new OneStepProverMath(),
            new OneStepProverHostIo(address(0), address(0))
        );
    }

    // Serialize a minimal FINISHED machine with empty stacks, matching Deserialize.machine.
    // Only the globalStateHash field matters for a halted machine's hash. Packed encodes are
    // chunked to small arg counts (optimizer-off stack limit).
    function _serializeMachine(
        bytes32 gsHash
    ) internal pure returns (bytes memory) {
        bytes memory p1 = abi.encodePacked(uint8(1), bytes32(0), uint256(0)); // status FINISHED + valueStack
        bytes memory p2 = abi.encodePacked(bytes32(0), bytes32(0)); // valueMultiStack
        bytes memory p3 = abi.encodePacked(bytes32(0), uint256(0)); // internalStack
        bytes memory p4 = abi.encodePacked(bytes32(0), uint8(0)); // frameStack window (empty)
        bytes memory p5 = abi.encodePacked(bytes32(0), bytes32(0)); // frameMultiStack
        bytes memory p6 = abi.encodePacked(gsHash, uint32(0), uint32(0), uint32(0)); // gsHash, idxs, pc
        bytes memory p7 = abi.encodePacked(bytes32(0), bytes32(0)); // recoveryPc, modulesRoot
        return bytes.concat(p1, p2, p3, p4, p5, p6, p7);
    }

    function _serializeGlobalState(
        GlobalState memory g
    ) internal pure returns (bytes memory) {
        bytes memory a =
            abi.encodePacked(g.bytes32Vals[0], g.bytes32Vals[1], g.bytes32Vals[2], g.bytes32Vals[3]);
        bytes memory b = abi.encodePacked(g.u64Vals[0], g.u64Vals[1]);
        return bytes.concat(a, b);
    }

    function _serializeMELState(
        MELState memory m
    ) internal pure returns (bytes memory) {
        bytes memory a = abi.encodePacked(
            m.version,
            m.parentChainId,
            m.parentChainBlockNumber,
            uint256(uint160(m.batchPostingTargetAddress)),
            uint256(uint160(m.delayedMessagePostingTargetAddress))
        );
        bytes memory b = abi.encodePacked(
            m.parentChainBlockHash,
            m.parentChainPreviousBlockHash,
            m.batchCount,
            m.msgCount,
            m.localMsgAccumulator
        );
        bytes memory c = abi.encodePacked(
            m.delayedMessagesRead,
            m.delayedMessagesSeen,
            m.delayedMessageInboxAcc,
            m.delayedMessageOutboxAcc
        );
        return bytes.concat(a, b, c);
    }

    // machineGsHashField is the globalStateHash written into the serialized machine (which
    // determines beforeHash); g is the GlobalState appended after the machine.
    function _buildProof(
        bytes32 machineGsHashField,
        GlobalState memory g,
        MELState memory m
    ) internal pure returns (bytes memory) {
        return bytes.concat(
            _serializeMachine(machineGsHashField), _serializeGlobalState(g), _serializeMELState(m)
        );
    }

    function _finishedHash(
        bytes32 gsHash
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("Machine finished:", gsHash));
    }

    // Build a MELState whose hash we commit into the GlobalState's MEL slot.
    function _melState(
        bytes32 parentChainBlockHash,
        uint64 msgCount
    ) internal pure returns (MELState memory m) {
        m.version = 0;
        m.parentChainBlockHash = parentChainBlockHash;
        m.msgCount = msgCount;
    }

    function _execCtx(
        bytes32 target
    ) internal pure returns (ExecutionContext memory ctx) {
        ctx.targetParentChainBlockHash = target;
        ctx.initialWasmModuleRoot = WASM_ROOT;
    }

    // Halted machine whose committed MEL slot doesn't match the supplied MELState.
    function testRevertProveOneStepBadMELState() public {
        MELState memory m = _melState(keccak256("PCBH"), 1);
        GlobalState memory g;
        g.bytes32Vals[2] = keccak256("WRONG_MEL_HASH"); // != m.hash()
        bytes32 gsHash = g.hash();
        bytes memory proof = _buildProof(gsHash, g, m);

        vm.expectRevert("BAD_MEL_STATE");
        osp.proveOneStep(_execCtx(keccak256("PCBH")), 0, _finishedHash(gsHash), proof);
    }

    // Halted machine whose supplied GlobalState doesn't hash to the machine's committed
    // globalStateHash.
    function testRevertProveOneStepBadGlobalState() public {
        MELState memory m = _melState(keccak256("PCBH"), 1);
        GlobalState memory g;
        g.bytes32Vals[2] = m.hash();
        bytes32 wrongGsHash = keccak256("WRONG_GLOBAL_STATE"); // != g.hash()
        bytes memory proof = _buildProof(wrongGsHash, g, m);

        vm.expectRevert("BAD_GLOBAL_STATE");
        osp.proveOneStep(_execCtx(keccak256("PCBH")), 0, _finishedHash(wrongGsHash), proof);
    }

    // FINISHED, step 0, parentChainBlockHash != target -> kickstart (restart).
    function testProveOneStepKickstartBlockHashNotReached() public {
        bytes32 reached = keccak256("REACHED");
        bytes32 target = keccak256("TARGET"); // != reached
        MELState memory m = _melState(reached, 5);
        GlobalState memory g;
        g.bytes32Vals[2] = m.hash();
        g.u64Vals[1] = 5; // ExecutedMsgCount == msgCount, so only the block-hash branch fires
        bytes32 gsHash = g.hash();
        bytes memory proof = _buildProof(gsHash, g, m);

        bytes32 afterHash = osp.proveOneStep(_execCtx(target), 0, _finishedHash(gsHash), proof);
        assertEq(afterHash, osp.getStartMachineHash(gsHash, WASM_ROOT), "should kickstart machine");
    }

    // FINISHED, step 0, at target but ExecutedMsgCount < msgCount -> kickstart (restart).
    function testProveOneStepKickstartMessagesUnexecuted() public {
        bytes32 target = keccak256("TARGET");
        MELState memory m = _melState(target, 5); // parentChainBlockHash == target
        GlobalState memory g;
        g.bytes32Vals[2] = m.hash();
        g.u64Vals[1] = 3; // ExecutedMsgCount (3) < msgCount (5)
        bytes32 gsHash = g.hash();
        bytes memory proof = _buildProof(gsHash, g, m);

        bytes32 afterHash = osp.proveOneStep(_execCtx(target), 0, _finishedHash(gsHash), proof);
        assertEq(afterHash, osp.getStartMachineHash(gsHash, WASM_ROOT), "should kickstart machine");
    }

    // FINISHED, step 0, at target and all messages executed -> no kickstart, return mach.hash().
    function testProveOneStepFinishedNoKickstart() public {
        bytes32 target = keccak256("TARGET");
        MELState memory m = _melState(target, 5);
        GlobalState memory g;
        g.bytes32Vals[2] = m.hash();
        g.u64Vals[1] = 5; // ExecutedMsgCount == msgCount
        bytes32 gsHash = g.hash();
        bytes memory proof = _buildProof(gsHash, g, m);

        bytes32 beforeHash = _finishedHash(gsHash);
        bytes32 afterHash = osp.proveOneStep(_execCtx(target), 0, beforeHash, proof);
        assertEq(afterHash, beforeHash, "no kickstart: machine hash unchanged");
    }

    // A nonzero machineStep with the machine already FINISHED also takes the no-kickstart
    // return (the kickstart predicate requires machineStep == 0).
    function testProveOneStepNonZeroStepNoKickstart() public {
        bytes32 reached = keccak256("REACHED");
        bytes32 target = keccak256("TARGET"); // != reached, but step != 0 so no restart
        MELState memory m = _melState(reached, 5);
        GlobalState memory g;
        g.bytes32Vals[2] = m.hash();
        g.u64Vals[1] = 0;
        bytes32 gsHash = g.hash();
        bytes memory proof = _buildProof(gsHash, g, m);

        bytes32 beforeHash = _finishedHash(gsHash);
        bytes32 afterHash = osp.proveOneStep(_execCtx(target), 1, beforeHash, proof);
        assertEq(afterHash, beforeHash, "machineStep != 0 must not kickstart");
    }
}
