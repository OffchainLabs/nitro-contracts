// Copyright 2022-2025, Offchain Labs, Inc.
// For license information, see https://github.com/nitro/blob/master/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "../precompiles/ArbOwner.sol";
import "../precompiles/ArbGasInfo.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract PricingManager is AccessControlEnumerable {
    ArbOwner internal constant ARB_OWNER = ArbOwner(address(0x70));
    ArbGasInfo internal constant ARB_GAS_INFO = ArbGasInfo(address(0x6c));

    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    constructor(address admin, address executor) {
        _setupRole(DEFAULT_ADMIN_ROLE, admin);
        _setupRole(EXECUTOR_ROLE, admin);
        _setupRole(EXECUTOR_ROLE, executor);
    }

    /// @notice Adds or updates a resource constraint
    /// @param resources an array of resource–weight pairs (see Nitro documentation for the list of resources)
    /// @param periodSecs the time window for the constraint
    /// @param targetPerSec allowed usage per second across weighted resources
    function setResourceConstraint(
        ArbResourceConstraintsTypes.ResourceWeight[] calldata resources,
        uint32 periodSecs,
        uint64 targetPerSec
    ) external onlyRole(EXECUTOR_ROLE) {
        // TODO: restrict input
        ARB_OWNER.setResourceConstraint(resources, periodSecs, targetPerSec);
    }

    /// @notice Removes a resource constraint
    /// @param resources the list of resource kinds to be removed (see Nitro documentation for the list of resources)
    /// @param periodSecs the time window for the constraint
    function clearConstraint(
        ArbResourceConstraintsTypes.ResourceKind[] calldata resources,
        uint32 periodSecs
    ) external onlyRole(EXECUTOR_ROLE) {
        // TODO: restrict input
        ARB_OWNER.clearConstraint(resources, periodSecs);
    }
}
