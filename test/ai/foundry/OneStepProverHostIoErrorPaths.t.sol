// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../../src/osp/OneStepProverHostIo.sol";

// Error/edge branches of OneStepProverHostIo that the existing
// test/foundry/OneStepProverHostIo.t.sol does not reach:
//   - GET_END_PARENT_CHAIN_BLOCK_HASH with an invalid destination leaf -> ERRORED
//   - GET_END_PARENT_CHAIN_BLOCK_HASH with an inconsistent committed memory root -> WRONG_MEM_ROOT
//   - keccak ReadPreImage with an unrecognized proofType -> UNKNOWN_PREIMAGE_PROOF
contract OneStepProverHostIoErrorPathsTest is Test {
    using ValueStackLib for ValueStack;

    OneStepProverHostIo prover;

    function setUp() public {
        prover = new OneStepProverHostIo(address(0), address(0));
    }

    // Single-leaf memory proof: leaf at index 0, no counterparts.
    function buildMerkleProof(
        bytes32 leafContents
    ) internal pure returns (bytes memory) {
        bytes memory proofData = new bytes(32 + 1);
        assembly {
            mstore(add(proofData, 32), leafContents)
        }
        proofData[32] = 0; // counterparts length
        return proofData;
    }

    // An out-of-bounds destination pointer errors the machine and leaves memory untouched.
    function testGetEndParentChainBlockHashInvalidLeaf() public {
        ExecutionContext memory context;
        context.targetParentChainBlockHash = keccak256("TARGET");
        Machine memory mach;
        Module memory mod;
        Instruction memory inst;
        inst.opcode = Instructions.GET_END_PARENT_CHAIN_BLOCK_HASH;

        // ptr = 32 with size = 32 -> ptr + 32 > size, so isValidLeaf is false
        mach.valueStack.push(ValueLib.newI32(32));
        mod.moduleMemory.size = 32;
        bytes32 originalRoot = keccak256(abi.encodePacked("Memory leaf:", bytes32(0)));
        mod.moduleMemory.merkleRoot = originalRoot;

        // proof can be empty: the opcode returns before proveLeaf
        (Machine memory resultMach, Module memory resultMod) =
            prover.executeOneStep(context, mach, mod, inst, "");

        assertTrue(resultMach.status == MachineStatus.ERRORED, "machine should be ERRORED");
        assertEq(resultMod.moduleMemory.merkleRoot, originalRoot, "memory root must be unchanged");
    }

    // A committed memory root inconsistent with the proven leaf reverts in proveLeaf.
    function testGetEndParentChainBlockHashWrongMemRoot() public {
        ExecutionContext memory context;
        context.targetParentChainBlockHash = keccak256("TARGET");
        Machine memory mach;
        Module memory mod;
        Instruction memory inst;
        inst.opcode = Instructions.GET_END_PARENT_CHAIN_BLOCK_HASH;

        mach.valueStack.push(ValueLib.newI32(0)); // valid leaf
        mod.moduleMemory.size = 32;
        // committed root is for some OTHER leaf, but the proof is built for leaf bytes32(0)
        mod.moduleMemory.merkleRoot =
            keccak256(abi.encodePacked("Memory leaf:", keccak256("OTHER")));
        bytes memory proof = buildMerkleProof(bytes32(0));

        vm.expectRevert("WRONG_MEM_ROOT");
        prover.executeOneStep(context, mach, mod, inst, proof);
    }

    // A keccak256 ReadPreImage request with an unrecognized proofType reverts.
    function testReadPreImageUnknownKeccakProof() public {
        ExecutionContext memory context;
        Machine memory mach;
        Module memory mod;
        Instruction memory inst;
        inst.opcode = Instructions.READ_PRE_IMAGE;
        inst.argumentData = 0; // keccak256 preimage

        bytes32 fullHash = keccak256("SOME_PREIMAGE");
        mach.valueStack.push(ValueLib.newI32(0)); // ptr
        mach.valueStack.push(ValueLib.newI32(0)); // preimageOffset
        mod.moduleMemory.size = 32;
        mod.moduleMemory.merkleRoot = keccak256(abi.encodePacked("Memory leaf:", fullHash));
        // proofType = 2 is neither 0 (full preimage) nor 1 (HashProofHelper)
        bytes memory proof = abi.encodePacked(buildMerkleProof(fullHash), uint8(2));

        vm.expectRevert("UNKNOWN_PREIMAGE_PROOF");
        prover.executeOneStep(context, mach, mod, inst, proof);
    }
}
