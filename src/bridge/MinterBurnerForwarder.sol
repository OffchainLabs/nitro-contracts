// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/access/AccessControlEnumerable.sol';
import '../precompiles/ArbOwner.sol';

/**
 * @title MinterBurnerForwarder
 * @notice  This contract allows the chain owner of a chain to give rights for minting and burning native gas tokens to third parties.
 *          Minting and burning will be done by using the ArbOwner functions mintNativeToken and burnNativeToken.
 *          This contract must be set as a chain owner of the chain to be able to call ArbOwner functions
 */
contract MinterBurnerForwarder is AccessControlEnumerable {
    // Roles
    bytes32 public constant MINTER_ROLE = keccak256('MINTER');
    bytes32 public constant BURNER_ROLE = keccak256('BURNER');

    // ArbOwner precompile
    ArbOwner constant ARB_OWNER = ArbOwner(address(112));

    constructor(address[] memory admins, address[] memory minters, address[] memory burners) {
        // Grant ADMIN role to admins
        for (uint256 i = 0; i < admins.length; i++) {
            _grantRole(DEFAULT_ADMIN_ROLE, admins[i]);
        }
        
        // Grant MINTER role to minters
        for (uint256 i = 0; i < minters.length; i++) {
            _grantRole(MINTER_ROLE, minters[i]);
        }

        // Grant BURNER role to burners
        for (uint256 i = 0; i < burners.length; i++) {
            _grantRole(BURNER_ROLE, burners[i]);
        }
    }

    /**
     * @notice Mints some amount of the native gas token for this chain to the calling address.
     * @dev This function calls mintNativeToken in the ArbOwner precompile, so this contract must also be a chain owner.
     *      No events are emitted in this function, since the ArbOwner precompile already emits OwnerActs()
     * @param amount The amount of native gas token to mint
     */
    function mintNativeToken(uint256 amount) external onlyRole(MINTER_ROLE) {
        ARB_OWNER.mintNativeToken(msg.sender, amount);
    }

    /**
     * @notice Burns some amount of the native gas token for this chain from the given address.
     * @dev This function calls burnNativeToken in the ArbOwner precompile, so this contract must also be a chain owner.
     *      No events are emitted in this function, since the ArbOwner precompile already emits OwnerActs()
     * @param amount The amount of native gas token to burn
     */
    function burnNativeToken(uint256 amount) external onlyRole(BURNER_ROLE) {
        ARB_OWNER.burnNativeToken(msg.sender, amount);
    }
}
