// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "../RollupCore.sol";
import "./IRollupCoreTransition.sol";
import "./LegacyRollupLib.sol";

/// @notice Shared pre-MEL assertion support for the user and admin implementations.
/// @dev Adds no storage; all assertion updates use RollupCore.
abstract contract RollupCoreTransition is RollupCore, IRollupCoreTransition {
    using GlobalStateLib for GlobalState;

    // beforeState is pre-MEL
    // afterState is post-MEL
    function createNewAssertion(
        LegacyAssertionInputs calldata assertion,
        bytes32 prevAssertionHash,
        bytes32 expectedAssertionHash
    ) internal returns (bytes32 newAssertionHash, bool overflowAssertion) {
        // Validate the config hash
        LegacyRollupLib.validateConfigHash(
            assertion.beforeStateData.configData, getAssertionStorage(prevAssertionHash).configHash
        );

        // Legacy only checks
        int256 afterStateCmpMaxInbox =
            assertion.afterState.globalState
                .comparePositionsAgainstStartOfBatch(
                    assertion.beforeStateData.configData.nextInboxPosition
                );
        require(afterStateCmpMaxInbox <= 0, "INBOX_TOO_FAR");
        require(
            assertion.beforeStateData.configData.nextInboxPosition
                <= bridge.sequencerMessageCount(),
            "INBOX_NOT_POPULATED"
        );

        bytes32 sequencerBatchAcc;
        bytes32 targetParentChainBlockHash;
        (newAssertionHash, overflowAssertion, sequencerBatchAcc, targetParentChainBlockHash) =
            createAssertionInternal(
                assertion.beforeState,
                assertion.afterState,
                prevAssertionHash,
                assertion.beforeStateData.prevPrevAssertionHash,
                assertion.beforeStateData.sequencerBatchAcc,
                expectedAssertionHash
            );

        emit AssertionCreated(
            newAssertionHash,
            prevAssertionHash,
            assertion,
            sequencerBatchAcc,
            targetParentChainBlockHash,
            wasmModuleRoot,
            baseStake,
            address(challengeManager),
            confirmPeriodBlocks
        );

        return (newAssertionHash, overflowAssertion);
    }

    function validateConfig(
        bytes32 assertionHash,
        LegacyConfigData calldata configData
    ) external view {
        LegacyRollupLib.validateConfigHash(
            configData, getAssertionStorage(assertionHash).configHash
        );
    }
}
