// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./IHashProofHelper.sol";
import "../libraries/CryptographyPrimitives.sol";

contract HashProofHelper is IHashProofHelper {
    /// @dev Tracks an in-progress split preimage proof
    struct KeccakState {
        /// @dev Offset determining which slice is extracted and stored from the preimage (up to 32 bytes)
        uint64 offset;
        /// @dev The bytes being collected for the [offset, offset+32) slice, built up across chunks
        bytes part;
        /// @dev The 1600-bit keccak internal state as 25 × 64-bit words
        ///      (stored in column-major order to match CryptographyPrimitives.keccakF's layout)
        uint64[25] state;
        /// @dev Total bytes of preimage data absorbed so far across all chunks
        uint256 length;
    }

    /// @dev Stores a 32-byte (or shorter) slice extracted from a fully-proven preimage.
    struct PreimagePart {
        /// @dev Whether this entry has been set by a completed proof.
        bool proven;
        /// @dev The extracted slice at this offset. Empty if offset >= preimage length.
        bytes part;
    }

    /// @dev Completed proofs, keyed by (keccak256 hash of the full preimage, byte offset)
    mapping(bytes32 => mapping(uint64 => PreimagePart)) private preimageParts;
    /// @dev In-progress split proofs, keyed by msg.sender
    mapping(address => KeccakState) public keccakStates;

    /// @dev Maximum bytes stored per part — matches one EVM word and one WASM ReadPreImage result
    uint256 private constant MAX_PART_LENGTH = 32;
    /// @dev Number of bytes absorbed into the keccak sponge state per round — matches the keccak256 rate for 1600-bit state
    uint256 private constant KECCAK_ROUND_INPUT = 136;

    /// @inheritdoc IHashProofHelper
    function proveWithFullPreimage(
        bytes calldata data,
        uint64 offset
    ) external returns (bytes32 fullHash) {
        fullHash = keccak256(data);
        bytes memory part;
        if (data.length > offset) {
            uint256 partLength = data.length - offset;
            if (partLength > MAX_PART_LENGTH) {
                partLength = MAX_PART_LENGTH;
            }
            part = data[offset:(offset + partLength)];
        }
        preimageParts[fullHash][offset] = PreimagePart({proven: true, part: part});
        emit PreimagePartProven(fullHash, offset, part);
    }

    /// @inheritdoc IHashProofHelper
    function proveWithSplitPreimage(
        bytes calldata data,
        uint64 offset,
        uint256 flags
    ) external returns (bytes32 fullHash) {
        bool isFinal = (flags & (1 << 0)) != 0;
        if ((flags & (1 << 1)) != 0) {
            delete keccakStates[msg.sender];
        }
        require(isFinal || data.length % KECCAK_ROUND_INPUT == 0, "NOT_BLOCK_ALIGNED");
        KeccakState storage state = keccakStates[msg.sender];
        uint256 startLength = state.length;
        if (startLength == 0) {
            state.offset = offset;
        } else {
            require(state.offset == offset, "DIFF_OFFSET");
        }

        // Update the keccak state with the new data
        // (updates state.state and state.length)
        keccakUpdate(state, data, isFinal);

        // Obtain the `part`
        if (uint256(offset) + MAX_PART_LENGTH > startLength && offset < state.length) {
            uint256 startIdx = 0;
            if (offset > startLength) {
                startIdx = offset - startLength;
            }
            uint256 endIdx = uint256(offset) + MAX_PART_LENGTH - startLength;
            if (endIdx > data.length) {
                endIdx = data.length;
            }
            for (uint256 i = startIdx; i < endIdx; i++) {
                state.part.push(data[i]);
            }
        }

        // If this is not the final chunk, we can't yet determine the full hash, so we return early
        if (!isFinal) {
            return bytes32(0);
        }

        // Obtain the full hash from the keccak state
        // (the first 32 bytes)
        for (uint256 i = 0; i < 32; i++) {
            uint256 stateIdx = i / 8;
            // work around our weird keccakF function state ordering
            stateIdx = 5 * (stateIdx % 5) + stateIdx / 5;
            uint8 b = uint8(state.state[stateIdx] >> ((i % 8) * 8));
            fullHash |= bytes32(uint256(b) << (248 - (i * 8)));
        }
        preimageParts[fullHash][state.offset] = PreimagePart({proven: true, part: state.part});
        emit PreimagePartProven(fullHash, state.offset, state.part);
        delete keccakStates[msg.sender];
    }

    /**
     * @notice Absorbs data into the keccak sponge state, one 136-byte round at a time.
     *         On the final call, applies keccak padding.
     * @param state The in-progress keccak state to update (modified in place)
     * @param data The next chunk of preimage bytes to absorb
     * @param isFinal If true, pads and processes the final block
     */
    function keccakUpdate(KeccakState storage state, bytes calldata data, bool isFinal) internal {
        state.length += data.length;
        while (true) {
            if (data.length == 0 && !isFinal) {
                break;
            }

            // XOR in the next chunk of data, padding if necessary
            // (1 byte per iteration)
            for (uint256 i = 0; i < KECCAK_ROUND_INPUT; i++) {
                uint8 b = 0;
                if (i < data.length) {
                    b = uint8(data[i]);
                } else {
                    // Padding added in the final chunk or in a chunk on its own if the final chunk is exactly round-aligned
                    // 1st bit (LSB) is set if this is the first byte after the data
                    if (i == data.length) {
                        b |= uint8(0x01);
                    }
                    // Last bit (MSB) is always set in the final chunk
                    if (i == KECCAK_ROUND_INPUT - 1) {
                        b |= uint8(0x80);
                    }
                }
                uint256 stateIdx = i / 8;
                // work around our weird keccakF function state ordering
                stateIdx = 5 * (stateIdx % 5) + stateIdx / 5;
                state.state[stateIdx] ^= uint64(b) << uint64((i % 8) * 8);
            }
            uint256[25] memory state256;
            for (uint256 i = 0; i < 25; i++) {
                state256[i] = state.state[i];
            }

            // Scramble the state with keccakF
            state256 = CryptographyPrimitives.keccakF(state256);

            // Write the new state back to storage
            for (uint256 i = 0; i < 25; i++) {
                state.state[i] = uint64(state256[i]);
            }

            // Strict inequality, because if data is an exact multiple of the round size, keccak still adds a padding chunk
            if (data.length < KECCAK_ROUND_INPUT) {
                break;
            }
            data = data[KECCAK_ROUND_INPUT:];
        }
    }

    /// @notice Deletes the caller's in-progress split proof state
    function clearSplitProof() external {
        delete keccakStates[msg.sender];
    }

    /// @inheritdoc IHashProofHelper
    function getPreimagePart(
        bytes32 fullHash,
        uint64 offset
    ) external view returns (bytes memory) {
        PreimagePart storage part = preimageParts[fullHash][offset];
        if (!part.proven) {
            revert NotProven(fullHash, offset);
        }
        return part.part;
    }
}
