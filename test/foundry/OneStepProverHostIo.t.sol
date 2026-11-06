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
        bytes32 certHash,
        uint256 offset,
        bytes calldata proof
    ) external pure override returns (bytes memory preimageChunk) {
        return new bytes(32);
    }

    function validateCertificate(
        bytes calldata proof
    ) external pure override returns (bool isValid) {
        // Extract certificate size
        if (proof.length < 8) {
            return false;
        }

        uint256 certSize;
        assembly {
            certSize := shr(192, calldataload(add(proof.offset, 0)))
        }

        if (proof.length < 8 + certSize) {
            return false;
        }

        bytes calldata certificate = proof[8:8 + certSize];

        // Simple mock validation - just check length
        return certificate.length == 33;
    }
}

contract CustomDAProofValidatorBadResponse is ICustomDAProofValidator {
    function validateReadPreimage(
        bytes32 certHash,
        uint256 offset,
        bytes calldata proof
    ) external pure override returns (bytes memory preimageChunk) {
        // Return invalid response (too long)
        return new bytes(33);
    }

    function validateCertificate(
        bytes calldata proof
    ) external pure override returns (bool isValid) {
        // Always return false for this mock
        return false;
    }
}

contract CustomDAProofValidatorEmptyResponse is ICustomDAProofValidator {
    function validateReadPreimage(
        bytes32 certHash,
        uint256 offset,
        bytes calldata proof
    ) external pure override returns (bytes memory preimageChunk) {
        // Return empty response
        return new bytes(0);
    }

    function validateCertificate(
        bytes calldata proof
    ) external pure override returns (bool isValid) {
        // Always return true for this mock
        return true;
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

    function buildMerkleProof(
        bytes32 leafContents
    ) internal pure returns (bytes memory) {
        // For a simple test case, we'll create a merkle tree with just one level
        // The leaf at index 0 contains our leafContents

        // Build the proof data: leafContents (32 bytes) + counterparts length (1 byte) + counterparts data
        bytes memory proofData = new bytes(32 + 1); // No counterparts for a single element tree

        // Copy leaf contents
        assembly {
            mstore(add(proofData, 32), leafContents)
        }

        // Set counterparts length to 0 (1 byte)
        proofData[32] = 0;

        return proofData;
    }

    function prepareCertificate(
        bytes memory preimage
    ) internal pure returns (bytes memory) {
        // Create certificate: [header(1), sha256Hash(32)]
        bytes memory certificate = new bytes(33);
        certificate[0] = 0x01; // header
        bytes32 sha256Hash = sha256(preimage);
        assembly {
            mstore(add(certificate, 33), sha256Hash)
        }
        return certificate;
    }

    function buildDAProof(
        bytes memory preimage
    ) internal pure returns (bytes memory) {
        // Create certificate: [header(1), sha256Hash(32)]
        bytes memory certificate = new bytes(33);
        certificate[0] = 0x01; // header
        bytes32 sha256Hash = sha256(preimage);
        assembly {
            mstore(add(certificate, 33), sha256Hash)
        }

        // Build CustomDA proof with new format: [certSize(8), certificate, version(1), preimageSize(8), preimageData]
        return abi.encodePacked(
            uint64(33), // certSize
            certificate,
            uint8(0x01), // version
            uint64(preimage.length), // preimageSize
            preimage
        );
    }

    function buildFullProof(
        bytes memory preimage
    ) internal pure returns (bytes32 certKeccak256, bytes memory proof) {
        bytes memory certificate = prepareCertificate(preimage);
        certKeccak256 = keccak256(certificate);
        // Build CustomDA proof with new format: [certSize(8), certificate, version(1), preimageSize(8), preimageData]
        bytes memory customDAProof = buildDAProof(preimage);

        // Build merkle proof for the leaf containing certKeccak256
        bytes memory merkleProof = buildMerkleProof(certKeccak256);

        // Build complete proof: merkleProof + proofType(1) + customDAProof
        return (certKeccak256, abi.encodePacked(merkleProof, uint8(0), customDAProof));
    }

    function testWrongCertificateHash() public {
        // Deploy OSP with mockCustomDAProofValidator as customDAValidator
        OneStepProverHostIoPublic ospHostIo =
            new OneStepProverHostIoPublic(address(mockCustomDAProofValidator));

        // Create a different certificate hash that the machine expects
        bytes32 correctCertKeccak256 = keccak256(
            prepareCertificate(
                hex"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"
            )
        );

        // Build the DA proof with another certificate
        bytes memory customDAProof =
            buildDAProof(hex"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f201337");

        // Build merkle proof for the correct certificate hash (what the machine expects)
        bytes memory merkleProof = buildMerkleProof(correctCertKeccak256);

        // Build complete proof
        bytes memory proof = abi.encodePacked(merkleProof, uint8(0), customDAProof);

        ExecutionContext memory context;
        Machine memory mach;
        Module memory mod;
        Instruction memory inst;

        mach.valueStack.push(ValueLib.newI32(0)); // ptr
        mach.valueStack.push(ValueLib.newI32(0)); // preimageOffset
        mod.moduleMemory.size = 32;
        inst.argumentData = 3; // CustomDA

        // Set the merkleRoot to match what the machine expects
        mod.moduleMemory.merkleRoot =
            keccak256(abi.encodePacked("Memory leaf:", correctCertKeccak256));

        vm.expectRevert("WRONG_CERTIFICATE_HASH");
        ospHostIo.executeReadPreImagePublic(context, mach, mod, inst, proof);
    }

    function testCustomDAValidatorSupported() public {
        // Deploy OSP with mockCustomDAProofValidator as customDAValidator
        OneStepProverHostIoPublic ospHostIo =
            new OneStepProverHostIoPublic(address(mockCustomDAProofValidator));

        (bytes32 certKeccak256, bytes memory proof) =
            buildFullProof(hex"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20");

        ExecutionContext memory context;
        Machine memory mach;
        Module memory mod;
        Instruction memory inst;

        mach.valueStack.push(ValueLib.newI32(0)); // ptr
        mach.valueStack.push(ValueLib.newI32(0)); // preimageOffset
        mod.moduleMemory.size = 32;
        inst.argumentData = 3; // CustomDA

        // Set the merkleRoot to match our single-element merkle tree
        mod.moduleMemory.merkleRoot = keccak256(abi.encodePacked("Memory leaf:", certKeccak256));

        ospHostIo.executeReadPreImagePublic(context, mach, mod, inst, proof);
    }

    function testCustomDAValidatorNotSupported() public {
        // Deploy OSP with address(0) as customDAValidator
        OneStepProverHostIoPublic ospHostIo = new OneStepProverHostIoPublic(address(0));

        (bytes32 certKeccak256, bytes memory proof) =
            buildFullProof(hex"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20");

        ExecutionContext memory context;
        Machine memory mach;
        Module memory mod;
        Instruction memory inst;

        mach.valueStack.push(ValueLib.newI32(0)); // ptr
        mach.valueStack.push(ValueLib.newI32(0)); // preimageOffset
        mod.moduleMemory.size = 32;
        inst.argumentData = 3; // CustomDA

        // Set the merkleRoot to match our single-element merkle tree
        mod.moduleMemory.merkleRoot = keccak256(abi.encodePacked("Memory leaf:", certKeccak256));

        vm.expectRevert("CUSTOM_DA_VALIDATOR_NOT_SUPPORTED");
        ospHostIo.executeReadPreImagePublic(context, mach, mod, inst, proof);
    }

    function testCustomDAProofTooShort() public {
        // Deploy OSP with mockCustomDAProofValidator as customDAValidator
        OneStepProverHostIoPublic ospHostIo =
            new OneStepProverHostIoPublic(address(mockCustomDAProofValidator));

        bytes32 certKeccak256 = keccak256("test");
        bytes memory merkleProof = buildMerkleProof(certKeccak256);

        // Build proof that's too short (less than 8 bytes for cert size)
        bytes memory customDAProof = new bytes(7);
        bytes memory proof = abi.encodePacked(merkleProof, uint8(0), customDAProof);

        ExecutionContext memory context;
        Machine memory mach;
        Module memory mod;
        Instruction memory inst;

        mach.valueStack.push(ValueLib.newI32(0)); // ptr
        mach.valueStack.push(ValueLib.newI32(0)); // preimageOffset
        mod.moduleMemory.size = 32;
        inst.argumentData = 3; // CustomDA

        mod.moduleMemory.merkleRoot = keccak256(abi.encodePacked("Memory leaf:", certKeccak256));

        vm.expectRevert("CUSTOM_DA_PROOF_TOO_SHORT");
        ospHostIo.executeReadPreImagePublic(context, mach, mod, inst, proof);
    }

    function testProofTooShortForCert() public {
        // Deploy OSP with mockCustomDAProofValidator as customDAValidator
        OneStepProverHostIoPublic ospHostIo =
            new OneStepProverHostIoPublic(address(mockCustomDAProofValidator));

        bytes32 certKeccak256 = keccak256("test");
        bytes memory merkleProof = buildMerkleProof(certKeccak256);

        // Build proof with cert size but not enough bytes for the certificate
        bytes memory customDAProof = new bytes(10);
        // Set certSize to 33 but only provide 10 bytes total
        assembly {
            let certSize := shl(192, 33)
            mstore(add(customDAProof, 32), certSize)
        }
        bytes memory proof = abi.encodePacked(merkleProof, uint8(0), customDAProof);

        ExecutionContext memory context;
        Machine memory mach;
        Module memory mod;
        Instruction memory inst;

        mach.valueStack.push(ValueLib.newI32(0)); // ptr
        mach.valueStack.push(ValueLib.newI32(0)); // preimageOffset
        mod.moduleMemory.size = 32;
        inst.argumentData = 3; // CustomDA

        mod.moduleMemory.merkleRoot = keccak256(abi.encodePacked("Memory leaf:", certKeccak256));

        vm.expectRevert("PROOF_TOO_SHORT_FOR_CERT");
        ospHostIo.executeReadPreImagePublic(context, mach, mod, inst, proof);
    }

    function testUnknownPreimageProof() public {
        // Deploy OSP with mockCustomDAProofValidator as customDAValidator
        OneStepProverHostIoPublic ospHostIo =
            new OneStepProverHostIoPublic(address(mockCustomDAProofValidator));

        bytes memory preimage =
            hex"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20";
        bytes memory certificate = prepareCertificate(preimage);
        bytes32 certKeccak256 = keccak256(certificate);
        bytes memory customDAProof = buildDAProof(preimage);
        bytes memory merkleProof = buildMerkleProof(certKeccak256);

        // Build complete proof with wrong proofType (not 0)
        bytes memory proof = abi.encodePacked(merkleProof, uint8(1), customDAProof);

        ExecutionContext memory context;
        Machine memory mach;
        Module memory mod;
        Instruction memory inst;

        mach.valueStack.push(ValueLib.newI32(0)); // ptr
        mach.valueStack.push(ValueLib.newI32(0)); // preimageOffset
        mod.moduleMemory.size = 32;
        inst.argumentData = 3; // CustomDA

        mod.moduleMemory.merkleRoot = keccak256(abi.encodePacked("Memory leaf:", certKeccak256));

        vm.expectRevert("UNKNOWN_PREIMAGE_PROOF");
        ospHostIo.executeReadPreImagePublic(context, mach, mod, inst, proof);
    }

    function testInvalidCustomDAResponseTooLong() public {
        // Deploy OSP with a validator that returns too long response
        CustomDAProofValidatorBadResponse badValidator = new CustomDAProofValidatorBadResponse();
        OneStepProverHostIoPublic ospHostIo = new OneStepProverHostIoPublic(address(badValidator));

        (bytes32 certKeccak256, bytes memory proof) =
            buildFullProof(hex"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20");

        ExecutionContext memory context;
        Machine memory mach;
        Module memory mod;
        Instruction memory inst;

        mach.valueStack.push(ValueLib.newI32(0)); // ptr
        mach.valueStack.push(ValueLib.newI32(0)); // preimageOffset
        mod.moduleMemory.size = 32;
        inst.argumentData = 3; // CustomDA

        mod.moduleMemory.merkleRoot = keccak256(abi.encodePacked("Memory leaf:", certKeccak256));

        vm.expectRevert("INVALID_CUSTOM_DA_RESPONSE");
        ospHostIo.executeReadPreImagePublic(context, mach, mod, inst, proof);
    }

    function testInvalidCustomDAResponseEmpty() public {
        // Deploy OSP with a validator that returns empty response
        CustomDAProofValidatorEmptyResponse emptyValidator =
            new CustomDAProofValidatorEmptyResponse();
        OneStepProverHostIoPublic ospHostIo = new OneStepProverHostIoPublic(address(emptyValidator));

        (bytes32 certKeccak256, bytes memory proof) =
            buildFullProof(hex"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20");

        ExecutionContext memory context;
        Machine memory mach;
        Module memory mod;
        Instruction memory inst;

        mach.valueStack.push(ValueLib.newI32(0)); // ptr
        mach.valueStack.push(ValueLib.newI32(0)); // preimageOffset
        mod.moduleMemory.size = 32;
        inst.argumentData = 3; // CustomDA

        mod.moduleMemory.merkleRoot = keccak256(abi.encodePacked("Memory leaf:", certKeccak256));

        vm.expectRevert("INVALID_CUSTOM_DA_RESPONSE");
        ospHostIo.executeReadPreImagePublic(context, mach, mod, inst, proof);
    }
}
