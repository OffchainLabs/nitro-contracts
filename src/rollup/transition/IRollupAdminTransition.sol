// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./LegacyAssertion.sol";

/// @notice Additional admin entrypoints for assertions with pre-MEL parents.
interface IRollupAdminTransition {
    function forceCreateAssertion(
        bytes32 prevAssertionHash,
        LegacyAssertionInputs calldata assertion,
        bytes32 expectedAssertionHash
    ) external;
}
