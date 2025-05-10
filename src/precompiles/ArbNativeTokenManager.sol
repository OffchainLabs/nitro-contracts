// Copyright 2021-2025, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE.md
// SPDX-License-Identifier: BUSL-1.1

pragma solidity >=0.4.21 <0.9.0;

/**
 * @title Enables minting and burning native tokens.
 * @notice Authorized callers are added/removed through ArbOwner precompile.
 * Available in ArbOS version 41
 */
interface ArbNativeTokenManager {
    /**
     * @notice In case the caller is authorized,
     * mints some amount of the native gas token for this chain to the caller.
     */
    function mintNativeToken(
        uint256 amount
    ) external;

    /**
     * @notice In case the caller is authorized,
     * burns some amount of the native gas token for this chain from the caller.
     */
    function burnNativeToken(
        uint256 amount
    ) external;
}
