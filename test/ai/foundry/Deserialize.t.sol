// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../../src/state/Deserialize.sol";
import "../../../src/state/MELState.sol";

// Exposes the internal Deserialize.melState for testing. The harness mirrors
// OneStepProofEntry.proveOneStep's usage (decode into a memory local, then hash) and keeps
// only the hash + offset in storage. Reading individual struct fields into extra locals, or
// putting the 14-field struct in storage / an external return, overflows the stack under
// the optimizer-off test profile. The hash equality is sufficient: abi.encode is
// order-sensitive, so any field/width/ordering decode error changes the hash or the offset.
contract DeserializeHarness {
    using MELStateLib for MELState;

    bytes32 public decodedHash;
    uint256 public lastOffset;

    function decode(bytes calldata proof, uint256 offset) external {
        MELState memory s;
        uint256 newOffset;
        (s, newOffset) = Deserialize.melState(proof, offset);
        lastOffset = newOffset;
        decodedHash = s.hash();
    }
}

// Deserialize is referenced by no existing test; this locks in the 14-field decode and the exact
// byte width (274 bytes).
contract DeserializeTest is Test {
    using MELStateLib for MELState;

    DeserializeHarness harness;

    function setUp() public {
        harness = new DeserializeHarness();
    }

    // Serialize a MELState exactly as Deserialize.melState expects to read it. Split into
    // small abi.encodePacked groups joined with bytes.concat — a single 14-arg packed encode
    // overflows the stack under the optimizer-off test profile.
    function _serializeMELState(
        MELState memory s
    ) internal pure returns (bytes memory) {
        bytes memory a = abi.encodePacked(
            s.version, // u16
            s.parentChainId, // u64
            s.parentChainBlockNumber, // u64
            uint256(uint160(s.batchPostingTargetAddress)), // addr read as u256
            uint256(uint160(s.delayedMessagePostingTargetAddress)) // addr read as u256
        );
        bytes memory b = abi.encodePacked(
            s.parentChainBlockHash, // b32
            s.parentChainPreviousBlockHash, // b32
            s.batchCount, // u64
            s.msgCount, // u64
            s.localMsgAccumulator // b32
        );
        bytes memory c = abi.encodePacked(
            s.delayedMessagesRead, // u64
            s.delayedMessagesSeen, // u64
            s.delayedMessageInboxAcc, // b32
            s.delayedMessageOutboxAcc // b32
        );
        return bytes.concat(a, b, c);
    }

    function _sampleMELState() internal pure returns (MELState memory s) {
        s.version = 7;
        s.parentChainId = 42161;
        s.parentChainBlockNumber = 123456789;
        s.batchPostingTargetAddress = address(0xBEEF);
        s.delayedMessagePostingTargetAddress = address(0xCAFE);
        s.parentChainBlockHash = keccak256("parentChainBlockHash");
        s.parentChainPreviousBlockHash = keccak256("parentChainPreviousBlockHash");
        s.batchCount = 9;
        s.msgCount = 100;
        s.localMsgAccumulator = keccak256("localMsgAccumulator");
        s.delayedMessagesRead = 5;
        s.delayedMessagesSeen = 6;
        s.delayedMessageInboxAcc = keccak256("delayedMessageInboxAcc");
        s.delayedMessageOutboxAcc = keccak256("delayedMessageOutboxAcc");
    }

    // A fully-populated MELState round-trips through serialization and Deserialize.melState,
    // and the offset advances by the exact field-width sum (274 bytes).
    function testDeserializeMELStateRoundTrip() public {
        MELState memory want = _sampleMELState();
        bytes memory proof = _serializeMELState(want);
        // 2 + 8 + 8 + 32 + 32 + 32 + 32 + 8 + 8 + 32 + 8 + 8 + 32 + 32 = 274
        assertEq(proof.length, 274, "unexpected serialized length");

        harness.decode(proof, 0);

        // hash equality proves every field decoded correctly and in order (abi.encode is
        // order-sensitive); the offset assertion pins the total decoded width.
        assertEq(harness.decodedHash(), want.hash(), "hash mismatch after round-trip");
        assertEq(harness.lastOffset(), 274, "offset must advance by the full struct width");
    }

    // A single wrong field must change the decoded hash (guards against a no-op round-trip).
    function testDeserializeMELStateDetectsFieldChange() public {
        MELState memory want = _sampleMELState();
        harness.decode(_serializeMELState(want), 0);
        bytes32 baseline = harness.decodedHash();

        MELState memory mutated = want;
        mutated.msgCount = want.msgCount + 1;
        harness.decode(_serializeMELState(mutated), 0);
        assertTrue(harness.decodedHash() != baseline, "hash should change when a field changes");
    }

    // Decoding works at a non-zero start offset (leading bytes are skipped).
    function testDeserializeMELStateAtOffset() public {
        MELState memory want = _sampleMELState();
        bytes memory prefix = hex"aabbccdd";
        bytes memory proof = abi.encodePacked(prefix, _serializeMELState(want));

        harness.decode(proof, prefix.length);

        assertEq(harness.decodedHash(), want.hash(), "hash mismatch after offset round-trip");
        assertEq(harness.lastOffset(), prefix.length + 274, "offset must advance from start");
    }
}
