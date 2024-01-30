// Copyright 2021-2023, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./ValueStack.sol";
import "./Instructions.sol";
import "./MultiStack.sol";
import "./StackFrame.sol";
import "./GuardStack.sol";

enum MachineStatus {
    RUNNING,
    FINISHED,
    ERRORED,
    TOO_FAR
}

struct Machine {
    MachineStatus status;
    ValueStack valueStack;
    MultiStack valueMultiStack;
    ValueStack internalStack;
    StackFrameWindow frameStack;
    MultiStack frameMultiStack;
    GuardStack guardStack;
    bytes32 globalStateHash;
    uint32 moduleIdx;
    uint32 functionIdx;
    uint32 functionPc;
    bytes32 modulesRoot;
    bool cothread;
}

library MachineLib {
    using StackFrameLib for StackFrameWindow;
    using GuardStackLib for GuardStack;
    using ValueStackLib for ValueStack;
    using MultiStackLib for MultiStack;

    function hash(Machine memory mach) internal pure returns (bytes32) {
        // Warning: the non-running hashes are replicated in Challenge
        if (mach.status == MachineStatus.RUNNING) {
            bytes32 valueMultiHash = mach.valueMultiStack.hash(mach.valueStack.hash(), mach.cothread);
            bytes32 frameMultiHash = mach.frameMultiStack.hash(mach.frameStack.hash(), mach.cothread);
            bytes memory preimage = abi.encodePacked(
                "Machine running:",
                valueMultiHash,
                mach.internalStack.hash(),
                frameMultiHash,
                mach.globalStateHash,
                mach.moduleIdx,
                mach.functionIdx,
                mach.functionPc,
                mach.modulesRoot
            );

            if (mach.guardStack.empty() && !mach.cothread) {
                return keccak256(preimage);
            } else {
                return
                    keccak256(
                        abi.encodePacked(preimage, "With guards:", mach.guardStack.hash())
                    );
            }
        } else if (mach.status == MachineStatus.FINISHED) {
            return keccak256(abi.encodePacked("Machine finished:", mach.globalStateHash));
        } else if (mach.status == MachineStatus.ERRORED) {
            return keccak256(abi.encodePacked("Machine errored:"));
        } else if (mach.status == MachineStatus.TOO_FAR) {
            return keccak256(abi.encodePacked("Machine too far:"));
        } else {
            revert("BAD_MACH_STATUS");
        }
    }

    function setPc(Machine memory mach, Value memory pc) internal pure {
        if (pc.valueType == ValueType.REF_NULL) {
            mach.status = MachineStatus.ERRORED;
            return;
        }

        uint256 data = pc.contents;
        require(pc.valueType == ValueType.INTERNAL_REF, "INVALID_PC_TYPE");
        require(data >> 96 == 0, "INVALID_PC_DATA");

        mach.functionPc = uint32(data);
        mach.functionIdx = uint32(data >> 32);
        mach.moduleIdx = uint32(data >> 64);
    }
}
