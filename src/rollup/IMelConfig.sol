// Copyright 2021-2026, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

/// @notice Per-rollup registry read by the replay binary through storage proofs at the
///         pinned parent chain block. Storage slots are consensus-critical: the layout is
///         append-only and must never gain inherited storage ahead of these fields.
///         Slot 0 : MEL version
///         Slot 1 : bridge address
interface IMelConfig {
    function initialize(
        uint256 _version,
        address _bridge
    ) external;
    function version() external view returns (uint256);
    function bridge() external view returns (address);
}
