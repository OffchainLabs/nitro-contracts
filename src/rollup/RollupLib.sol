// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "../state/GlobalState.sol";
import "../bridge/ISequencerInbox.sol";

import "../bridge/IBridge.sol";
import "../bridge/IOutbox.sol";
import "../bridge/IInboxBase.sol";
import "./Assertion.sol";
import "./IRollupEventInbox.sol";
import "../challengeV2/IEdgeChallengeManager.sol";

library RollupLib {
    using GlobalStateLib for GlobalState;
    using AssertionStateLib for AssertionState;

    // The `assertionHash` contains all the information needed to determine an assertion's validity.
    // This helps protect validators against reorgs by letting them bind their assertion to the current chain state.
    // `afterState` includes a hash of the MELState up to which messages have been processed.
    function assertionHash(
        bytes32 parentAssertionHash,
        AssertionState memory afterState
    ) internal pure returns (bytes32) {
        // we can no longer have `hasSibling` in the assertion hash as it would allow identical assertions
        return assertionHash(parentAssertionHash, afterState.hash());
    }

    // Takes in a hash of the afterState instead of the afterState itself
    function assertionHash(
        bytes32 parentAssertionHash,
        bytes32 afterStateHash
    ) internal pure returns (bytes32) {
        // we can no longer have `hasSibling` in the assertion hash as it would allow identical assertions
        return keccak256(abi.encodePacked(parentAssertionHash, afterStateHash));
    }

    // All these should be emited in AssertionCreated event
    function configHash(
        bytes32 wasmModuleRoot,
        uint256 requiredStake,
        address challengeManager,
        uint64 confirmPeriodBlocks,
        bytes32 nextParentChainBlockHash
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                wasmModuleRoot,
                requiredStake,
                challengeManager,
                confirmPeriodBlocks,
                nextParentChainBlockHash
            )
        );
    }

    function validateConfigHash(
        ConfigData calldata configData,
        bytes32 _configHash
    ) internal pure {
        require(
            _configHash
                == configHash(
                    configData.wasmModuleRoot,
                    configData.requiredStake,
                    configData.challengeManager,
                    configData.confirmPeriodBlocks,
                    configData.nextParentChainBlockHash
                ),
            "CONFIG_HASH_MISMATCH"
        );
    }
}
