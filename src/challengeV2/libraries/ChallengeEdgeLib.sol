// Copyright 2023, Offchain Labs, Inc.
// For license information, see https://github.com/offchainlabs/bold/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1
//
pragma solidity ^0.8.17;

import "./Enums.sol";
import "./ChallengeErrors.sol";
import "./Structs.sol";

library ChallengeEdgeLib {
    /// @notice Common checks to do when adding an edge
    function newEdgeChecks(
        bytes32 originId,
        bytes32 startHistoryRoot,
        uint256 startHeight,
        bytes32 endHistoryRoot,
        uint256 endHeight
    ) internal pure {
        if (originId == 0) {
            revert EmptyOriginId();
        }
        if (endHeight <= startHeight) {
            revert InvalidHeights(startHeight, endHeight);
        }
        if (startHistoryRoot == 0) {
            revert EmptyStartRoot();
        }
        if (endHistoryRoot == 0) {
            revert EmptyEndRoot();
        }
    }

    /// @notice Create a new layer zero edge. These edges make claims about length one edges in the level
    ///         below. Creating a layer zero edge also requires placing a mini stake, so information
    ///         about that staker is also stored on this edge.
    function newLayerZeroEdge(
        bytes32 originId,
        bytes32 startHistoryRoot,
        uint256 startHeight,
        bytes32 endHistoryRoot,
        uint256 endHeight,
        bytes32 claimId,
        address staker,
        uint8 level
    ) internal view returns (ChallengeEdge memory) {
        if (staker == address(0)) {
            revert EmptyStaker();
        }
        if (claimId == 0) {
            revert EmptyClaimId();
        }

        newEdgeChecks(originId, startHistoryRoot, startHeight, endHistoryRoot, endHeight);

        return ChallengeEdge({
            originId: originId,
            startHeight: startHeight,
            startHistoryRoot: startHistoryRoot,
            endHeight: endHeight,
            endHistoryRoot: endHistoryRoot,
            lowerChildId: 0,
            upperChildId: 0,
            createdAtBlock: uint64(block.number),
            claimId: claimId,
            staker: staker,
            status: EdgeStatus.Pending,
            level: level,
            refunded: false,
            confirmedAtBlock: 0,
            totalTimeUnrivaledCache: 0
        });
    }

    /// @notice Creates a new child edge. All edges except layer zero edges are child edges.
    ///         These are edges that are created by bisection, and have parents rather than claims.
    function newChildEdge(
        bytes32 originId,
        bytes32 startHistoryRoot,
        uint256 startHeight,
        bytes32 endHistoryRoot,
        uint256 endHeight,
        uint8 level
    ) internal view returns (ChallengeEdge memory) {
        newEdgeChecks(originId, startHistoryRoot, startHeight, endHistoryRoot, endHeight);

        return ChallengeEdge({
            originId: originId,
            startHeight: startHeight,
            startHistoryRoot: startHistoryRoot,
            endHeight: endHeight,
            endHistoryRoot: endHistoryRoot,
            lowerChildId: 0,
            upperChildId: 0,
            createdAtBlock: uint64(block.number),
            claimId: 0,
            staker: address(0),
            status: EdgeStatus.Pending,
            level: level,
            refunded: false,
            confirmedAtBlock: 0,
            totalTimeUnrivaledCache: 0
        });
    }

    /// @notice The "mutualId" of an edge. A mutual id is a hash of all the data that is shared by rivals.
    ///         Rivals have the same start height, start history root and end height. They also have the same origin id and level.
    ///         The difference between rivals is that they have a different endHistoryRoot, so that information
    ///         is not included in this hash.
    function mutualIdComponent(
        uint8 level,
        bytes32 originId,
        uint256 startHeight,
        bytes32 startHistoryRoot,
        uint256 endHeight
    ) internal pure returns (bytes32) {
        return
            keccak256(abi.encodePacked(level, originId, startHeight, startHistoryRoot, endHeight));
    }

    /// @notice The "mutualId" of an edge. A mutual id is a hash of all the data that is shared by rivals.
    ///         Rivals have the same start height, start history root and end height. They also have the same origin id and level.
    ///         The difference between rivals is that they have a different endHistoryRoot, so that information
    ///         is not included in this hash.
    function mutualId(
        ChallengeEdge storage ce
    ) internal view returns (bytes32) {
        return mutualIdComponent(
            ce.level, ce.originId, ce.startHeight, ce.startHistoryRoot, ce.endHeight
        );
    }

    function mutualIdMem(
        ChallengeEdge memory ce
    ) internal pure returns (bytes32) {
        return mutualIdComponent(
            ce.level, ce.originId, ce.startHeight, ce.startHistoryRoot, ce.endHeight
        );
    }

    /// @notice The id of an edge. Edges are uniquely identified by their id, and commit to the same information
    function idComponent(
        uint8 level,
        bytes32 originId,
        uint256 startHeight,
        bytes32 startHistoryRoot,
        uint256 endHeight,
        bytes32 endHistoryRoot
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                mutualIdComponent(level, originId, startHeight, startHistoryRoot, endHeight),
                endHistoryRoot
            )
        );
    }

    /// @notice The id of an edge. Edges are uniquely identified by their id, and commit to the same information
    /// @dev    This separate idMem method is to be explicit about when ChallengeEdges are copied into memory. It is
    ///         possible to pass a storage edge to this method and the id be computed correctly, but that would load
    ///         the whole struct into memory, so we're explicit here that this should be used for edges already in memory.
    function idMem(
        ChallengeEdge memory edge
    ) internal pure returns (bytes32) {
        return idComponent(
            edge.level,
            edge.originId,
            edge.startHeight,
            edge.startHistoryRoot,
            edge.endHeight,
            edge.endHistoryRoot
        );
    }

    /// @notice The id of an edge. Edges are uniquely identified by their id, and commit to the same information
    function id(
        ChallengeEdge storage edge
    ) internal view returns (bytes32) {
        return idComponent(
            edge.level,
            edge.originId,
            edge.startHeight,
            edge.startHistoryRoot,
            edge.endHeight,
            edge.endHistoryRoot
        );
    }

    /// @notice Does this edge exist in storage
    function exists(
        ChallengeEdge storage edge
    ) internal view returns (bool) {
        // All edges have a createdAtBlock number
        return edge.createdAtBlock != 0;
    }

    /// @notice The length of this edge - difference between the start and end heights
    function length(
        ChallengeEdge storage edge
    ) internal view returns (uint256) {
        uint256 len = edge.endHeight - edge.startHeight;
        // It's impossible for a zero length edge to exist
        if (len == 0) {
            revert EdgeNotExists(ChallengeEdgeLib.id(edge));
        }
        return len;
    }

    /// @notice Set the children of an edge
    /// @dev    Children can only be set once
    function setChildren(
        ChallengeEdge storage edge,
        bytes32 lowerChildId,
        bytes32 upperChildId
    ) internal {
        if (edge.lowerChildId != 0 || edge.upperChildId != 0) {
            revert ChildrenAlreadySet(
                ChallengeEdgeLib.id(edge), edge.lowerChildId, edge.upperChildId
            );
        }
        edge.lowerChildId = lowerChildId;
        edge.upperChildId = upperChildId;
    }

    /// @notice Set the status of an edge to Confirmed
    /// @dev    Only Pending edges can be confirmed
    function setConfirmed(
        ChallengeEdge storage edge
    ) internal {
        if (edge.status != EdgeStatus.Pending) {
            revert EdgeNotPending(ChallengeEdgeLib.id(edge), edge.status);
        }
        edge.status = EdgeStatus.Confirmed;
        edge.confirmedAtBlock = uint64(block.number);
    }

    /// @notice Is the edge a layer zero edge.
    function isLayerZero(
        ChallengeEdge storage edge
    ) internal view returns (bool) {
        return edge.claimId != 0 && edge.staker != address(0);
    }

    /// @notice Set the refunded flag of an edge
    /// @dev    Checks internally that edge is confirmed, layer zero edge and hasnt been refunded already
    function setRefunded(
        ChallengeEdge storage edge
    ) internal {
        if (edge.status != EdgeStatus.Confirmed) {
            revert EdgeNotConfirmed(ChallengeEdgeLib.id(edge), edge.status);
        }
        if (!isLayerZero(edge)) {
            revert EdgeNotLayerZero(ChallengeEdgeLib.id(edge), edge.staker, edge.claimId);
        }
        if (edge.refunded == true) {
            revert EdgeAlreadyRefunded(ChallengeEdgeLib.id(edge));
        }

        edge.refunded = true;
    }

    /// @notice Returns the edge type for a given level, given the total number of big step levels
    function levelToType(
        uint8 level,
        uint8 numBigStepLevels
    ) internal pure returns (EdgeType eType) {
        if (level == 0) {
            return EdgeType.Block;
        } else if (level <= numBigStepLevels) {
            return EdgeType.BigStep;
        } else if (level == numBigStepLevels + 1) {
            return EdgeType.SmallStep;
        } else {
            revert LevelTooHigh(level, numBigStepLevels);
        }
    }
}
