// Copyright 2022-2026, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro/blob/master/LICENSE.md
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "../precompiles/ArbOwner.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract TipCollectionToggler is AccessControlEnumerable {
    ArbOwner internal constant ARB_OWNER = ArbOwner(address(0x70));

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    uint256 public immutable expiryTimestamp;

    error NotExpired();

    constructor(address admin, address manager, uint256 _expiryTimestamp) {
        _setupRole(DEFAULT_ADMIN_ROLE, admin);
        _setupRole(MANAGER_ROLE, manager);
        expiryTimestamp = _expiryTimestamp;
    }

    /// @notice Removes the contract from the list of chain owners after the expiry timestamp
    function revoke() external {
        if (block.timestamp < expiryTimestamp) {
            revert NotExpired();
        }
        ARB_OWNER.removeChainOwner(address(this));
    }

    /// @notice Enables or disables tip collection.
    /// @param collectTips If true, transaction tips are collected by the network fee account. If false (default), tips are dropped.
    function setCollectTips(
        bool collectTips
    ) external onlyRole(MANAGER_ROLE) {
        ARB_OWNER.setCollectTips(collectTips);
    }
}
