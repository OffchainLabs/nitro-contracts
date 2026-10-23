// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./LegacyAssertion.sol";
import "./IAssertionChainTransition.sol";

/// @notice Additional rollup ABI used during the pre-MEL transition.
interface IRollupCoreTransition is IAssertionChainTransition {
    event AssertionCreated(
        bytes32 indexed assertionHash,
        bytes32 indexed parentAssertionHash,
        LegacyAssertionInputs assertion,
        bytes32 afterInboxBatchAcc,
        bytes32 targetParentChainBlockHash,
        bytes32 wasmModuleRoot,
        uint256 requiredStake,
        address challengeManager,
        uint64 confirmPeriodBlocks
    );
}
