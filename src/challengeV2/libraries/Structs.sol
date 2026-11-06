// Copyright 2023, Offchain Labs, Inc.
// For license information, see https://github.com/offchainlabs/bold/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1
//
pragma solidity ^0.8.0;

import "./Enums.sol";
import "../../rollup/AssertionState.sol";

/// @notice An execution state and proof to show that it's valid
struct AssertionStateData {
    /// @notice An execution state
    AssertionState assertionState;
    /// @notice assertion Hash of the prev assertion
    bytes32 prevAssertionHash;
    /// @notice Inbox accumulator of the assertion
    bytes32 inboxAcc;
}

/// @notice Data for creating a layer zero edge
struct CreateEdgeArgs {
    /// @notice The level of edge to be created. Challenges are decomposed into multiple levels.
    ///         The first (level 0) being of type Block, followed by n (set by NUM_BIGSTEP_LEVEL) levels of type BigStep, and finally
    ///         followed by a single level of type SmallStep. Each level is bisected until an edge
    ///         of length one is reached before proceeding to the next level. The first edge in each level (the layer zero edge)
    ///         makes a claim about an assertion or assertion in the lower level.
    ///         Finally in the last level, a SmallStep edge is added that claims a lower level length one BigStep edge, and these
    ///         SmallStep edges are bisected until they reach length one. A length one small step edge
    ///         can then be directly executed using a one-step proof.
    uint8 level;
    /// @notice The end history root of the edge to be created
    bytes32 endHistoryRoot;
    /// @notice The end height of the edge to be created.
    /// @dev    End height is deterministic for different levels but supplying it here gives the
    ///         caller a bit of extra security that they are supplying data for the correct level of edge
    uint256 endHeight;
    /// @notice The edge, or assertion, that is being claimed correct by the newly created edge.
    bytes32 claimId;
    /// @notice Proof that the start history root commits to a prefix of the states that
    ///         end history root commits to
    bytes prefixProof;
    /// @notice Edge type specific data
    ///         For Block type edges this is the abi encoding of:
    ///         bytes32[]: Inclusion proof - proof to show that the end state is the last state in the end history root
    ///         AssertionStateData: the before state of the edge
    ///         AssertionStateData: the after state of the edge
    ///         bytes32 predecessorId: id of the prev assertion
    ///         bytes32 inboxAcc:  the inbox accumulator of the assertion
    ///         For BigStep and SmallStep edges this is the abi encoding of:
    ///         bytes32: Start state - first state the edge commits to
    ///         bytes32: End state - last state the edge commits to
    ///         bytes32[]: Claim start inclusion proof - proof to show the start state is the first state in the claim edge
    ///         bytes32[]: Claim end inclusion proof - proof to show the end state is the last state in the claim edge
    ///         bytes32[]: Inclusion proof - proof to show that the end state is the last state in the end history root
    bytes proof;
}

/// @notice Data parsed raw proof data
struct ProofData {
    /// @notice The first state being committed to by an edge
    bytes32 startState;
    /// @notice The last state being committed to by an edge
    bytes32 endState;
    /// @notice A proof that the end state is included in the edge
    bytes32[] inclusionProof;
}

/// @notice Stores all edges and their rival status
struct EdgeStore {
    /// @notice A mapping of edge id to edges. Edges are never deleted, only created, and potentially confirmed.
    mapping(bytes32 => ChallengeEdge) edges;
    /// @notice A mapping of mutualId to edge id. Rivals share the same mutual id, and here we
    ///         store the edge id of the second edge that was created with the same mutual id - the first rival
    ///         When only one edge exists for a specific mutual id then a special magic string hash is stored instead
    ///         of the first rival id, to signify that a single edge does exist with this mutual id
    mapping(bytes32 => bytes32) firstRivals;
    /// @notice A mapping of mutualId to the edge id of the confirmed rival with that mutualId
    /// @dev    Each group of rivals (edges sharing mutual id) can only have at most one confirmed edge
    mapping(bytes32 => bytes32) confirmedRivals;
    /// @notice A mapping of account -> mutualId -> bool indicating if the account has created a layer zero edge with a mutual id
    mapping(address => mapping(bytes32 => bool)) hasMadeLayerZeroRival;
}

/// @notice Input data to a one step proof
struct OneStepData {
    /// @notice The hash of the state that's being executed from
    bytes32 beforeHash;
    /// @notice Proof data to accompany the execution context
    bytes proof;
}

/// @notice Data about a recently added edge
struct EdgeAddedData {
    bytes32 edgeId;
    bytes32 mutualId;
    bytes32 originId;
    bytes32 claimId;
    uint256 length;
    uint8 level;
    bool hasRival;
    bool isLayerZero;
}

/// @notice Data about an assertion that is being claimed by an edge
/// @dev    This extra information that is needed in order to verify that a block edge can be created
struct AssertionReferenceData {
    /// @notice The id of the assertion - will be used in a sanity check
    bytes32 assertionHash;
    /// @notice The predecessor of the assertion
    bytes32 predecessorId;
    /// @notice Is the assertion pending
    bool isPending;
    /// @notice Does the assertion have a sibling
    bool hasSibling;
    /// @notice The execution state of the predecessor assertion
    AssertionState startState;
    /// @notice The execution state of the assertion being claimed
    AssertionState endState;
}

/// @notice An edge committing to a range of states. These edges will be bisected, slowly
///         reducing them in length until they reach length one. At that point new edges of a different
///         level will be added that claim the result of this edge, or a one step proof will be calculated
///         if the edge level is already of type SmallStep.
struct ChallengeEdge {
    /// @notice The origin id is a link from the edge to an edge or assertion at a lower level.
    ///         Intuitively all edges with the same origin id agree on the information committed to in the origin id
    ///         For a SmallStep edge the origin id is the 'mutual' id of the length one BigStep edge being claimed by the zero layer ancestors of this edge
    ///         For a BigStep edge the origin id is the 'mutual' id of the length one Block edge being claimed by the zero layer ancestors of this edge
    ///         For a Block edge the origin id is the assertion hash of the assertion that is the root of the challenge - all edges in this challenge agree
    ///         that that assertion hash is valid.
    ///         The purpose of the origin id is to ensure that only edges that agree on a common start position
    ///         are being compared against one another.
    bytes32 originId;
    /// @notice A root of all the states in the history up to the startHeight
    bytes32 startHistoryRoot;
    /// @notice The height of the start history root
    uint256 startHeight;
    /// @notice A root of all the states in the history up to the endHeight. Since endHeight > startHeight, the startHistoryRoot must
    ///         commit to a prefix of the states committed to by the endHistoryRoot
    bytes32 endHistoryRoot;
    /// @notice The height of the end history root
    uint256 endHeight;
    /// @notice Edges can be bisected into two children. If this edge has been bisected the id of the
    ///         lower child is populated here, until that time this value is 0. The lower child has startHistoryRoot and startHeight
    ///         equal to this edge, but endHistoryRoot and endHeight equal to some prefix of the endHistoryRoot of this edge
    bytes32 lowerChildId;
    /// @notice Edges can be bisected into two children. If this edge has been bisected the id of the
    ///         upper child is populated here, until that time this value is 0. The upper child has startHistoryRoot and startHeight
    ///         equal to some prefix of the endHistoryRoot of this edge, and endHistoryRoot and endHeight equal to this edge
    bytes32 upperChildId;
    /// @notice The edge or assertion in the upper level that this edge claims to be true.
    ///         Only populated on zero layer edges
    bytes32 claimId;
    /// @notice The entity that supplied a mini-stake accompanying this edge
    ///         Only populated on zero layer edges
    address staker;
    /// @notice The block number when this edge was created
    uint64 createdAtBlock;
    /// @notice The block number at which this edge was confirmed
    ///         Zero if not confirmed
    uint64 confirmedAtBlock;
    /// @notice Current status of this edge. All edges are created Pending, and may be updated to Confirmed
    ///         Once Confirmed they cannot transition back to Pending
    EdgeStatus status;
    /// @notice The level of this edge.
    ///         Level 0 is type Block
    ///         Last level (defined by NUM_BIGSTEP_LEVEL + 1) is type SmallStep
    ///         All levels in between are of type BigStep
    uint8 level;
    /// @notice Set to true when the staker has been refunded. Can only be set to true if the status is Confirmed
    ///         and the staker is non zero.
    bool refunded;
    /// @notice TODO
    uint64 totalTimeUnrivaledCache;
}
