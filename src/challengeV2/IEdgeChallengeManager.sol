// Copyright 2023, Offchain Labs, Inc.
// For license information, see https://github.com/offchainlabs/bold/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1
//
pragma solidity ^0.8.0;

import "./IAssertionChain.sol";
import "./libraries/Structs.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title EdgeChallengeManager interface
interface IEdgeChallengeManager {
    /// @notice Initialize the EdgeChallengeManager. EdgeChallengeManagers are upgradeable
    ///         so use the initializer paradigm
    /// @param _assertionChain              The assertion chain contract
    /// @param _challengePeriodBlocks       The amount of cumulative time an edge must spend unrivaled before it can be confirmed
    ///                                     This should be the censorship period + the cumulative amount of time needed to do any
    ///                                     offchain calculation. We currently estimate around 10 mins for each layer zero edge and 1
    ///                                     one minute for each other edge.
    /// @param _oneStepProofEntry           The one step proof logic
    /// @param layerZeroBlockEdgeHeight     The end height of layer zero edges of type Block
    /// @param layerZeroBigStepEdgeHeight   The end height of layer zero edges of type BigStep
    /// @param layerZeroSmallStepEdgeHeight The end height of layer zero edges of type SmallStep
    /// @param _stakeToken                  The token that stake will be provided in when creating zero layer block edges
    /// @param _excessStakeReceiver         The address that excess stake will be sent to when 2nd+ block edge is created
    /// @param _numBigStepLevel             The number of bigstep levels
    /// @param _stakeAmounts                The stake amount for each level. (first element is for block level)
    function initialize(
        IAssertionChain _assertionChain,
        uint64 _challengePeriodBlocks,
        IOneStepProofEntry _oneStepProofEntry,
        uint256 layerZeroBlockEdgeHeight,
        uint256 layerZeroBigStepEdgeHeight,
        uint256 layerZeroSmallStepEdgeHeight,
        IERC20 _stakeToken,
        address _excessStakeReceiver,
        uint8 _numBigStepLevel,
        uint256[] calldata _stakeAmounts
    ) external;

    function stakeToken() external view returns (IERC20);

    function stakeAmounts(
        uint256
    ) external view returns (uint256);

    function challengePeriodBlocks() external view returns (uint64);

    /// @notice The one step proof resolver used to decide between rival SmallStep edges of length 1
    function oneStepProofEntry() external view returns (IOneStepProofEntry);

    /// @notice Performs necessary checks and creates a new layer zero edge
    /// @param args             Edge creation args
    function createLayerZeroEdge(
        CreateEdgeArgs calldata args
    ) external returns (bytes32);

    /// @notice Bisect an edge. This creates two child edges:
    ///         lowerChild: has the same start root and height as this edge, but a different end root and height
    ///         upperChild: has the same end root and height as this edge, but a different start root and height
    ///         The lower child end root and height are equal to the upper child start root and height. This height
    ///         is the mandatoryBisectionHeight.
    ///         The lower child may already exist, however it's not possible for the upper child to exist as that would
    ///         mean that the edge has already been bisected
    /// @param edgeId               Edge to bisect
    /// @param bisectionHistoryRoot The new history root to be used in the lower and upper children
    /// @param prefixProof          A proof to show that the bisectionHistoryRoot commits to a prefix of the current endHistoryRoot
    /// @return lowerChildId        The id of the newly created lower child edge
    /// @return upperChildId        The id of the newly created upper child edge
    function bisectEdge(
        bytes32 edgeId,
        bytes32 bisectionHistoryRoot,
        bytes calldata prefixProof
    ) external returns (bytes32, bytes32);

    /// @notice An edge can be confirmed if the total amount of time it and a single chain of its direct ancestors
    ///         has spent unrivaled is greater than the challenge period.
    /// @dev    Edges inherit time from their parents, so the sum of unrivaled timers is compared against the threshold.
    ///         Given that an edge cannot become unrivaled after becoming rivaled, once the threshold is passed
    ///         it will always remain passed. The direct ancestors of an edge are linked by parent-child links for edges
    ///         of the same level, and claimId-edgeId links for zero layer edges that claim an edge in the level below.
    ///         This method also includes the amount of time the assertion being claimed spent without a sibling
    /// @param edgeId                   The id of the edge to confirm
    function confirmEdgeByTime(
        bytes32 edgeId,
        AssertionStateData calldata claimStateData
    ) external;

    /// @notice Update multiple edges' timer cache by their children. Equivalent to calling updateTimerCacheByChildren for each edge.
    ///         May update timer cache above maximum if the last edge's timer cache was below maximumCachedTime.
    ///         Revert when the last edge's timer cache is already equal to or above maximumCachedTime.
    /// @param edgeIds           The ids of the edges to update
    /// @param maximumCachedTime The maximum amount of cached time allowed on the last edge (β∗)
    function multiUpdateTimeCacheByChildren(
        bytes32[] calldata edgeIds,
        uint256 maximumCachedTime
    ) external;

    /// @notice Update an edge's timer cache by its children.
    ///         Sets the edge's timer cache to its timeUnrivaled + (minimum timer cache of its children).
    ///         May update timer cache above maximum if the last edge's timer cache was below maximumCachedTime.
    ///         Revert when the edge's timer cache is already equal to or above maximumCachedTime.
    /// @param edgeId            The id of the edge to update
    /// @param maximumCachedTime The maximum amount of cached time allowed on the edge (β∗)
    function updateTimerCacheByChildren(bytes32 edgeId, uint256 maximumCachedTime) external;

    /// @notice Given a one step fork edge and an edge with matching claim id,
    ///         set the one step fork edge's timer cache to its timeUnrivaled + claiming edge's timer cache.
    ///         May update timer cache above maximum if the last edge's timer cache was below maximumCachedTime.
    ///         Revert when the edge's timer cache is already equal to or above maximumCachedTime.
    /// @param edgeId            The id of the edge to update
    /// @param claimingEdgeId    The id of the edge which has a claimId equal to edgeId
    /// @param maximumCachedTime The maximum amount of cached time allowed on the edge (β∗)
    function updateTimerCacheByClaim(
        bytes32 edgeId,
        bytes32 claimingEdgeId,
        uint256 maximumCachedTime
    ) external;

    /// @notice Confirm an edge by executing a one step proof
    /// @dev    One step proofs can only be executed against edges that have length one and of type SmallStep
    /// @param edgeId                       The id of the edge to confirm
    /// @param oneStepData                  Input data to the one step proof
    /// @param prevConfig                     Data about the config set in prev
    /// @param beforeHistoryInclusionProof  Proof that the state which is the start of the edge is committed to by the startHistoryRoot
    /// @param afterHistoryInclusionProof   Proof that the state which is the end of the edge is committed to by the endHistoryRoot
    function confirmEdgeByOneStepProof(
        bytes32 edgeId,
        OneStepData calldata oneStepData,
        ConfigData calldata prevConfig,
        bytes32[] calldata beforeHistoryInclusionProof,
        bytes32[] calldata afterHistoryInclusionProof
    ) external;

    /// @notice When zero layer block edges are created a stake is also provided
    ///         The stake on this edge can be refunded if the edge is confirme
    function refundStake(
        bytes32 edgeId
    ) external;

    /// @notice Zero layer edges have to be a fixed height.
    ///         This function returns the end height for a given edge type
    function getLayerZeroEndHeight(
        EdgeType eType
    ) external view returns (uint256);

    /// @notice Calculate the unique id of an edge
    /// @param level            The level of the edge
    /// @param originId         The origin id of the edge
    /// @param startHeight      The start height of the edge
    /// @param startHistoryRoot The start history root of the edge
    /// @param endHeight        The end height of the edge
    /// @param endHistoryRoot   The end history root of the edge
    function calculateEdgeId(
        uint8 level,
        bytes32 originId,
        uint256 startHeight,
        bytes32 startHistoryRoot,
        uint256 endHeight,
        bytes32 endHistoryRoot
    ) external pure returns (bytes32);

    /// @notice Calculate the mutual id of the edge
    ///         Edges that are rivals share the same mutual id
    /// @param level            The level of the edge
    /// @param originId         The origin id of the edge
    /// @param startHeight      The start height of the edge
    /// @param startHistoryRoot The start history root of the edge
    /// @param endHeight        The end height of the edge
    function calculateMutualId(
        uint8 level,
        bytes32 originId,
        uint256 startHeight,
        bytes32 startHistoryRoot,
        uint256 endHeight
    ) external pure returns (bytes32);

    /// @notice Has the edge already been stored in the manager
    function edgeExists(
        bytes32 edgeId
    ) external view returns (bool);

    /// @notice Get full edge data for an edge
    function getEdge(
        bytes32 edgeId
    ) external view returns (ChallengeEdge memory);

    /// @notice The length of the edge, from start height to end height
    function edgeLength(
        bytes32 edgeId
    ) external view returns (uint256);

    /// @notice Does this edge currently have one or more rivals
    ///         Rival edges share the same mutual id
    function hasRival(
        bytes32 edgeId
    ) external view returns (bool);

    /// @notice The confirmed rival of this mutual id
    ///         Returns 0 if one does not exist
    function confirmedRival(
        bytes32 mutualId
    ) external view returns (bytes32);

    /// @notice Does the edge have at least one rival, and it has length one
    function hasLengthOneRival(
        bytes32 edgeId
    ) external view returns (bool);

    /// @notice The amount of time this edge has spent without rivals
    ///         This value is increasing whilst an edge is unrivaled, once a rival is created
    ///         it is fixed. If an edge has rivals from the moment it is created then it will have
    ///         a zero time unrivaled
    function timeUnrivaled(
        bytes32 edgeId
    ) external view returns (uint256);

    /// @notice Get the id of the prev assertion that this edge is originates from
    /// @dev    Uses the parent chain to traverse upwards SmallStep->BigStep->Block->Assertion
    ///         until it gets to the origin assertion
    function getPrevAssertionHash(
        bytes32 edgeId
    ) external view returns (bytes32);

    /// @notice Fetch the raw first rival record for the given mutual id
    /// @dev    Returns 0 if there is no edge with the given mutual id
    ///         Returns a magic value if there is one edge but it is unrivaled
    ///         Returns the id of the second edge created with the mutual id, if > 1 exists
    function firstRival(
        bytes32 mutualId
    ) external view returns (bytes32);

    /// @notice True if an account has made a layer zero edge with the given mutual id.
    ///         This is only tracked when the validator whitelist is enabled
    function hasMadeLayerZeroRival(
        address account,
        bytes32 mutualId
    ) external view returns (bool);
}
