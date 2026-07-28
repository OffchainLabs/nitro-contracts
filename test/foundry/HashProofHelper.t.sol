// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/osp/HashProofHelper.sol";

contract HashProofHelperTest is Test {
    HashProofHelper hph;
    HashProofHelper hphFull;
    HashProofHelper hphSplit;

    uint256 constant KECCAK_ROUND_INPUT = 136;

    function setUp() public {
        hph = new HashProofHelper();
        hphFull = new HashProofHelper();
        hphSplit = new HashProofHelper();
    }

    // A non-final chunk whose length is not a multiple of the keccak round size is rejected.
    function testRevertNotBlockAligned() public {
        bytes memory data = new bytes(100); // not a multiple of 136
        vm.expectRevert("NOT_BLOCK_ALIGNED");
        hph.proveWithSplitPreimage(data, 0, 0); // flags 0 => non-final
    }

    // The offset must stay constant across the chunks of a single split proof.
    function testRevertDiffOffset() public {
        bytes memory chunk1 = new bytes(KECCAK_ROUND_INPUT); // round-aligned, non-final
        hph.proveWithSplitPreimage(chunk1, 0, 0); // establishes in-progress state at offset 0
        bytes memory chunk2 = new bytes(64);
        vm.expectRevert("DIFF_OFFSET");
        hph.proveWithSplitPreimage(chunk2, 5, 1); // final chunk with a different offset
    }

    // Requesting a part that was never proven reverts with NotProven.
    function testRevertGetPreimagePartNotProven() public {
        bytes32 fullHash = keccak256("never-proven");
        vm.expectRevert(
            abi.encodeWithSelector(IHashProofHelper.NotProven.selector, fullHash, uint64(0))
        );
        hph.getPreimagePart(fullHash, 0);
    }

    // An offset past the end of a full preimage proves an empty (but present) part.
    function testFullPreimageOffsetPastEndEmptyPart() public {
        bytes memory data = "hello world"; // 11 bytes
        uint64 offset = 100;
        bytes32 fullHash = hph.proveWithFullPreimage(data, offset);
        assertEq(fullHash, keccak256(data), "hash mismatch");
        assertEq(hph.getPreimagePart(fullHash, offset).length, 0, "part should be empty");
    }

    // Same boundary, proved through the split path.
    function testSplitPreimageOffsetPastEndEmptyPart() public {
        bytes memory data = "hello world"; // 11 bytes
        uint64 offset = 100;
        bytes32 fullHash = hph.proveWithSplitPreimage(data, offset, 1); // single final chunk
        assertEq(fullHash, keccak256(data), "hash mismatch");
        assertEq(hph.getPreimagePart(fullHash, offset).length, 0, "part should be empty");
    }

    // The clear flag (bit 1) discards stale in-progress state before a new proof.
    function testSplitPreimageClearFlagResetsState() public {
        // leave a stale, in-progress chunk in the caller's keccak state
        hph.proveWithSplitPreimage(new bytes(KECCAK_ROUND_INPUT), 0, 0);

        // prove a different preimage from scratch: flags = isFinal (1) | clear (2) = 3
        bytes memory realData = "the real preimage";
        bytes32 fullHash = hph.proveWithSplitPreimage(realData, 0, 3);

        // the stale chunk must not contribute to the hash
        assertEq(fullHash, keccak256(realData), "stale state was not cleared");
        assertEq(hph.getPreimagePart(fullHash, 0), realData, "wrong proven part");
    }

    // Builds a deterministic, varied byte string of the given length.
    function _fill(
        uint256 len
    ) internal pure returns (bytes memory b) {
        b = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            b[i] = bytes1(uint8(i));
        }
    }

    // Copies data[start:end] out of a memory buffer.
    function _slice(
        bytes memory data,
        uint256 start,
        uint256 end
    ) internal pure returns (bytes memory out) {
        out = new bytes(end - start);
        for (uint256 i = 0; i < out.length; i++) {
            out[i] = data[start + i];
        }
    }

    function testEmptyPreimage() public {
        bytes memory data = new bytes(0);
        bytes32 expected = keccak256(data);

        bytes32 fullHash = hph.proveWithFullPreimage(data, 0);
        assertEq(fullHash, expected, "full empty hash");
        assertEq(hph.getPreimagePart(fullHash, 0).length, 0, "full empty part");

        bytes32 splitHash = hph.proveWithSplitPreimage(data, 0, 1); // single empty final chunk
        assertEq(splitHash, expected, "split empty hash");
        assertEq(hph.getPreimagePart(splitHash, 0).length, 0, "split empty part");
    }

    // Lengths that are exact multiples of the keccak rate require an extra padding-only block.
    function testBlockMultipleLength() public {
        bytes memory d136 = _fill(136);
        assertEq(hph.proveWithSplitPreimage(d136, 0, 1), keccak256(d136), "136-byte hash");

        bytes memory d272 = _fill(272);
        assertEq(hph.proveWithSplitPreimage(d272, 0, 1), keccak256(d272), "272-byte hash");
    }

    // A single split call whose chunk spans multiple keccak blocks.
    function testSingleChunkLargerThanRound() public {
        bytes memory d200 = _fill(200);
        bytes32 h200 = hph.proveWithSplitPreimage(d200, 0, 1);
        assertEq(h200, keccak256(d200), "200-byte single chunk hash");
        assertEq(hph.getPreimagePart(h200, 0), _slice(d200, 0, 32), "200-byte part");

        bytes memory d400 = _fill(400);
        assertEq(
            hph.proveWithSplitPreimage(d400, 0, 1), keccak256(d400), "400-byte single chunk hash"
        );

        // a non-final two-block chunk followed by a final remainder
        bytes memory full = _fill(300);
        hph.proveWithSplitPreimage(_slice(full, 0, 272), 0, 0); // non-final, 2 blocks
        bytes32 h = hph.proveWithSplitPreimage(_slice(full, 272, 300), 0, 1); // final 28 bytes
        assertEq(h, keccak256(full), "272 non-final + remainder hash");
    }

    // In-progress split state is keyed by msg.sender, so two senders interleaving split proofs
    // (of different preimages, at different offsets) must not corrupt each other.
    function testSplitPreimagePerSenderIsolation() public {
        address alice = address(0xa11ce);
        address bob = address(0xb0b);

        bytes memory aliceData = _fill(200); // 136 (non-final) + 64 (final)
        bytes memory bobData = _fill(168); //   136 (non-final) + 32 (final)
        uint64 aliceOffset = 0;
        uint64 bobOffset = 50;

        // interleave the two senders' chunks
        vm.prank(alice);
        hph.proveWithSplitPreimage(_slice(aliceData, 0, 136), aliceOffset, 0);
        vm.prank(bob);
        hph.proveWithSplitPreimage(_slice(bobData, 0, 136), bobOffset, 0);
        vm.prank(alice);
        bytes32 aliceHash = hph.proveWithSplitPreimage(_slice(aliceData, 136, 200), aliceOffset, 1);
        vm.prank(bob);
        bytes32 bobHash = hph.proveWithSplitPreimage(_slice(bobData, 136, 168), bobOffset, 1);

        // each sender's proof finalizes to its own preimage, uncorrupted by the other's chunks
        assertEq(aliceHash, keccak256(aliceData), "alice hash corrupted by interleaving");
        assertEq(bobHash, keccak256(bobData), "bob hash corrupted by interleaving");
        assertEq(
            hph.getPreimagePart(aliceHash, aliceOffset), _slice(aliceData, 0, 32), "alice part"
        );
        assertEq(hph.getPreimagePart(bobHash, bobOffset), _slice(bobData, 50, 82), "bob part");
    }

    // clearSplitProof() discards the caller's in-progress state.
    function testClearSplitProofDiscardsState() public {
        // leave a stale, in-progress chunk in the caller's keccak state
        hph.proveWithSplitPreimage(new bytes(KECCAK_ROUND_INPUT), 0, 0);

        // explicitly clear it
        hph.clearSplitProof();

        // a fresh proof (no clear flag, same offset) must not include the stale chunk
        bytes memory realData = "the real preimage";
        bytes32 fullHash = hph.proveWithSplitPreimage(realData, 0, 1);
        assertEq(fullHash, keccak256(realData), "stale state not discarded by clearSplitProof");
        assertEq(hph.getPreimagePart(fullHash, 0), realData, "wrong proven part");
    }

    // An empty final chunk after full blocks triggers the padding-only round.
    function testEmptyFinalChunk() public {
        bytes memory d136 = _fill(136);
        hph.proveWithSplitPreimage(d136, 0, 0); // non-final
        assertEq(
            hph.proveWithSplitPreimage(new bytes(0), 0, 1), keccak256(d136), "136 + empty final"
        );

        bytes memory d272 = _fill(272);
        hph.proveWithSplitPreimage(d272, 0, 0); // non-final, 2 blocks
        assertEq(
            hph.proveWithSplitPreimage(new bytes(0), 0, 1), keccak256(d272), "272 + empty final"
        );
    }

    // Differential property: full and split proofs agree on the hash and the proven part for
    // any valid input, and neither reverts. Uses randomized chunk sizes (multiples of 136) and
    // covers length 0 and offsets past the end of the preimage.
    function testFuzz_fullVsSplit(
        bytes calldata data,
        uint64 rawOffset,
        uint256 chunkSeed
    ) public {
        vm.assume(data.length <= 600);
        uint64 offset =
            data.length == 0 ? rawOffset : uint64(uint256(rawOffset) % (2 * data.length + 1));

        bytes32 fullHash = hphFull.proveWithFullPreimage(data, offset);

        bytes32 splitHash;
        if (data.length == 0) {
            splitHash = hphSplit.proveWithSplitPreimage(data, offset, 1);
        } else {
            uint256 provenLen = 0;
            uint256 seed = chunkSeed;
            while (provenLen < data.length) {
                uint256 numBlocks = 1 + (seed % 3); // 1..3 keccak blocks per chunk
                seed = uint256(keccak256(abi.encode(seed)));
                uint256 next = provenLen + numBlocks * KECCAK_ROUND_INPUT;
                if (next >= data.length) next = data.length;
                uint256 flags = next == data.length ? 1 : 0; // final only on the last chunk
                splitHash = hphSplit.proveWithSplitPreimage(data[provenLen:next], offset, flags);
                provenLen = next;
            }
        }

        assertEq(fullHash, keccak256(data), "full hash mismatch");
        assertEq(splitHash, fullHash, "split hash mismatch");

        bytes memory expected;
        if (offset < data.length) {
            uint256 end = uint256(offset) + 32;
            if (end > data.length) end = data.length;
            expected = data[offset:end];
        }
        assertLe(expected.length, 32, "part > 32 bytes");
        assertEq(hphFull.getPreimagePart(fullHash, offset), expected, "full part mismatch");
        assertEq(hphSplit.getPreimagePart(splitHash, offset), expected, "split part mismatch");
    }
}
