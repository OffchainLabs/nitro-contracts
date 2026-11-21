// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./LegacyAssertion.sol";

/// @notice Config-validation callback used by pre-MEL challenge managers.
interface IAssertionChainTransition {
    function validateConfig(
        bytes32 assertionHash,
        LegacyConfigData calldata configData
    ) external view;
}
