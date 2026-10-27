// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./IRollupCoreTransition.sol";

/// @notice Additional user entrypoints for assertions with pre-MEL parents.
interface IRollupUserTransition is IRollupCoreTransition {
    function confirmAssertion(
        bytes32 assertionHash,
        bytes32 prevAssertionHash,
        AssertionState calldata confirmState,
        bytes32 winningEdgeId,
        LegacyConfigData calldata prevConfig,
        bytes32 inboxAcc
    ) external;

    function stakeOnNewAssertion(
        LegacyAssertionInputs calldata assertion,
        bytes32 expectedAssertionHash
    ) external;

    function newStakeOnNewAssertion(
        uint256 tokenAmount,
        LegacyAssertionInputs calldata assertion,
        bytes32 expectedAssertionHash
    ) external;

    function newStakeOnNewAssertion(
        uint256 tokenAmount,
        LegacyAssertionInputs calldata assertion,
        bytes32 expectedAssertionHash,
        address withdrawalAddress
    ) external;

    function fastConfirmNewAssertion(
        LegacyAssertionInputs calldata assertion,
        bytes32 expectedAssertionHash
    ) external;
}
