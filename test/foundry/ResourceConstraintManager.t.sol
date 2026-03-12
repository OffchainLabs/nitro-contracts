// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "../../src/chain/ResourceConstraintManager.sol";

contract ResourceConstraintManagerTest is Test {
    ResourceConstraintManager public resourceConstraintManager;
    ArbOwnerMock internal constant ARB_OWNER = ArbOwnerMock(address(0x70));

    address constant admin = address(1337);
    address constant manager = address(7331);
    uint256 constant expiryTimestamp = 12345678;

    constructor() {
        resourceConstraintManager = new ResourceConstraintManager(admin, manager, expiryTimestamp);
        vm.etch(address(ARB_OWNER), type(ArbOwnerMock).runtimeCode);
    }

    function test_revoke() external {
        // Test before expiry
        vm.warp(expiryTimestamp - 1);
        vm.expectRevert(ResourceConstraintManager.NotExpired.selector);
        resourceConstraintManager.revoke();

        // Test after expiry
        vm.warp(expiryTimestamp);
        assertFalse(ARB_OWNER.removeChainOwnerCalled());
        resourceConstraintManager.revoke();
        assertTrue(ARB_OWNER.removeChainOwnerCalled());
    }

    //
    // --- setGasPricingConstraints tests ---
    //
    function test_setGasPricingConstraints_success() external {
        // Test with valid single constraint
        uint64[3][] memory constraints = new uint64[3][](1);
        constraints[0] = [uint64(10_000_000), uint64(100), uint64(0)];

        vm.prank(manager);
        resourceConstraintManager.setGasPricingConstraints(constraints);

        // Test with multiple valid constraints
        uint64[3][] memory multipleConstraints = new uint64[3][](3);
        multipleConstraints[0] = [uint64(7_000_000), uint64(5), uint64(0)];
        multipleConstraints[1] = [uint64(50_000_000), uint64(1000), uint64(1)];
        multipleConstraints[2] = [uint64(100_000_000), uint64(86400), uint64(10000)];

        vm.prank(manager);
        resourceConstraintManager.setGasPricingConstraints(multipleConstraints);

        // Test with empty constraints array (switch to single-constraint model)
        uint64[3][] memory emptyConstraints = new uint64[3][](0);
        vm.prank(manager);
        resourceConstraintManager.setGasPricingConstraints(emptyConstraints);
    }

    function test_setGasPricingConstraints_pricingExponentTooHigh() external {
        // create constraints on the limit of the pricing exponent
        uint64[3][] memory multipleConstraints = new uint64[3][](3);
        multipleConstraints[0] = [uint64(7_000_000), uint64(5), uint64(35_000_000)]; // 1
        multipleConstraints[1] = [uint64(50_000_000), uint64(1000), uint64(300_000_000_000)]; // 6
        multipleConstraints[2] = [uint64(100_000_000), uint64(86400), uint64(8_640_000_000_000)]; // 1

        vm.prank(manager);
        resourceConstraintManager.setGasPricingConstraints(multipleConstraints);

        // up to the limit
        multipleConstraints[1][2] = uint64(300_049_999_999);
        vm.prank(manager);
        resourceConstraintManager.setGasPricingConstraints(multipleConstraints);

        // over the limit
        multipleConstraints[1][2] = uint64(300_050_000_000);
        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(ResourceConstraintManager.PricingExponentTooHigh.selector, 8001)
        );
        resourceConstraintManager.setGasPricingConstraints(multipleConstraints);
    }

    function test_setGasPricingConstraints_accessControl() external {
        uint64[3][] memory constraints = new uint64[3][](1);
        constraints[0] = [uint64(10_000_000), uint64(100), uint64(0)];

        // Test non-manager cannot call
        vm.expectRevert();
        resourceConstraintManager.setGasPricingConstraints(constraints);

        // Test admin without manager role cannot call
        vm.prank(admin);
        vm.expectRevert();
        resourceConstraintManager.setGasPricingConstraints(constraints);

        // Test manager can call
        vm.prank(manager);
        resourceConstraintManager.setGasPricingConstraints(constraints);
    }

    function test_setGasPricingConstraints_tooManyConstraints() external {
        // Test exactly 10 constraints (should succeed)
        uint64[3][] memory tenConstraints = new uint64[3][](10);
        for (uint256 i = 0; i < 10; i++) {
            tenConstraints[i] = [uint64(10_000_000), uint64(100), uint64(0)];
        }
        vm.prank(manager);
        resourceConstraintManager.setGasPricingConstraints(tenConstraints);

        // Test 11 constraints (should revert)
        uint64[3][] memory elevenConstraints = new uint64[3][](11);
        for (uint256 i = 0; i < 11; i++) {
            elevenConstraints[i] = [uint64(10_000_000), uint64(100), uint64(0)];
        }
        vm.prank(manager);
        vm.expectRevert(ResourceConstraintManager.TooManyConstraints.selector);
        resourceConstraintManager.setGasPricingConstraints(elevenConstraints);
    }

    function test_setGasPricingConstraints_invalidTarget() external {
        // Test gas target below minimum (6,999,999)
        uint64[3][] memory constraintsLowTarget = new uint64[3][](1);
        constraintsLowTarget[0] = [uint64(6_999_999), uint64(100), uint64(0)];

        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(
                ResourceConstraintManager.InvalidTarget.selector,
                uint64(6_999_999),
                uint64(100),
                uint64(0)
            )
        );
        resourceConstraintManager.setGasPricingConstraints(constraintsLowTarget);

        // Test gas target above maximum (100,000,001)
        uint64[3][] memory constraintsHighTarget = new uint64[3][](1);
        constraintsHighTarget[0] = [uint64(100_000_001), uint64(100), uint64(0)];

        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(
                ResourceConstraintManager.InvalidTarget.selector,
                uint64(100_000_001),
                uint64(100),
                uint64(0)
            )
        );
        resourceConstraintManager.setGasPricingConstraints(constraintsHighTarget);

        // Test edge cases (exactly at boundaries should succeed)
        uint64[3][] memory constraintsMinTarget = new uint64[3][](1);
        constraintsMinTarget[0] = [uint64(7_000_000), uint64(100), uint64(0)];
        vm.prank(manager);
        resourceConstraintManager.setGasPricingConstraints(constraintsMinTarget);

        uint64[3][] memory constraintsMaxTarget = new uint64[3][](1);
        constraintsMaxTarget[0] = [uint64(100_000_000), uint64(100), uint64(0)];
        vm.prank(manager);
        resourceConstraintManager.setGasPricingConstraints(constraintsMaxTarget);
    }

    function test_setGasPricingConstraints_invalidPeriod() external {
        // Test adjustment window below minimum (4 seconds)
        uint64[3][] memory constraintsLowPeriod = new uint64[3][](1);
        constraintsLowPeriod[0] = [uint64(10_000_000), uint64(4), uint64(0)];

        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(
                ResourceConstraintManager.InvalidPeriod.selector,
                uint64(10_000_000),
                uint64(4),
                uint64(0)
            )
        );
        resourceConstraintManager.setGasPricingConstraints(constraintsLowPeriod);

        // Test adjustment window above maximum (86401 seconds)
        uint64[3][] memory constraintsHighPeriod = new uint64[3][](1);
        constraintsHighPeriod[0] = [uint64(10_000_000), uint64(86401), uint64(0)];

        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(
                ResourceConstraintManager.InvalidPeriod.selector,
                uint64(10_000_000),
                uint64(86401),
                uint64(0)
            )
        );
        resourceConstraintManager.setGasPricingConstraints(constraintsHighPeriod);

        // Test edge cases (exactly at boundaries should succeed)
        uint64[3][] memory constraintsMinPeriod = new uint64[3][](1);
        constraintsMinPeriod[0] = [uint64(10_000_000), uint64(5), uint64(0)];
        vm.prank(manager);
        resourceConstraintManager.setGasPricingConstraints(constraintsMinPeriod);

        uint64[3][] memory constraintsMaxPeriod = new uint64[3][](1);
        constraintsMaxPeriod[0] = [uint64(10_000_000), uint64(86400), uint64(0)];
        vm.prank(manager);
        resourceConstraintManager.setGasPricingConstraints(constraintsMaxPeriod);
    }

    function test_setGasPricingConstraints_multipleConstraintValidation() external {
        // Test that all constraints are validated (not just the first one)
        uint64[3][] memory constraints = new uint64[3][](3);
        constraints[0] = [uint64(10_000_000), uint64(100), uint64(0)]; // Valid
        constraints[1] = [uint64(20_000_000), uint64(200), uint64(0)]; // Valid
        constraints[2] = [uint64(5_000_000), uint64(100), uint64(0)]; // Invalid target

        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(
                ResourceConstraintManager.InvalidTarget.selector,
                uint64(5_000_000),
                uint64(100),
                uint64(0)
            )
        );
        resourceConstraintManager.setGasPricingConstraints(constraints);

        // Test with invalid period in middle
        constraints[0] = [uint64(10_000_000), uint64(100), uint64(0)]; // Valid
        constraints[1] = [uint64(20_000_000), uint64(3), uint64(0)]; // Invalid period
        constraints[2] = [uint64(30_000_000), uint64(100), uint64(0)]; // Valid

        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(
                ResourceConstraintManager.InvalidPeriod.selector,
                uint64(20_000_000),
                uint64(3),
                uint64(0)
            )
        );
        resourceConstraintManager.setGasPricingConstraints(constraints);
    }

    //
    // --- setMultiGasPricingConstraints tests ---
    //
    function _createMultiGasConstraintWithResources(
        uint64 targetPerSec,
        uint32 adjustmentWindowSecs,
        uint64 backlog,
        ArbMultiGasConstraintsTypes.WeightedResource[] memory resources
    ) internal pure returns (ArbMultiGasConstraintsTypes.ResourceConstraint memory) {
        return ArbMultiGasConstraintsTypes.ResourceConstraint({
            resources: resources,
            adjustmentWindowSecs: adjustmentWindowSecs,
            targetPerSec: targetPerSec,
            backlog: backlog
        });
    }

    function _createMultiGasConstraint(
        uint64 targetPerSec,
        uint32 adjustmentWindowSecs,
        uint64 backlog
    ) internal pure returns (ArbMultiGasConstraintsTypes.ResourceConstraint memory) {
        ArbMultiGasConstraintsTypes.WeightedResource[] memory resources =
            new ArbMultiGasConstraintsTypes.WeightedResource[](1);
        resources[0] = ArbMultiGasConstraintsTypes.WeightedResource({
            resource: ArbMultiGasConstraintsTypes.ResourceKind.Computation,
            weight: 1
        });
        return _createMultiGasConstraintWithResources(
            targetPerSec, adjustmentWindowSecs, backlog, resources
        );
    }

    function test_setMultiGasPricingConstraints_success() external {
        // Test with valid single constraint using single resource kind
        ArbMultiGasConstraintsTypes.ResourceConstraint[] memory constraints =
            new ArbMultiGasConstraintsTypes.ResourceConstraint[](1);
        constraints[0] = _createMultiGasConstraint(10_000_000, 100, 0);

        vm.prank(manager);
        resourceConstraintManager.setMultiGasPricingConstraints(constraints);

        // Test with multiple constraints using different resource kinds and weights
        ArbMultiGasConstraintsTypes.ResourceConstraint[] memory multipleConstraints =
            new ArbMultiGasConstraintsTypes.ResourceConstraint[](3);

        // Single resource: Computation with weight 1
        multipleConstraints[0] = _createMultiGasConstraint(7_000_000, 5, 0);

        // Multiple resources: HistoryGrowth (weight 2) + StorageAccess (weight 3)
        ArbMultiGasConstraintsTypes.WeightedResource[] memory resources2 =
            new ArbMultiGasConstraintsTypes.WeightedResource[](2);
        resources2[0] = ArbMultiGasConstraintsTypes.WeightedResource({
            resource: ArbMultiGasConstraintsTypes.ResourceKind.HistoryGrowth,
            weight: 2
        });
        resources2[1] = ArbMultiGasConstraintsTypes.WeightedResource({
            resource: ArbMultiGasConstraintsTypes.ResourceKind.StorageAccess,
            weight: 3
        });
        multipleConstraints[1] =
            _createMultiGasConstraintWithResources(50_000_000, 1000, 1, resources2);

        // Multiple resources: L1Calldata (weight 1) + WasmComputation (weight 5)
        ArbMultiGasConstraintsTypes.WeightedResource[] memory resources3 =
            new ArbMultiGasConstraintsTypes.WeightedResource[](2);
        resources3[0] = ArbMultiGasConstraintsTypes.WeightedResource({
            resource: ArbMultiGasConstraintsTypes.ResourceKind.L1Calldata,
            weight: 1
        });
        resources3[1] = ArbMultiGasConstraintsTypes.WeightedResource({
            resource: ArbMultiGasConstraintsTypes.ResourceKind.WasmComputation,
            weight: 5
        });
        multipleConstraints[2] =
            _createMultiGasConstraintWithResources(100_000_000, 86400, 10000, resources3);

        vm.prank(manager);
        resourceConstraintManager.setMultiGasPricingConstraints(multipleConstraints);

        // Test with empty constraints array (switch to previous pricing model)
        ArbMultiGasConstraintsTypes.ResourceConstraint[] memory emptyConstraints =
            new ArbMultiGasConstraintsTypes.ResourceConstraint[](0);
        vm.prank(manager);
        resourceConstraintManager.setMultiGasPricingConstraints(emptyConstraints);
    }

    function test_setMultiGasPricingConstraints_pricingExponentTooHigh() external {
        // Create constraints on the limit of the pricing exponent
        // Computation (weight=1), maxWeight=1
        // exponent = backlog * 1 * 1000 / (targetPerSec * adjustmentWindowSecs * 1) = backlog * 1000 / (targetPerSec * adjustmentWindowSecs)
        ArbMultiGasConstraintsTypes.ResourceConstraint[] memory multipleConstraints =
            new ArbMultiGasConstraintsTypes.ResourceConstraint[](3);
        // 35_000_000 * 1000 / (7_000_000 * 5) = 1000
        multipleConstraints[0] = _createMultiGasConstraint(7_000_000, 5, 35_000_000);
        // 300_000_000_000 * 1000 / (50_000_000 * 1000) = 6000
        multipleConstraints[1] = _createMultiGasConstraint(50_000_000, 1000, 300_000_000_000);
        // 8_640_000_000_000 * 1000 / (100_000_000 * 86400) = 1000
        multipleConstraints[2] = _createMultiGasConstraint(100_000_000, 86400, 8_640_000_000_000);
        // total = 1000 + 6000 + 1000 = 8000

        vm.prank(manager);
        resourceConstraintManager.setMultiGasPricingConstraints(multipleConstraints);

        // Modify constraint and set it up to the limit: 300_049_999_999 * 1000 / 50_000_000_000 = 6000, total = 8000
        multipleConstraints[1] = _createMultiGasConstraint(50_000_000, 1000, 300_049_999_999);
        vm.prank(manager);
        resourceConstraintManager.setMultiGasPricingConstraints(multipleConstraints);

        // Modify constraint and set it over the limit: 300_050_000_000 * 1000 / 50_000_000_000 = 6001, total = 8001
        multipleConstraints[1] = _createMultiGasConstraint(50_000_000, 1000, 300_050_000_000);
        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(ResourceConstraintManager.PricingExponentTooHigh.selector, 8001)
        );
        resourceConstraintManager.setMultiGasPricingConstraints(multipleConstraints);

        // Test with multi-resource constraint (with one resource over the limit)
        // Computation (weight=2) and HistoryGrowth (weight=1), targetPerSec=10_000_000, adjustmentWindowSecs=100
        // maxWeight=2, divisor=2_000_000_000
        // Computation exponent = backlog * 2 * 1000 / 2_000_000_000 = backlog / 1_000_000
        // HistoryGrowth exponent = backlog * 1 * 1000 / 2_000_000_000 = backlog / 2_000_000
        ArbMultiGasConstraintsTypes.WeightedResource[] memory resources =
            new ArbMultiGasConstraintsTypes.WeightedResource[](2);
        resources[0] = ArbMultiGasConstraintsTypes.WeightedResource({
            resource: ArbMultiGasConstraintsTypes.ResourceKind.Computation,
            weight: 2
        });
        resources[1] = ArbMultiGasConstraintsTypes.WeightedResource({
            resource: ArbMultiGasConstraintsTypes.ResourceKind.HistoryGrowth,
            weight: 1
        });

        ArbMultiGasConstraintsTypes.ResourceConstraint[] memory multiResourceConstraints =
            new ArbMultiGasConstraintsTypes.ResourceConstraint[](1);

        // Constraint up to the limit: Computation exponent = 8000, HistoryGrowth exponent = 4000
        multiResourceConstraints[0] =
            _createMultiGasConstraintWithResources(10_000_000, 100, 8_000_000_000, resources);
        vm.prank(manager);
        resourceConstraintManager.setMultiGasPricingConstraints(multiResourceConstraints);

        // Constraint over the limit: Computation exponent = 8001, HistoryGrowth exponent = 4000
        multiResourceConstraints[0] =
            _createMultiGasConstraintWithResources(10_000_000, 100, 8_001_000_000, resources);
        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(ResourceConstraintManager.PricingExponentTooHigh.selector, 8001)
        );
        resourceConstraintManager.setMultiGasPricingConstraints(multiResourceConstraints);
    }

    function test_setMultiGasPricingConstraints_accessControl() external {
        ArbMultiGasConstraintsTypes.ResourceConstraint[] memory constraints =
            new ArbMultiGasConstraintsTypes.ResourceConstraint[](1);
        constraints[0] = _createMultiGasConstraint(10_000_000, 100, 0);

        // Test non-manager cannot call
        vm.expectRevert();
        resourceConstraintManager.setMultiGasPricingConstraints(constraints);

        // Test admin without manager role cannot call
        vm.prank(admin);
        vm.expectRevert();
        resourceConstraintManager.setMultiGasPricingConstraints(constraints);

        // Test manager can call
        vm.prank(manager);
        resourceConstraintManager.setMultiGasPricingConstraints(constraints);
    }

    function test_setMultiGasPricingConstraints_invalidTarget() external {
        // Test gas target below minimum (6,999,999)
        ArbMultiGasConstraintsTypes.ResourceConstraint[] memory constraintsLowTarget =
            new ArbMultiGasConstraintsTypes.ResourceConstraint[](1);
        constraintsLowTarget[0] = _createMultiGasConstraint(6_999_999, 100, 0);

        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(
                ResourceConstraintManager.InvalidTarget.selector,
                uint64(6_999_999),
                uint64(100),
                uint64(0)
            )
        );
        resourceConstraintManager.setMultiGasPricingConstraints(constraintsLowTarget);

        // Test gas target above maximum (100,000,001)
        ArbMultiGasConstraintsTypes.ResourceConstraint[] memory constraintsHighTarget =
            new ArbMultiGasConstraintsTypes.ResourceConstraint[](1);
        constraintsHighTarget[0] = _createMultiGasConstraint(100_000_001, 100, 0);

        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(
                ResourceConstraintManager.InvalidTarget.selector,
                uint64(100_000_001),
                uint64(100),
                uint64(0)
            )
        );
        resourceConstraintManager.setMultiGasPricingConstraints(constraintsHighTarget);

        // Test edge cases (exactly at boundaries should succeed)
        ArbMultiGasConstraintsTypes.ResourceConstraint[] memory constraintsMinTarget =
            new ArbMultiGasConstraintsTypes.ResourceConstraint[](1);
        constraintsMinTarget[0] = _createMultiGasConstraint(7_000_000, 100, 0);
        vm.prank(manager);
        resourceConstraintManager.setMultiGasPricingConstraints(constraintsMinTarget);

        ArbMultiGasConstraintsTypes.ResourceConstraint[] memory constraintsMaxTarget =
            new ArbMultiGasConstraintsTypes.ResourceConstraint[](1);
        constraintsMaxTarget[0] = _createMultiGasConstraint(100_000_000, 100, 0);
        vm.prank(manager);
        resourceConstraintManager.setMultiGasPricingConstraints(constraintsMaxTarget);
    }

    function test_setMultiGasPricingConstraints_invalidPeriod() external {
        // Test adjustment window below minimum (4 seconds)
        ArbMultiGasConstraintsTypes.ResourceConstraint[] memory constraintsLowPeriod =
            new ArbMultiGasConstraintsTypes.ResourceConstraint[](1);
        constraintsLowPeriod[0] = _createMultiGasConstraint(10_000_000, 4, 0);

        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(
                ResourceConstraintManager.InvalidPeriod.selector,
                uint64(10_000_000),
                uint64(4),
                uint64(0)
            )
        );
        resourceConstraintManager.setMultiGasPricingConstraints(constraintsLowPeriod);

        // Test adjustment window above maximum (86401 seconds)
        ArbMultiGasConstraintsTypes.ResourceConstraint[] memory constraintsHighPeriod =
            new ArbMultiGasConstraintsTypes.ResourceConstraint[](1);
        constraintsHighPeriod[0] = _createMultiGasConstraint(10_000_000, 86401, 0);

        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(
                ResourceConstraintManager.InvalidPeriod.selector,
                uint64(10_000_000),
                uint64(86401),
                uint64(0)
            )
        );
        resourceConstraintManager.setMultiGasPricingConstraints(constraintsHighPeriod);

        // Test edge cases (exactly at boundaries should succeed)
        ArbMultiGasConstraintsTypes.ResourceConstraint[] memory constraintsMinPeriod =
            new ArbMultiGasConstraintsTypes.ResourceConstraint[](1);
        constraintsMinPeriod[0] = _createMultiGasConstraint(10_000_000, 5, 0);
        vm.prank(manager);
        resourceConstraintManager.setMultiGasPricingConstraints(constraintsMinPeriod);

        ArbMultiGasConstraintsTypes.ResourceConstraint[] memory constraintsMaxPeriod =
            new ArbMultiGasConstraintsTypes.ResourceConstraint[](1);
        constraintsMaxPeriod[0] = _createMultiGasConstraint(10_000_000, 86400, 0);
        vm.prank(manager);
        resourceConstraintManager.setMultiGasPricingConstraints(constraintsMaxPeriod);
    }

    function test_setMultiGasPricingConstraints_multipleConstraintValidation() external {
        // Test that all constraints are validated (not just the first one)
        ArbMultiGasConstraintsTypes.ResourceConstraint[] memory constraints =
            new ArbMultiGasConstraintsTypes.ResourceConstraint[](3);
        constraints[0] = _createMultiGasConstraint(10_000_000, 100, 0); // Valid
        constraints[1] = _createMultiGasConstraint(20_000_000, 200, 0); // Valid
        constraints[2] = _createMultiGasConstraint(5_000_000, 100, 0); // Invalid target

        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(
                ResourceConstraintManager.InvalidTarget.selector,
                uint64(5_000_000),
                uint64(100),
                uint64(0)
            )
        );
        resourceConstraintManager.setMultiGasPricingConstraints(constraints);

        // Test with invalid period in middle
        constraints[0] = _createMultiGasConstraint(10_000_000, 100, 0); // Valid
        constraints[1] = _createMultiGasConstraint(20_000_000, 3, 0); // Invalid period
        constraints[2] = _createMultiGasConstraint(30_000_000, 100, 0); // Valid

        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(
                ResourceConstraintManager.InvalidPeriod.selector,
                uint64(20_000_000),
                uint64(3),
                uint64(0)
            )
        );
        resourceConstraintManager.setMultiGasPricingConstraints(constraints);
    }

    function test_setMultiGasPricingConstraints_emptyResources() external {
        // Edge case: a constraint with an empty resources array should succeed (no-op constraint)
        ArbMultiGasConstraintsTypes.WeightedResource[] memory emptyResources =
            new ArbMultiGasConstraintsTypes.WeightedResource[](0);

        ArbMultiGasConstraintsTypes.ResourceConstraint[] memory constraints =
            new ArbMultiGasConstraintsTypes.ResourceConstraint[](1);
        constraints[0] = _createMultiGasConstraintWithResources(10_000_000, 100, 1, emptyResources);

        vm.prank(manager);
        resourceConstraintManager.setMultiGasPricingConstraints(constraints);
    }

    function test_setMultiGasPricingConstraints_duplicateResourceKind() external {
        // Test duplicate Computation (kind=1) in a single constraint
        ArbMultiGasConstraintsTypes.WeightedResource[] memory resources1 =
            new ArbMultiGasConstraintsTypes.WeightedResource[](2);
        resources1[0] = ArbMultiGasConstraintsTypes.WeightedResource({
            resource: ArbMultiGasConstraintsTypes.ResourceKind.Computation,
            weight: 1
        });
        resources1[1] = ArbMultiGasConstraintsTypes.WeightedResource({
            resource: ArbMultiGasConstraintsTypes.ResourceKind.Computation,
            weight: 2
        });

        ArbMultiGasConstraintsTypes.ResourceConstraint[] memory constraints1 =
            new ArbMultiGasConstraintsTypes.ResourceConstraint[](1);
        constraints1[0] = _createMultiGasConstraintWithResources(10_000_000, 100, 1, resources1);

        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(
                ResourceConstraintManager.InvalidResources.selector,
                uint8(ArbMultiGasConstraintsTypes.ResourceKind.Computation)
            )
        );
        resourceConstraintManager.setMultiGasPricingConstraints(constraints1);

        // Test duplicate Unknown (kind=0) in a single constraint
        ArbMultiGasConstraintsTypes.WeightedResource[] memory resources2 =
            new ArbMultiGasConstraintsTypes.WeightedResource[](2);
        resources2[0] = ArbMultiGasConstraintsTypes.WeightedResource({
            resource: ArbMultiGasConstraintsTypes.ResourceKind.Unknown,
            weight: 1
        });
        resources2[1] = ArbMultiGasConstraintsTypes.WeightedResource({
            resource: ArbMultiGasConstraintsTypes.ResourceKind.Unknown,
            weight: 3
        });

        ArbMultiGasConstraintsTypes.ResourceConstraint[] memory constraints2 =
            new ArbMultiGasConstraintsTypes.ResourceConstraint[](1);
        constraints2[0] = _createMultiGasConstraintWithResources(10_000_000, 100, 1, resources2);

        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(
                ResourceConstraintManager.InvalidResources.selector,
                uint8(ArbMultiGasConstraintsTypes.ResourceKind.Unknown)
            )
        );
        resourceConstraintManager.setMultiGasPricingConstraints(constraints2);

        // Test constraint with adjacent duplicates in sorted order: [Computation, HistoryGrowth, HistoryGrowth, StorageAccess]
        // Should revert on the duplicate HistoryGrowth at index 2
        ArbMultiGasConstraintsTypes.WeightedResource[] memory resources3 =
            new ArbMultiGasConstraintsTypes.WeightedResource[](4);
        resources3[0] = ArbMultiGasConstraintsTypes.WeightedResource({
            resource: ArbMultiGasConstraintsTypes.ResourceKind.Computation,
            weight: 1
        });
        resources3[1] = ArbMultiGasConstraintsTypes.WeightedResource({
            resource: ArbMultiGasConstraintsTypes.ResourceKind.HistoryGrowth,
            weight: 3
        });
        resources3[2] = ArbMultiGasConstraintsTypes.WeightedResource({
            resource: ArbMultiGasConstraintsTypes.ResourceKind.HistoryGrowth,
            weight: 4
        });
        resources3[3] = ArbMultiGasConstraintsTypes.WeightedResource({
            resource: ArbMultiGasConstraintsTypes.ResourceKind.StorageAccess,
            weight: 2
        });

        ArbMultiGasConstraintsTypes.ResourceConstraint[] memory constraints3 =
            new ArbMultiGasConstraintsTypes.ResourceConstraint[](1);
        constraints3[0] = _createMultiGasConstraintWithResources(10_000_000, 100, 1, resources3);

        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(
                ResourceConstraintManager.InvalidResources.selector,
                uint8(ArbMultiGasConstraintsTypes.ResourceKind.HistoryGrowth)
            )
        );
        resourceConstraintManager.setMultiGasPricingConstraints(constraints3);

        // Duplicate resources with zero backlog
        ArbMultiGasConstraintsTypes.WeightedResource[] memory resources4 =
            new ArbMultiGasConstraintsTypes.WeightedResource[](2);
        resources4[0] = ArbMultiGasConstraintsTypes.WeightedResource({
            resource: ArbMultiGasConstraintsTypes.ResourceKind.Computation,
            weight: 1
        });
        resources4[1] = ArbMultiGasConstraintsTypes.WeightedResource({
            resource: ArbMultiGasConstraintsTypes.ResourceKind.Computation,
            weight: 2
        });

        ArbMultiGasConstraintsTypes.ResourceConstraint[] memory constraints4 =
            new ArbMultiGasConstraintsTypes.ResourceConstraint[](1);
        constraints4[0] = _createMultiGasConstraintWithResources(10_000_000, 100, 0, resources4);

        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(
                ResourceConstraintManager.InvalidResources.selector,
                uint8(ArbMultiGasConstraintsTypes.ResourceKind.Computation)
            )
        );
        resourceConstraintManager.setMultiGasPricingConstraints(constraints4);
    }

    function test_setMultiGasPricingConstraints_zeroWeightsWithNonZeroBacklog() external {
        // Edge case: all-zero weights with non-zero backlog: sorted check runs but no exponent is added
        ArbMultiGasConstraintsTypes.WeightedResource[] memory resources =
            new ArbMultiGasConstraintsTypes.WeightedResource[](2);
        resources[0] = ArbMultiGasConstraintsTypes.WeightedResource({
            resource: ArbMultiGasConstraintsTypes.ResourceKind.Computation,
            weight: 0
        });
        resources[1] = ArbMultiGasConstraintsTypes.WeightedResource({
            resource: ArbMultiGasConstraintsTypes.ResourceKind.HistoryGrowth,
            weight: 0
        });

        ArbMultiGasConstraintsTypes.ResourceConstraint[] memory constraints =
            new ArbMultiGasConstraintsTypes.ResourceConstraint[](1);
        constraints[0] = _createMultiGasConstraintWithResources(10_000_000, 100, 1, resources);

        vm.prank(manager);
        resourceConstraintManager.setMultiGasPricingConstraints(constraints);
    }

    function test_setMultiGasPricingConstraints_unsortedResources() external {
        // Resources not in ascending order by kind should revert
        // HistoryGrowth (kind=2) before Computation (kind=1)
        ArbMultiGasConstraintsTypes.WeightedResource[] memory resources =
            new ArbMultiGasConstraintsTypes.WeightedResource[](2);
        resources[0] = ArbMultiGasConstraintsTypes.WeightedResource({
            resource: ArbMultiGasConstraintsTypes.ResourceKind.HistoryGrowth,
            weight: 1
        });
        resources[1] = ArbMultiGasConstraintsTypes.WeightedResource({
            resource: ArbMultiGasConstraintsTypes.ResourceKind.Computation,
            weight: 2
        });

        ArbMultiGasConstraintsTypes.ResourceConstraint[] memory constraints =
            new ArbMultiGasConstraintsTypes.ResourceConstraint[](1);
        constraints[0] = _createMultiGasConstraintWithResources(10_000_000, 100, 1, resources);

        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(
                ResourceConstraintManager.InvalidResources.selector,
                uint8(ArbMultiGasConstraintsTypes.ResourceKind.Computation)
            )
        );
        resourceConstraintManager.setMultiGasPricingConstraints(constraints);

        // Larger unsorted array: [Computation(1), StorageAccess(3), HistoryGrowth(2)]
        ArbMultiGasConstraintsTypes.WeightedResource[] memory resources2 =
            new ArbMultiGasConstraintsTypes.WeightedResource[](3);
        resources2[0] = ArbMultiGasConstraintsTypes.WeightedResource({
            resource: ArbMultiGasConstraintsTypes.ResourceKind.Computation,
            weight: 1
        });
        resources2[1] = ArbMultiGasConstraintsTypes.WeightedResource({
            resource: ArbMultiGasConstraintsTypes.ResourceKind.StorageAccess,
            weight: 2
        });
        resources2[2] = ArbMultiGasConstraintsTypes.WeightedResource({
            resource: ArbMultiGasConstraintsTypes.ResourceKind.HistoryGrowth,
            weight: 3
        });

        ArbMultiGasConstraintsTypes.ResourceConstraint[] memory constraints2 =
            new ArbMultiGasConstraintsTypes.ResourceConstraint[](1);
        constraints2[0] = _createMultiGasConstraintWithResources(10_000_000, 100, 1, resources2);

        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(
                ResourceConstraintManager.InvalidResources.selector,
                uint8(ArbMultiGasConstraintsTypes.ResourceKind.HistoryGrowth)
            )
        );
        resourceConstraintManager.setMultiGasPricingConstraints(constraints2);

        // Unsorted resources should revert even with zero backlog
        ArbMultiGasConstraintsTypes.WeightedResource[] memory resources3 =
            new ArbMultiGasConstraintsTypes.WeightedResource[](2);
        resources3[0] = ArbMultiGasConstraintsTypes.WeightedResource({
            resource: ArbMultiGasConstraintsTypes.ResourceKind.HistoryGrowth,
            weight: 1
        });
        resources3[1] = ArbMultiGasConstraintsTypes.WeightedResource({
            resource: ArbMultiGasConstraintsTypes.ResourceKind.Computation,
            weight: 2
        });

        ArbMultiGasConstraintsTypes.ResourceConstraint[] memory constraints3 =
            new ArbMultiGasConstraintsTypes.ResourceConstraint[](1);
        constraints3[0] = _createMultiGasConstraintWithResources(10_000_000, 100, 0, resources3);

        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(
                ResourceConstraintManager.InvalidResources.selector,
                uint8(ArbMultiGasConstraintsTypes.ResourceKind.Computation)
            )
        );
        resourceConstraintManager.setMultiGasPricingConstraints(constraints3);
    }
}

contract ArbOwnerMock {
    bool public removeChainOwnerCalled;
    uint64[3][] public lastConstraints;
    bytes internal lastMultiGasConstraintsEncoded;

    function removeChainOwner(
        address
    ) external {
        removeChainOwnerCalled = true;
    }

    function setGasPricingConstraints(
        uint64[3][] calldata constraints
    ) external {
        lastConstraints = constraints;
    }

    function setMultiGasPricingConstraints(
        ArbMultiGasConstraintsTypes.ResourceConstraint[] calldata constraints
    ) external {
        lastMultiGasConstraintsEncoded = abi.encode(constraints);
    }
}
