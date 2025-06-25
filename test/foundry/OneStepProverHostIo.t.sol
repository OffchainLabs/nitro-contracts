// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/osp/OneStepProverHostIo.sol";
import {ICustomDAProofValidator} from "../../src/osp/ICustomDAProofValidator.sol";

contract OneStepProverHostIoPublic is OneStepProverHostIo {
    constructor(
        address _customDAValidator
    ) OneStepProverHostIo(_customDAValidator) {}

    function executeReadPreImagePublic(
        ExecutionContext calldata context,
        Machine memory mach,
        Module memory mod,
        Instruction calldata inst,
        bytes calldata proof
    ) public view {
        super.executeReadPreImage(context, mach, mod, inst, proof);
    }
}

contract CustomDAProofValidatorMock is ICustomDAProofValidator {
    function validateReadPreimage(
        bytes calldata proof
    ) external pure override returns (bytes memory preimageChunk) {
        return new bytes(32);
    }
}

contract OneStepProverHostIoTest is Test {
    using MachineLib for Machine;
    using ValueLib for Value;
    using ValueStackLib for ValueStack;

    ICustomDAProofValidator mockCustomDAProofValidator;
    address owner = address(0x1234);

    function setUp() public {
        mockCustomDAProofValidator = new CustomDAProofValidatorMock();
    }

    function testCustomDAValidatorSupported() public {
        // Deploy OSP with mockCustomDAProofValidator as customDAValidator
        OneStepProverHostIoPublic ospHostIo =
            new OneStepProverHostIoPublic(address(mockCustomDAProofValidator));

        // Prepare a valid ReferenceDA proof
        bytes memory preimage =
            hex"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20";
        bytes32 hash = keccak256(preimage);
        uint64 offset = 0;
        uint8 version = 0x01;
        uint64 preimageSize = uint64(preimage.length);
        bytes memory proof = abi.encodePacked(hash, offset, version, preimageSize, preimage);

        ExecutionContext memory context;
        Machine memory mach;
        Module memory mod;
        Instruction memory inst;

        mach.valueStack.push(ValueLib.newI32(0));
        mach.valueStack.push(ValueLib.newI32(0));
        mod.moduleMemory.size = 32;
        inst.argumentData = 3; // CustomDA
        mod.moduleMemory.merkleRoot =
            0x3fc4ac0e48eb4af888852fca798249c069e469c12221c04bbc0c6321064c8fe0;

        ospHostIo.executeReadPreImagePublic(context, mach, mod, inst, proof);
    }

    function testCustomDAValidatorNotSupported() public {
        // Deploy OSP with address(0) as customDAValidator
        OneStepProverHostIoPublic ospHostIo = new OneStepProverHostIoPublic(address(0));

        // Prepare a valid ReferenceDA proof
        bytes memory preimage =
            hex"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20";
        bytes32 hash = keccak256(preimage);
        uint64 offset = 0;
        uint8 version = 0x01;
        uint64 preimageSize = uint64(preimage.length);
        bytes memory proof = abi.encodePacked(hash, offset, version, preimageSize, preimage);

        ExecutionContext memory context;
        Machine memory mach;
        Module memory mod;
        Instruction memory inst;

        mach.valueStack.push(ValueLib.newI32(0));
        mach.valueStack.push(ValueLib.newI32(0));
        mod.moduleMemory.size = 32;
        inst.argumentData = 3; // CustomDA
        mod.moduleMemory.merkleRoot =
            0x3fc4ac0e48eb4af888852fca798249c069e469c12221c04bbc0c6321064c8fe0;

        vm.expectRevert("CUSTOM_DA_VALIDATOR_NOT_SUPPORTED");
        ospHostIo.executeReadPreImagePublic(context, mach, mod, inst, proof);
    }
}
