// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/access/AccessControl.sol';
import '../precompiles/ArbOwner.sol';

/**
 * @title MinterBurnerForwarder
 * @notice  This contract allows the chain owner of a chain to give rights for minting and burning native gas tokens to third parties.
 *          Minting and burning will be done by using the ArbOwner functions mintNativeToken and burnNativeToken.
 *          This contract must be set as a chain owner of the chain to be able to call ArbOwner functions
 */
contract MinterBurnerForwarder is AccessControl {
    // Roles
    bytes32 public constant MINTER_ROLE = keccak256('MINTER');
    bytes32 public constant BURNER_ROLE = keccak256('BURNER');

    // ArbOwner precompile
    ArbOwner constant ARB_OWNER = ArbOwner(address(112));

    // Events
    event NativeTokenMinted(address indexed caller, uint256 amount);
    event NativeTokenBurned(address indexed caller, uint256 amount);

    // Errors
    error NotChainOwner();

    constructor() {
        // Check if the deployer is a chain owner
        if (!ARB_OWNER.isChainOwner(msg.sender)) {
            revert NotChainOwner();
        }

        // Grant admin role to the chain owner
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Mints some amount of the native gas token for this chain to the calling address.
     * @dev This function calls mintNativeToken in the ArbOwner precompile, so this contract must also be a chain owner.
     * @param amount The amount of native gas token to mint
     */
    function mintNativeToken(uint256 amount) external onlyRole(MINTER_ROLE) {
        ARB_OWNER.mintNativeToken(msg.sender, amount);
        emit NativeTokenMinted(msg.sender, amount);
    }

    /**
     * @notice Burns some amount of the native gas token for this chain from the given address.
     * @dev This function calls burnNativeToken in the ArbOwner precompile, so this contract must also be a chain owner.
     * @param amount The amount of native gas token to burn
     */
    function burnNativeToken(uint256 amount) external onlyRole(BURNER_ROLE) {
        ARB_OWNER.burnNativeToken(msg.sender, amount);
        emit NativeTokenBurned(msg.sender, amount);
    }
}
