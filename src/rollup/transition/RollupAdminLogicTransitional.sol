// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "../RollupAdminLogic.sol";
import "./RollupCoreTransition.sol";
import "./IRollupAdminTransition.sol";

/// @notice Admin implementation supporting assertion creation from pre-MEL parents.
/// @dev Access remains restricted by the rollup proxy admin routing. Adds no storage.
contract RollupAdminLogicTransitional is
    RollupAdminLogic,
    RollupCoreTransition,
    IRollupAdminTransition
{
    function forceCreateAssertion(
        bytes32 prevAssertionHash,
        LegacyAssertionInputs calldata assertion,
        bytes32 expectedAssertionHash
    ) external override whenPaused {
        // To update the wasm module root in the case of a bug:
        // 0. pause the contract
        // 1. update the wasm module root in the contract
        // 2. update the config hash of the assertion after which you wish to use the new wasm module root (functionality not written yet)
        // 3. force refund the stake of the current leaf assertion(s)
        // 4. create a new assertion using the assertion with the updated config has as a prev
        // 5. force confirm it - this is necessary to set latestConfirmed on the correct line
        // 6. unpause the contract
        createNewAssertion(assertion, prevAssertionHash, expectedAssertionHash);

        emit AssertionForceCreated(expectedAssertionHash);
        // previously: emit OwnerFunctionCalled(23);
    }
}
