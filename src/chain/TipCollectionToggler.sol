// Copyright 2022-2026, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro/blob/master/LICENSE.md
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "../precompiles/ArbOwner.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract TipCollectionToggler is AccessControlEnumerable {
    ArbOwner internal constant ARB_OWNER = ArbOwner(address(0x70));
    uint256 internal constant ACTIVATION_DURATION = 2 * 365 days; // 2 years

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    uint256 public expiryTimestamp;

    error NotExpired();
    error NotActivated();
    error AlreadyActivated();

    event Activated(uint256 expiryTimestamp);

    modifier onlyActivated() {
        if (expiryTimestamp == 0) {
            revert NotActivated();
        }
        _;
    }

    constructor(address admin, address manager) {
        _setupRole(DEFAULT_ADMIN_ROLE, admin);
        _setupRole(MANAGER_ROLE, manager);
    }

    /// @notice Activates the contract for a fixed duration, allowing tip collection to be toggled.
    function activate() external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (expiryTimestamp != 0) {
            revert AlreadyActivated();
        }
        expiryTimestamp = block.timestamp + ACTIVATION_DURATION;
        emit Activated(expiryTimestamp);
    }

    /// @notice Removes the contract from the list of chain owners after the expiry timestamp
    function revoke() external onlyActivated {
        if (block.timestamp < expiryTimestamp) {
            revert NotExpired();
        }
        ARB_OWNER.removeChainOwner(address(this));
    }

    /// @notice Enables or disables tip collection.
    /// @param collectTips If true, transaction tips are collected by the network fee account. If false (default), tips are dropped.
    function setCollectTips(
        bool collectTips
    ) external onlyRole(MANAGER_ROLE) onlyActivated {
        ARB_OWNER.setCollectTips(collectTips);
    }
}
