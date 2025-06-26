// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/osp/ReferenceDAProofValidator.sol";

contract ReferenceDAProofValidatorTest is Test {
    ReferenceDAProofValidator validator;

    function setUp() public {
        validator = new ReferenceDAProofValidator();
    }

    function testValidateReadPreimage() public {
        // Test preimage data
        bytes memory preimage =
            "This is a test preimage that is longer than 32 bytes for testing chunk extraction";
        bytes32 hash = keccak256(preimage);
        uint256 offset = 16; // Read from byte 16

        // Build proof: [hash(32), offset(8), Version(1), PreimageSize(8), PreimageData]
        bytes memory proof = new bytes(49 + preimage.length);

        // Copy hash
        assembly {
            mstore(add(proof, 32), hash)
        }

        // Copy offset (8 bytes)
        assembly {
            let offsetData := shl(192, offset) // Shift to make it 8 bytes at the beginning
            mstore(add(proof, 64), offsetData)
        }

        // Set version
        proof[40] = bytes1(0x01);

        // Set preimage size (8 bytes)
        uint256 preimageSize = preimage.length;
        assembly {
            let sizeData := shl(192, preimageSize) // Shift to make it 8 bytes at the beginning
            mstore(add(proof, 73), sizeData)
        }

        // Copy preimage data
        for (uint256 i = 0; i < preimage.length; i++) {
            proof[49 + i] = preimage[i];
        }

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
        bytes32 hash = keccak256(preimage);
        uint256 offset = 8; // Only 6 bytes available from offset 8

        // Build proof
        bytes memory proof = new bytes(49 + preimage.length);

        // Copy hash
        assembly {
            mstore(add(proof, 32), hash)
        }

        // Copy offset
        assembly {
            let offsetData := shl(192, offset)
            mstore(add(proof, 64), offsetData)
        }

        // Set version
        proof[40] = bytes1(0x01);

        // Set preimage size
        assembly {
            let sizeData := shl(192, 14) // "Short preimage" is 14 bytes
            mstore(add(proof, 73), sizeData)
        }

        // Copy preimage
        for (uint256 i = 0; i < preimage.length; i++) {
            proof[49 + i] = preimage[i];
        }

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
        bytes32 wrongHash = keccak256("Wrong data");
        uint256 offset = 0;

        // Build proof with wrong hash
        bytes memory proof = new bytes(49 + preimage.length);

        assembly {
            mstore(add(proof, 32), wrongHash)
        }
        assembly {
            let offsetData := shl(192, offset)
            mstore(add(proof, 64), offsetData)
        }
        proof[40] = bytes1(0x01);
        assembly {
            let sizeData := shl(192, 13)
            mstore(add(proof, 73), sizeData)
        }
        for (uint256 i = 0; i < preimage.length; i++) {
            proof[49 + i] = preimage[i];
        }

        // Should revert
        vm.expectRevert("Invalid preimage");
        validator.validateReadPreimage(proof);
    }

    function testInvalidVersion() public {
        bytes memory preimage = "Test";
        bytes32 hash = keccak256(preimage);

        bytes memory proof = new bytes(49 + preimage.length);
        assembly {
            mstore(add(proof, 32), hash)
        }
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
