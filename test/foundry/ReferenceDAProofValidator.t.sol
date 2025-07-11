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
    ) internal pure returns (bytes memory proof, bytes32 certHash) {
        bytes32 sha256Hash = sha256(abi.encodePacked(preimage));

        // Create certificate: [header(1), sha256Hash(32)]
        bytes memory certificate = new bytes(33);
        certificate[0] = 0x01; // header
        assembly {
            mstore(add(certificate, 33), sha256Hash)
        }
        certHash = keccak256(certificate);

        // Build proof with new format: [certSize(8), certificate(33), version(1), preimageSize(8), preimageData]
        uint256 proofLength = 8 + 33 + 1 + 8 + preimage.length;
        proof = new bytes(proofLength);

        // Set certificate size (8 bytes at position 0)
        assembly {
            let certSize := shl(192, 33)
            mstore(add(proof, 32), certSize)
        }

        // Copy certificate (33 bytes starting at position 8)
        for (uint256 i = 0; i < 33; i++) {
            proof[8 + i] = certificate[i];
        }

        // Set version (1 byte at position 41)
        proof[41] = bytes1(0x01);

        // Set preimage size (8 bytes at position 42)
        uint256 preimageLen = preimage.length;
        assembly {
            let preimageSize := shl(192, preimageLen)
            mstore(add(proof, 74), preimageSize)
        }

        // Copy preimage data (starting at position 50)
        for (uint256 i = 0; i < preimage.length; i++) {
            proof[50 + i] = preimage[i];
        }
    }

    function testValidateReadPreimage() public {
        // Test preimage data
        bytes memory preimage =
            "This is a test preimage that is longer than 32 bytes for testing chunk extraction";
        uint256 offset = 16; // Read from byte 16

        // Build valid proof
        (bytes memory proof, bytes32 certHash) = buildValidProof(preimage, offset);

        // Call validateReadPreimage
        bytes memory chunk = validator.validateReadPreimage(certHash, offset, proof);

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
        (bytes memory proof, bytes32 certHash) = buildValidProof(preimage, offset);

        // Validate
        bytes memory chunk = validator.validateReadPreimage(certHash, offset, proof);

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
        (bytes memory proof, bytes32 certHash) = buildValidProof(wrongPreimage, offset);

        // Replace the preimage data with wrong preimage data
        // The preimage starts at offset 50 in the proof (after certSize(8) + certificate(33) + version(1) + preimageSize(8))
        for (uint256 i = 0; i < preimage.length; i++) {
            proof[50 + i] = preimage[i];
        }

        // Update preimage size to match the wrong preimage
        assembly {
            let preimageSize := shl(192, 13) // "Test preimage" is 13 bytes
            mstore(add(proof, 74), preimageSize)
        }

        // Should revert when preimage hash doesn't match
        vm.expectRevert("Invalid preimage hash");
        validator.validateReadPreimage(certHash, offset, proof);
    }

    function testInvalidVersion() public {
        bytes memory preimage = "Test";
        uint256 offset = 0;

        // Build a valid proof
        (bytes memory proof, bytes32 certHash) = buildValidProof(preimage, offset);

        // Set wrong version (version byte is at position 41)
        proof[41] = bytes1(0x02); // Wrong version

        vm.expectRevert("Unsupported proof version");
        validator.validateReadPreimage(certHash, offset, proof);
    }

    function testProofTooShort() public {
        // Create a proof that's too short to contain the certificate
        bytes memory proof = new bytes(40); // Has header but not enough for full certificate

        // Set certificate size to 33 at position 0
        assembly {
            let certSize := shl(192, 33)
            mstore(add(proof, 32), certSize)
        }

        // Create a dummy certHash for the test
        bytes32 certHash = keccak256("test");

        vm.expectRevert("Proof too short for certificate");
        validator.validateReadPreimage(certHash, 0, proof);
    }
}
