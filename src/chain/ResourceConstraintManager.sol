// Copyright 2022-2025, Offchain Labs, Inc.
// For license information, see https://github.com/nitro/blob/master/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "../precompiles/ArbOwner.sol";
import "../precompiles/ArbGasInfo.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract ResourceConstraintManager is AccessControlEnumerable {
    ArbOwner internal constant ARB_OWNER = ArbOwner(address(0x70));
    ArbGasInfo internal constant ARB_GAS_INFO = ArbGasInfo(address(0x6c));

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    error TooManyConstraints();
    error InvalidPeriod(uint64[3] constraint);
    error InvalidTarget(uint64[3] constraint);

    constructor(address admin, address executor) {
        _setupRole(DEFAULT_ADMIN_ROLE, admin);
        _setupRole(MANAGER_ROLE, admin);
        _setupRole(MANAGER_ROLE, executor);
    }

    /// @notice Sets the list of gas pricing constraints for the multi-constraint pricing model.
    ///         See ArbOwner.setGasPricingConstraints interface for more information.
    /// @param constraints Array of triples (gas_target_per_second, adjustment_window_seconds, starting_backlog_value)
    ///        - gas_target_per_second: target gas usage per second for the constraint (uint64, gas/sec)
    ///        - adjustment_window_seconds: time over which the price will rise by a factor of e if demand is 2x the target (uint64, seconds)
    ///        - starting_backlog_value: initial backlog for this constraint (uint64, gas units)
    function setGasPricingConstraints(
        uint64[3][] calldata constraints
    ) external onlyRole(MANAGER_ROLE) {
        // If zero constraints are provided, the chain uses the single-constraint pricing model
        if (constraints.length > 10) {
            revert TooManyConstraints();
        }
        uint256 nConstraints = constraints.length;
        for (uint256 i = 0; i < nConstraints; ++i) {
            uint64 gasTargetPerSec = constraints[i][0];
            uint64 adjustmentWindowSecs = constraints[i][1];
            if (gasTargetPerSec < 7_000_000 || gasTargetPerSec > 100_000_000) {
                revert InvalidTarget(constraints[i]);
            }
            if (adjustmentWindowSecs < 5 || adjustmentWindowSecs > 86400) {
                revert InvalidPeriod(constraints[i]);
            }
        }
        ARB_OWNER.setGasPricingConstraints(constraints);
    }
}
