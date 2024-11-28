// Copyright 2023, Offchain Labs, Inc.
// For license information, see https://github.com/offchainlabs/bold/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1
//
pragma solidity ^0.8.17;

import "../rollup/Assertion.sol";
import "./libraries/UintUtilsLib.sol";
import "./IEdgeChallengeManager.sol";
import "./libraries/EdgeChallengeManagerLib.sol";
import "../libraries/Constants.sol";
import "../state/Machine.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title  A challenge manager that uses edge structures to decide between Assertions
/// @notice When two assertions are created that have the same predecessor the protocol needs to decide which of the two is correct
///         This challenge manager allows the staker who has created the valid assertion to enforce that it will be confirmed, and all
///         other rival assertions will be rejected. The challenge is all-vs-all in that all assertions with the same
///         predecessor will vie for succession against each other. Stakers compete by creating edges that reference the assertion they
///         believe in. These edges are then bisected, reducing the size of the disagreement with each bisection, and narrowing in on the
///         exact point of disagreement. Eventually, at step size 1, the step can be proved on-chain directly proving that the related assertion
///         must be invalid.
contract EdgeChallengeManager is IEdgeChallengeManager, Initializable {
    using EdgeChallengeManagerLib for EdgeStore;
    using ChallengeEdgeLib for ChallengeEdge;
    using SafeERC20 for IERC20;

    /// @notice A new edge has been added to the challenge manager
    /// @param edgeId       The id of the newly added edge
    /// @param mutualId     The mutual id of the added edge - all rivals share the same mutual id
    /// @param originId     The origin id of the added edge - origin ids link an edge to the level below
    /// @param hasRival     Does the newly added edge have a rival upon creation
    /// @param length       The length of the new edge
    /// @param level        The level of the new edge
    /// @param isLayerZero  Whether the new edge was added at layer zero - has a claim and a staker
    event EdgeAdded(
        bytes32 indexed edgeId,
        bytes32 indexed mutualId,
        bytes32 indexed originId,
        bytes32 claimId,
        uint256 length,
        uint8 level,
        bool hasRival,
        bool isLayerZero
    );

    /// @notice An edge has been bisected
    /// @param edgeId                   The id of the edge that was bisected
    /// @param lowerChildId             The id of the lower child created during bisection
    /// @param upperChildId             The id of the upper child created during bisection
    /// @param lowerChildAlreadyExists  When an edge is bisected the lower child may already exist - created by a rival.
    event EdgeBisected(
        bytes32 indexed edgeId,
        bytes32 indexed lowerChildId,
        bytes32 indexed upperChildId,
        bool lowerChildAlreadyExists
    );

    /// @notice An edge can be confirmed if the cumulative time (in blocks) unrivaled of it and a direct chain of ancestors is greater than a threshold
    /// @param edgeId               The edge that was confirmed
    /// @param mutualId             The mutual id of the confirmed edge
    /// @param totalTimeUnrivaled   The cumulative amount of time (in blocks) this edge spent unrivaled
    event EdgeConfirmedByTime(
        bytes32 indexed edgeId, bytes32 indexed mutualId, uint256 totalTimeUnrivaled
    );

    /// @notice A SmallStep edge of length 1 can be confirmed via a one step proof
    /// @param edgeId   The edge that was confirmed
    /// @param mutualId The mutual id of the confirmed edge
    event EdgeConfirmedByOneStepProof(bytes32 indexed edgeId, bytes32 indexed mutualId);

    /// @notice An edge's timer cache has been updated
    /// @param edgeId   The edge that was updated
    /// @param newValue The new value of its timer cache
    event TimerCacheUpdated(bytes32 indexed edgeId, uint256 newValue);

    /// @notice A stake has been refunded for a confirmed layer zero block edge
    /// @param edgeId       The edge that was confirmed
    /// @param mutualId     The mutual id of the confirmed edge
    /// @param stakeToken   The ERC20 being refunded
    /// @param stakeAmount  The amount of tokens being refunded
    event EdgeRefunded(
        bytes32 indexed edgeId, bytes32 indexed mutualId, address stakeToken, uint256 stakeAmount
    );

    /// @dev Store for all edges and rival data
    ///      All edges, including edges from different challenges, are stored together in the same store
    ///      Since edge ids include the origin id, which is unique for each challenge, we can be sure that
    ///      edges from different challenges cannot have the same id, and so can be stored in the same store
    EdgeStore internal store;

    /// @notice When creating a zero layer block edge a stake must be supplied. However since we know that only
    ///         one edge in a group of rivals can ever be confirmed, we only need to keep one stake in this contract
    ///         to later refund for that edge. Other stakes can immediately be sent to an excess stake receiver.
    ///         This excess stake receiver can then choose to refund the gas of participants who aided in the confirmation
    ///         of the winning edge
    address public excessStakeReceiver;

    /// @notice The token to supply stake in
    IERC20 public stakeToken;

    /// @notice The amount of stake token to be supplied when creating a zero layer block edge at a given level
    uint256[] public stakeAmounts;

    /// @notice The number of blocks accumulated on an edge before it can be confirmed by time
    uint64 public challengePeriodBlocks;

    /// @notice The assertion chain about which challenges are created
    IAssertionChain public assertionChain;

    /// @inheritdoc IEdgeChallengeManager
    IOneStepProofEntry public override oneStepProofEntry;

    /// @notice The end height of layer zero Block edges
    uint256 public LAYERZERO_BLOCKEDGE_HEIGHT;
    /// @notice The end height of layer zero BigStep edges
    uint256 public LAYERZERO_BIGSTEPEDGE_HEIGHT;
    /// @notice The end height of layer zero SmallStep edges
    uint256 public LAYERZERO_SMALLSTEPEDGE_HEIGHT;
    /// @notice The number of big step levels configured for this challenge manager
    ///         There is 1 block level, 1 small step level and N big step levels
    uint8 public NUM_BIGSTEP_LEVEL;

    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IEdgeChallengeManager
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
    ) public initializer {
        if (address(_assertionChain) == address(0)) {
            revert EmptyAssertionChain();
        }
        assertionChain = _assertionChain;
        if (address(_oneStepProofEntry) == address(0)) {
            revert EmptyOneStepProofEntry();
        }
        oneStepProofEntry = _oneStepProofEntry;
        if (_challengePeriodBlocks == 0) {
            revert EmptyChallengePeriod();
        }
        challengePeriodBlocks = _challengePeriodBlocks;

        stakeToken = _stakeToken;
        if (_excessStakeReceiver == address(0)) {
            revert EmptyStakeReceiver();
        }
        excessStakeReceiver = _excessStakeReceiver;

        if (!EdgeChallengeManagerLib.isPowerOfTwo(layerZeroBlockEdgeHeight)) {
            revert NotPowerOfTwo(layerZeroBlockEdgeHeight);
        }
        LAYERZERO_BLOCKEDGE_HEIGHT = layerZeroBlockEdgeHeight;
        if (!EdgeChallengeManagerLib.isPowerOfTwo(layerZeroBigStepEdgeHeight)) {
            revert NotPowerOfTwo(layerZeroBigStepEdgeHeight);
        }
        LAYERZERO_BIGSTEPEDGE_HEIGHT = layerZeroBigStepEdgeHeight;
        if (!EdgeChallengeManagerLib.isPowerOfTwo(layerZeroSmallStepEdgeHeight)) {
            revert NotPowerOfTwo(layerZeroSmallStepEdgeHeight);
        }
        LAYERZERO_SMALLSTEPEDGE_HEIGHT = layerZeroSmallStepEdgeHeight;

        // ensure that there is at least on of each type of level
        if (_numBigStepLevel == 0) {
            revert ZeroBigStepLevels();
        }
        // ensure there's also space for the block level and the small step level
        // in total level parameters
        if (_numBigStepLevel > 253) {
            revert BigStepLevelsTooMany(_numBigStepLevel);
        }
        NUM_BIGSTEP_LEVEL = _numBigStepLevel;

        if (_numBigStepLevel + 2 != _stakeAmounts.length) {
            revert StakeAmountsMismatch(_stakeAmounts.length, _numBigStepLevel + 2);
        }
        stakeAmounts = _stakeAmounts;
    }

    /////////////////////////////
    // STATE MUTATING SECTIION //
    /////////////////////////////

    /// @inheritdoc IEdgeChallengeManager
    function createLayerZeroEdge(
        CreateEdgeArgs calldata args
    ) external returns (bytes32) {
        // Check if whitelist is enabled in the Rollup
        // We only enforce whitelist in this function as it may exhaust resources
        bool whitelistEnabled = !assertionChain.validatorWhitelistDisabled();

        if (whitelistEnabled && !assertionChain.isValidator(msg.sender)) {
            revert NotValidator(msg.sender);
        }

        EdgeAddedData memory edgeAdded;
        EdgeType eType = ChallengeEdgeLib.levelToType(args.level, NUM_BIGSTEP_LEVEL);
        uint256 expectedEndHeight = getLayerZeroEndHeight(eType);
        AssertionReferenceData memory ard;

        if (eType == EdgeType.Block) {
            // for block type edges we need to provide some extra assertion data context
            if (args.proof.length == 0) {
                revert EmptyEdgeSpecificProof();
            }
            (
                ,
                AssertionStateData memory predecessorStateData,
                AssertionStateData memory claimStateData
            ) = abi.decode(args.proof, (bytes32[], AssertionStateData, AssertionStateData));

            assertionChain.validateAssertionHash(
                args.claimId,
                claimStateData.assertionState,
                claimStateData.prevAssertionHash,
                claimStateData.inboxAcc
            );

            assertionChain.validateAssertionHash(
                claimStateData.prevAssertionHash,
                predecessorStateData.assertionState,
                predecessorStateData.prevAssertionHash,
                predecessorStateData.inboxAcc
            );

            if (args.endHistoryRoot != claimStateData.assertionState.endHistoryRoot) {
                revert EndHistoryRootMismatch(
                    args.endHistoryRoot, claimStateData.assertionState.endHistoryRoot
                );
            }

            ard = AssertionReferenceData(
                args.claimId,
                claimStateData.prevAssertionHash,
                assertionChain.isPending(args.claimId),
                assertionChain.getSecondChildCreationBlock(claimStateData.prevAssertionHash) > 0,
                predecessorStateData.assertionState,
                claimStateData.assertionState
            );
        }
        edgeAdded = store.createLayerZeroEdge(
            args, ard, oneStepProofEntry, expectedEndHeight, NUM_BIGSTEP_LEVEL, whitelistEnabled
        );

        IERC20 st = stakeToken;
        uint256 sa = stakeAmounts[args.level];
        // when a zero layer edge is created it must include stake amount. Each time a zero layer
        // edge is created it forces the honest participants to do some work, so we want to disincentive
        // their creation. The amount should also be enough to pay for the gas costs incurred by the honest
        // participant. This can be arranged out of bound by the excess stake receiver.
        // The contract initializer can disable staking by setting zeros for token or amount, to change
        // this a new challenge manager needs to be deployed and its address updated in the assertion chain
        if (address(st) != address(0) && sa != 0) {
            // since only one edge in a group of rivals can ever be confirmed, we know that we
            // will never need to refund more than one edge. Therefore we can immediately send
            // all stakes provided after the first one to an excess stake receiver.
            address receiver = edgeAdded.hasRival ? excessStakeReceiver : address(this);
            st.safeTransferFrom(msg.sender, receiver, sa);
        }

        emit EdgeAdded(
            edgeAdded.edgeId,
            edgeAdded.mutualId,
            edgeAdded.originId,
            edgeAdded.claimId,
            edgeAdded.length,
            edgeAdded.level,
            edgeAdded.hasRival,
            edgeAdded.isLayerZero
        );
        return edgeAdded.edgeId;
    }

    /// @inheritdoc IEdgeChallengeManager
    function bisectEdge(
        bytes32 edgeId,
        bytes32 bisectionHistoryRoot,
        bytes calldata prefixProof
    ) external returns (bytes32, bytes32) {
        (
            bytes32 lowerChildId,
            EdgeAddedData memory lowerChildAdded,
            EdgeAddedData memory upperChildAdded
        ) = store.bisectEdge(edgeId, bisectionHistoryRoot, prefixProof);

        bool lowerChildAlreadyExists = lowerChildAdded.edgeId == 0;
        // the lower child might already exist, if it didnt then a new
        // edge was added
        if (!lowerChildAlreadyExists) {
            emit EdgeAdded(
                lowerChildAdded.edgeId,
                lowerChildAdded.mutualId,
                lowerChildAdded.originId,
                lowerChildAdded.claimId,
                lowerChildAdded.length,
                lowerChildAdded.level,
                lowerChildAdded.hasRival,
                lowerChildAdded.isLayerZero
            );
        }
        // upper child is always added
        emit EdgeAdded(
            upperChildAdded.edgeId,
            upperChildAdded.mutualId,
            upperChildAdded.originId,
            upperChildAdded.claimId,
            upperChildAdded.length,
            upperChildAdded.level,
            upperChildAdded.hasRival,
            upperChildAdded.isLayerZero
        );

        emit EdgeBisected(edgeId, lowerChildId, upperChildAdded.edgeId, lowerChildAlreadyExists);

        return (lowerChildId, upperChildAdded.edgeId);
    }

    /// @inheritdoc IEdgeChallengeManager
    function multiUpdateTimeCacheByChildren(
        bytes32[] calldata edgeIds,
        uint256 maximumCachedTime
    ) public {
        if (edgeIds.length == 0) revert EmptyArray();
        // revert early if the last edge already has sufficient time
        store.validateCurrentTimer(edgeIds[edgeIds.length - 1], maximumCachedTime);
        for (uint256 i = 0; i < edgeIds.length; i++) {
            updateTimerCacheByChildren(edgeIds[i], type(uint256).max);
        }
    }

    /// @inheritdoc IEdgeChallengeManager
    function updateTimerCacheByChildren(bytes32 edgeId, uint256 maximumCachedTime) public {
        (bool updated, uint256 newValue) =
            store.updateTimerCacheByChildren(edgeId, maximumCachedTime);
        if (updated) emit TimerCacheUpdated(edgeId, newValue);
    }

    /// @inheritdoc IEdgeChallengeManager
    function updateTimerCacheByClaim(
        bytes32 edgeId,
        bytes32 claimingEdgeId,
        uint256 maximumCachedTime
    ) public {
        (bool updated, uint256 newValue) = store.updateTimerCacheByClaim(
            edgeId, claimingEdgeId, NUM_BIGSTEP_LEVEL, maximumCachedTime
        );
        if (updated) emit TimerCacheUpdated(edgeId, newValue);
    }

    /// @inheritdoc IEdgeChallengeManager
    function confirmEdgeByTime(bytes32 edgeId, AssertionStateData calldata claimStateData) public {
        ChallengeEdge storage topEdge = store.get(edgeId);
        if (!topEdge.isLayerZero()) {
            revert EdgeNotLayerZero(topEdge.id(), topEdge.staker, topEdge.claimId);
        }

        uint64 assertionBlocks = 0;
        // if the edge is block level and the assertion being claimed against was the first child of its predecessor
        // then we are able to count the time between the first and second child as time towards
        // the this edge
        bool isBlockLevel =
            ChallengeEdgeLib.levelToType(topEdge.level, NUM_BIGSTEP_LEVEL) == EdgeType.Block;
        if (isBlockLevel && assertionChain.isFirstChild(topEdge.claimId)) {
            assertionChain.validateAssertionHash(
                topEdge.claimId,
                claimStateData.assertionState,
                claimStateData.prevAssertionHash,
                claimStateData.inboxAcc
            );
            assertionBlocks = assertionChain.getSecondChildCreationBlock(
                claimStateData.prevAssertionHash
            ) - assertionChain.getFirstChildCreationBlock(claimStateData.prevAssertionHash);
        }

        uint256 totalTimeUnrivaled =
            store.confirmEdgeByTime(edgeId, assertionBlocks, challengePeriodBlocks);

        emit EdgeConfirmedByTime(edgeId, store.edges[edgeId].mutualId(), totalTimeUnrivaled);
    }

    /// @inheritdoc IEdgeChallengeManager
    function confirmEdgeByOneStepProof(
        bytes32 edgeId,
        OneStepData calldata oneStepData,
        ConfigData calldata prevConfig,
        bytes32[] calldata beforeHistoryInclusionProof,
        bytes32[] calldata afterHistoryInclusionProof
    ) public {
        bytes32 prevAssertionHash = store.getPrevAssertionHash(edgeId);

        assertionChain.validateConfig(prevAssertionHash, prevConfig);

        ExecutionContext memory execCtx = ExecutionContext({
            maxInboxMessagesRead: prevConfig.nextInboxPosition,
            bridge: assertionChain.bridge(),
            initialWasmModuleRoot: prevConfig.wasmModuleRoot
        });

        store.confirmEdgeByOneStepProof(
            edgeId,
            oneStepProofEntry,
            oneStepData,
            execCtx,
            beforeHistoryInclusionProof,
            afterHistoryInclusionProof,
            NUM_BIGSTEP_LEVEL,
            LAYERZERO_BIGSTEPEDGE_HEIGHT,
            LAYERZERO_SMALLSTEPEDGE_HEIGHT
        );

        emit EdgeConfirmedByOneStepProof(edgeId, store.edges[edgeId].mutualId());
    }

    /// @inheritdoc IEdgeChallengeManager
    function refundStake(
        bytes32 edgeId
    ) public {
        ChallengeEdge storage edge = store.get(edgeId);
        // setting refunded also do checks that the edge cannot be refunded twice
        edge.setRefunded();

        IERC20 st = stakeToken;
        uint256 sa = stakeAmounts[edge.level];
        // no need to refund with the token or amount where zero'd out
        if (address(st) != address(0) && sa != 0) {
            st.safeTransfer(edge.staker, sa);
        }

        emit EdgeRefunded(edgeId, store.edges[edgeId].mutualId(), address(st), sa);
    }

    ///////////////////////
    // VIEW ONLY SECTION //
    ///////////////////////
    /// @inheritdoc IEdgeChallengeManager
    function getLayerZeroEndHeight(
        EdgeType eType
    ) public view returns (uint256) {
        if (eType == EdgeType.Block) {
            return LAYERZERO_BLOCKEDGE_HEIGHT;
        } else if (eType == EdgeType.BigStep) {
            return LAYERZERO_BIGSTEPEDGE_HEIGHT;
        } else if (eType == EdgeType.SmallStep) {
            return LAYERZERO_SMALLSTEPEDGE_HEIGHT;
        } else {
            revert InvalidEdgeType(eType);
        }
    }

    /// @inheritdoc IEdgeChallengeManager
    function calculateEdgeId(
        uint8 level,
        bytes32 originId,
        uint256 startHeight,
        bytes32 startHistoryRoot,
        uint256 endHeight,
        bytes32 endHistoryRoot
    ) public pure returns (bytes32) {
        return ChallengeEdgeLib.idComponent(
            level, originId, startHeight, startHistoryRoot, endHeight, endHistoryRoot
        );
    }

    /// @inheritdoc IEdgeChallengeManager
    function calculateMutualId(
        uint8 level,
        bytes32 originId,
        uint256 startHeight,
        bytes32 startHistoryRoot,
        uint256 endHeight
    ) public pure returns (bytes32) {
        return ChallengeEdgeLib.mutualIdComponent(
            level, originId, startHeight, startHistoryRoot, endHeight
        );
    }

    /// @inheritdoc IEdgeChallengeManager
    function edgeExists(
        bytes32 edgeId
    ) public view returns (bool) {
        return store.edges[edgeId].exists();
    }

    /// @inheritdoc IEdgeChallengeManager
    function getEdge(
        bytes32 edgeId
    ) public view returns (ChallengeEdge memory) {
        return store.get(edgeId);
    }

    /// @inheritdoc IEdgeChallengeManager
    function edgeLength(
        bytes32 edgeId
    ) public view returns (uint256) {
        return store.get(edgeId).length();
    }

    /// @inheritdoc IEdgeChallengeManager
    function hasRival(
        bytes32 edgeId
    ) public view returns (bool) {
        return store.hasRival(edgeId);
    }

    /// @inheritdoc IEdgeChallengeManager
    function confirmedRival(
        bytes32 mutualId
    ) public view returns (bytes32) {
        return store.confirmedRivals[mutualId];
    }

    /// @inheritdoc IEdgeChallengeManager
    function hasLengthOneRival(
        bytes32 edgeId
    ) public view returns (bool) {
        return store.hasLengthOneRival(edgeId);
    }

    /// @inheritdoc IEdgeChallengeManager
    function timeUnrivaled(
        bytes32 edgeId
    ) public view returns (uint256) {
        return store.timeUnrivaled(edgeId);
    }

    /// @inheritdoc IEdgeChallengeManager
    function getPrevAssertionHash(
        bytes32 edgeId
    ) public view returns (bytes32) {
        return store.getPrevAssertionHash(edgeId);
    }

    /// @inheritdoc IEdgeChallengeManager
    function firstRival(
        bytes32 mutualId
    ) public view returns (bytes32) {
        return store.firstRivals[mutualId];
    }

    /// @inheritdoc IEdgeChallengeManager
    function hasMadeLayerZeroRival(
        address account,
        bytes32 mutualId
    ) external view returns (bool) {
        return store.hasMadeLayerZeroRival[account][mutualId];
    }
}
