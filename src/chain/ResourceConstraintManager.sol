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

    // Constraint parameters boundaries
    uint256 public constant MAX_CONSTRAINTS = 10;
    uint64 public constant MIN_GAS_TARGET_PER_SEC = 7_000_000;
    uint64 public constant MAX_GAS_TARGET_PER_SEC = 100_000_000;
    uint32 public constant MIN_ADJUSTMENT_WINDOW_SECS = 5;
    uint32 public constant MAX_ADJUSTMENT_WINDOW_SECS = 86400;
    uint64 public constant MAX_PRICING_EXPONENT = 8000; // scaled by 1000 to allow for fractional exponents

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    uint256 public expiryTimestamp;

    error TooManyConstraints();
    error InvalidPeriod(
        uint64 gasTargetPerSec, uint64 adjustmentWindowSecs, uint64 startingBacklogValue
    );
    error InvalidTarget(
        uint64 gasTargetPerSec, uint64 adjustmentWindowSecs, uint64 startingBacklogValue
    );
    error PricingExponentTooHigh(uint64 pricingExponent);
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
        uint256 nConstraints = constraints.length;
        if (nConstraints > 10) {
            revert TooManyConstraints();
        }
        uint64 pricingExponent = 0;
        for (uint256 i = 0; i < nConstraints; ++i) {
            uint64 gasTargetPerSec = constraints[i][0];
            uint64 adjustmentWindowSecs = constraints[i][1];
            uint64 startingBacklogValue = constraints[i][2];
            if (gasTargetPerSec < 7_000_000 || gasTargetPerSec > 100_000_000) {
                revert InvalidTarget(gasTargetPerSec, adjustmentWindowSecs, startingBacklogValue);
            }
            if (adjustmentWindowSecs < 5 || adjustmentWindowSecs > 86400) {
                revert InvalidPeriod(gasTargetPerSec, adjustmentWindowSecs, startingBacklogValue);
            }
            // we scale by 1000 to improve precision in calculating the exponent
            // since this division will round down, it's always possible for the real exponent to be up to
            // the number of constraints greater than the value we measure
            // for instance
            // if n = 10, and we check with precision 1 against threshold 8, then the real exponent might actually be up to 18
            // if n = 10, and we check with precision 1000 against threshold 8000, then the real exponent might actually be up to 8010 / 1000
            pricingExponent +=
                (startingBacklogValue * 1000) / (gasTargetPerSec * adjustmentWindowSecs);
        }

        // this calculated pricing exponent will by used by nitro to calculate the gas price
        // we check that the pricing exponent is below some reasonable number to avoid setting the gas price astronomically high
        // as long as the gas price is not so high that no-one at all can send a transaction the chain will be able to function
        // eg. these constraints can be changed again, or the sec council can send admin transactions
        // with min base fee of 0.02, exponent of 8 (scaled by 1000) corresponds to a gas price of ~60 Gwei
        if (pricingExponent > 8000) {
            revert PricingExponentTooHigh(pricingExponent);
        }

        ARB_OWNER.setGasPricingConstraints(constraints);
    }

    /// @notice Sets the list of multi-gas pricing constraints for the multi-dimensional multi-constraint pricing model.
    ///         See ArbOwner.setMultiGasPricingConstraints interface for more information.
    /// @param constraints Array of ResourceConstraint structs, each containing:
    ///        - resources: list of (ResourceKind, weight) pairs
    ///        - adjustmentWindowSecs: time window (seconds) over which the price will rise by a factor of e if demand is 2x the target (uint32, seconds)
    ///        - targetPerSec: target gas usage per second for this constraint (uint64, gas/sec)
    ///        - backlog: initial backlog value for this constraint (uint64, gas units)
    function setMultiGasPricingConstraints(
        ArbMultiGasConstraintsTypes.ResourceConstraint[] calldata constraints
    ) external onlyRole(MANAGER_ROLE) {
        // If zero constraints are provided, the chain uses the single-constraint pricing model
        // Starting from ArbOS 60, there's no limit to the number of constraints to set
        uint256 nConstraints = constraints.length;

        // We calculate the implied pricing exponent for each resource kind
        uint8 numResourceKinds = uint8(type(ArbMultiGasConstraintsTypes.ResourceKind).max) + 1;
        uint64[] memory pricingExponents = new uint64[](numResourceKinds);
        for (uint256 i = 0; i < nConstraints; ++i) {
            uint64 targetPerSec = constraints[i].targetPerSec;
            uint32 adjustmentWindowSecs = constraints[i].adjustmentWindowSecs;
            uint64 startingBacklogValue = constraints[i].backlog;
            if (targetPerSec < MIN_GAS_TARGET_PER_SEC || targetPerSec > MAX_GAS_TARGET_PER_SEC) {
                revert InvalidTarget(targetPerSec, adjustmentWindowSecs, startingBacklogValue);
            }
            if (adjustmentWindowSecs < MIN_ADJUSTMENT_WINDOW_SECS || adjustmentWindowSecs > MAX_ADJUSTMENT_WINDOW_SECS) {
                revert InvalidPeriod(targetPerSec, adjustmentWindowSecs, startingBacklogValue);
            }
            if (startingBacklogValue > 0) {
                // Find the maximum weight among all resources in this constraint
                uint64 maxWeight = 0;
                uint256 nResources = constraints[i].resources.length;
                for (uint256 j = 0; j < nResources; ++j) {
                    uint64 weight = constraints[i].resources[j].weight;
                    if (weight > maxWeight) {
                        maxWeight = weight;
                    }
                }

                if (maxWeight > 0) {
                    // Neither of these values can be zero due to the earlier checks, so this division is safe
                    uint256 divisor = uint256(adjustmentWindowSecs) * uint256(targetPerSec) * uint256(maxWeight);

                    // Calculate per-resource-kind exponent contribution
                    // we scale by 1000 to improve precision in calculating the exponent
                    // since this division will round down, it's always possible for the real exponent to be up to
                    // the number of constraints greater than the value we measure
                    // Operation is performed in uint256 to avoid overflow, but the result is guaranteed to fit in uint64 due to the earlier check
                    for (uint256 j = 0; j < nResources; ++j) {
                        uint8 kind = uint8(constraints[i].resources[j].resource);
                        uint64 weight = constraints[i].resources[j].weight;
                        pricingExponents[kind] += uint64(uint256(startingBacklogValue) * uint256(weight) * 1000 / divisor);
                    }
                }
            }
        }

        // this calculated pricing exponent will by used by nitro to calculate the gas price
        // we check that the pricing exponent is below some reasonable number to avoid setting the gas price astronomically high
        // as long as the gas price is not so high that no-one at all can send a transaction the chain will be able to function
        // eg. these constraints can be changed again, or the sec council can send admin transactions
        // with min base fee of 0.02, exponent of 8 (scaled by 1000) corresponds to a gas price of ~60 Gwei
        for (uint8 k = 0; k < numResourceKinds; ++k) {
            if (pricingExponents[k] > MAX_PRICING_EXPONENT) {
                revert PricingExponentTooHigh(pricingExponents[k]);
            }
        }

        ARB_OWNER.setMultiGasPricingConstraints(constraints);
    }
}
