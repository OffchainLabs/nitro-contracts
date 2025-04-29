// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

interface IMinterBurnerForwarder {
    /**
     * @notice Mints some amount of the native gas token for this chain to the calling address.
     * @dev This function calls mintNativeToken in the ArbOwner precompile, so this contract must also be a chain owner.
     *      No events are emitted in this function, since the ArbOwner precompile already emits OwnerActs()
     * @param to The address credited with the minted native gas token
     * @param amount The amount of native gas token to mint
     */
    function mintNativeToken(address to, uint256 amount) external;

    /**
     * @notice Burns some amount of the native gas token for this chain from the given address.
     * @dev This function calls burnNativeToken in the ArbOwner precompile, so this contract must also be a chain owner.
     *      No events are emitted in this function, since the ArbOwner precompile already emits OwnerActs()
     * @param from The address to burn the native gas token from
     * @param amount The amount of native gas token to burn
     */
    function burnNativeToken(address from, uint256 amount) external;

    /// @notice The role given to the addresses that can mint native gas token
    function MINTER_ROLE() external returns (bytes32);

    /// @notice The role given to the addresses that can burn native gas token
    function BURNER_ROLE() external returns (bytes32);
}
