// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/osp/ReferenceDAProofValidator.sol";

contract ReferenceDAProofValidatorTest is Test {
    ReferenceDAProofValidator validator;

    function setUp() public {
        validator = new ReferenceDAProofValidator();
    }

    function buildValidProof(
        bytes memory preimage,
        uint256 offset
    ) internal pure returns (bytes memory proof) {
        bytes32 sha256Hash = sha256(abi.encodePacked(preimage));

        // Create certificate: [header(1), sha256Hash(32)]
        bytes memory certificate = new bytes(33);
        certificate[0] = 0x01; // header
        assembly {
            mstore(add(certificate, 33), sha256Hash)
        }
        bytes32 certKeccak256 = keccak256(certificate);

        // Build proof: [certKeccak256(32), offset(8), Version(1), CertificateSize(8), Certificate(33), PreimageSize(8), PreimageData]
        uint256 proofLength = 32 + 8 + 1 + 8 + 33 + 8 + preimage.length;
        proof = new bytes(proofLength);

        // Copy certKeccak256
        assembly {
            mstore(add(proof, 32), certKeccak256)
        }

        // Copy offset (8 bytes)
        assembly {
            let offsetData := shl(192, offset)
            mstore(add(proof, 64), offsetData)
        }

        // Set version
        proof[40] = bytes1(0x01);

        // Set certificate size (8 bytes)
        assembly {
            let certSize := shl(192, 33)
            mstore(add(proof, 73), certSize)
        }

        // Copy certificate
        for (uint256 i = 0; i < 33; i++) {
            proof[49 + i] = certificate[i];
        }

        // Set preimage size (8 bytes)
        uint256 preimageLen = preimage.length;
        assembly {
            let preimageSize := shl(192, preimageLen)
            mstore(add(proof, 114), preimageSize)
        }

        // Copy preimage data
        for (uint256 i = 0; i < preimage.length; i++) {
            proof[90 + i] = preimage[i];
        }
    }

    function testValidateReadPreimage() public {
        // Test preimage data
        bytes memory preimage =
            "This is a test preimage that is longer than 32 bytes for testing chunk extraction";
        uint256 offset = 16; // Read from byte 16

        // Build valid proof
        bytes memory proof = buildValidProof(preimage, offset);

        // Call validateReadPreimage
        bytes memory chunk = validator.validateReadPreimage(proof);

        // Verify the chunk
        assertEq(chunk.length, 32, "Chunk should be 32 bytes");

        // Verify chunk contents match the expected slice of preimage
        for (uint256 i = 0; i < 32; i++) {
            if (offset + i < preimage.length) {
                assertEq(chunk[i], preimage[offset + i], "Chunk byte mismatch");
            } else {
                assertEq(chunk[i], 0, "Chunk padding should be zero");
            }
        }
    }

    function testValidateReadPreimageAtEnd() public {
        // Test reading at the end of preimage (less than 32 bytes available)
        bytes memory preimage = "Short preimage";
        uint256 offset = 8; // Only 6 bytes available from offset 8

        // Build valid proof
        bytes memory proof = buildValidProof(preimage, offset);

        // Validate
        bytes memory chunk = validator.validateReadPreimage(proof);

        // Should get "eimage" (6 bytes) padded with zeros
        assertEq(chunk.length, 32);
        assertEq(chunk[0], bytes1("e"));
        assertEq(chunk[1], bytes1("i"));
        assertEq(chunk[2], bytes1("m"));
        assertEq(chunk[3], bytes1("a"));
        assertEq(chunk[4], bytes1("g"));
        assertEq(chunk[5], bytes1("e"));

        // Rest should be zeros
        for (uint256 i = 6; i < 32; i++) {
            assertEq(chunk[i], 0);
        }
    }

    function testInvalidHash() public {
        bytes memory preimage = "Test preimage";
        bytes memory wrongPreimage = "Wrong preimage data";
        uint256 offset = 0;

        // Build a valid proof with the wrong preimage to get wrong hash in certificate
        bytes memory proof = buildValidProof(wrongPreimage, offset);

        // Replace the preimage data with wrong preimage data
        // The preimage starts at offset 90 in the proof
        for (uint256 i = 0; i < preimage.length; i++) {
            proof[90 + i] = preimage[i];
        }

        // Update preimage size to match the wrong preimage
        assembly {
            let preimageSize := shl(192, 13) // "Test preimage" is 13 bytes
            mstore(add(proof, 114), preimageSize)
        }

        // Should revert when preimage hash doesn't match
        vm.expectRevert("Invalid preimage hash");
        validator.validateReadPreimage(proof);
    }

    function testInvalidVersion() public {
        bytes memory preimage = "Test";
        uint256 offset = 0;

        // Build a valid proof
        bytes memory proof = buildValidProof(preimage, offset);

        // Set wrong version
        proof[40] = bytes1(0x02); // Wrong version

        vm.expectRevert("Unsupported proof version");
        validator.validateReadPreimage(proof);
    }

    function testProofTooShort() public {
        bytes memory proof = new bytes(48); // Too short

        vm.expectRevert("Proof too short");
        validator.validateReadPreimage(proof);
    }
}
