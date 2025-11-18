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
}

contract ArbOwnerMock {
    bool public removeChainOwnerCalled;
    uint64[3][] public lastConstraints;

    function removeChainOwner(
        address ownerToRemove
    ) external {
        removeChainOwnerCalled = true;
    }

    function setGasPricingConstraints(
        uint64[3][] calldata constraints
    ) external {
        lastConstraints = constraints;
    }

    function getLastConstraints() external view returns (uint64[3][] memory) {
        return lastConstraints;
    }
}
