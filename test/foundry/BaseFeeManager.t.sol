// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "../../src/chain/BaseFeeManager.sol";

// We need this library to storage the addresses of the mocked contracts,
// since they have to be available in both BaseFeeManagerTest and the mock contracts
library AddressStore {
    address constant StorageContractAddress = address(0xabcdef);
    address constant ArbOwnerAddress = address(0x70);
    address constant ArbGasInfoAddress = address(0x6c);
}

contract BaseFeeManagerTest is Test {
    ArbOwnerMock internal constant ARB_OWNER = ArbOwnerMock(AddressStore.ArbOwnerAddress);
    ArbGasInfoMock internal constant ARB_GAS_INFO = ArbGasInfoMock(AddressStore.ArbGasInfoAddress);

    address constant admin = address(1337);
    address constant manager = address(7331);
    uint256 constant expiryTimestamp = 12345678;

    BaseFeeManager public baseFeeManager;

    constructor() {
        baseFeeManager = new BaseFeeManager(admin, manager, expiryTimestamp);
        vm.etch(AddressStore.StorageContractAddress, type(StorageContractMock).runtimeCode);
        vm.etch(AddressStore.ArbOwnerAddress, type(ArbOwnerMock).runtimeCode);
        vm.etch(AddressStore.ArbGasInfoAddress, type(ArbGasInfoMock).runtimeCode);
    }

    function test_revoke() external {
        // Test before expiry
        vm.warp(expiryTimestamp - 1);
        vm.expectRevert(BaseFeeManager.NotExpired.selector);
        baseFeeManager.revoke();

        // Test after expiry
        vm.warp(expiryTimestamp);
        assertFalse(ARB_OWNER.removeChainOwnerCalled());
        baseFeeManager.revoke();
        assertTrue(ARB_OWNER.removeChainOwnerCalled());
    }

    //
    // --- setL2BaseFee tests ---
    //
    function test_setL2BaseFee_success() external {
        // Set the on-chain minimum low so the cross-validation passes
        ARB_OWNER.setMinimumL2BaseFee(0.01 gwei);

        // Test at minimum
        vm.prank(manager);
        baseFeeManager.setL2BaseFee(0.01 gwei);

        // Test at maximum
        vm.prank(manager);
        baseFeeManager.setL2BaseFee(0.1 gwei);

        // Test in the middle
        vm.prank(manager);
        baseFeeManager.setL2BaseFee(0.05 gwei);
    }

    function test_setL2BaseFee_accessControl() external {
        // Test non-manager cannot call
        vm.expectRevert();
        baseFeeManager.setL2BaseFee(0.05 gwei);

        // Test admin without manager role cannot call
        vm.prank(admin);
        vm.expectRevert();
        baseFeeManager.setL2BaseFee(0.05 gwei);

        // Test manager can call
        vm.prank(manager);
        baseFeeManager.setL2BaseFee(0.05 gwei);
    }

    function test_setL2BaseFee_invalidBaseFee() external {
        // Test below minimum (0.01 gwei - 1)
        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(BaseFeeManager.InvalidBaseFee.selector, 0.01 gwei - 1)
        );
        baseFeeManager.setL2BaseFee(0.01 gwei - 1);

        // Test above maximum (0.1 gwei + 1)
        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(BaseFeeManager.InvalidBaseFee.selector, 0.1 gwei + 1)
        );
        baseFeeManager.setL2BaseFee(0.1 gwei + 1);
    }

    function test_setL2BaseFee_belowMinimumBaseFee() external {
        // Set the on-chain minimum to 0.05 gwei
        ARB_OWNER.setMinimumL2BaseFee(0.05 gwei);

        // Setting base fee at the minimum should succeed
        vm.prank(manager);
        baseFeeManager.setL2BaseFee(0.05 gwei);

        // Setting base fee above the minimum should succeed
        vm.prank(manager);
        baseFeeManager.setL2BaseFee(0.06 gwei);

        // Setting base fee below the on-chain minimum should revert
        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseFeeManager.BaseFeeBelowMinimum.selector, 0.04 gwei, 0.05 gwei
            )
        );
        baseFeeManager.setL2BaseFee(0.04 gwei);
    }

    //
    // --- setMinimumL2BaseFee tests ---
    //
    function test_setMinimumL2BaseFee_success() external {
        // Test at minimum
        vm.prank(manager);
        baseFeeManager.setMinimumL2BaseFee(0.01 gwei);

        // Test at maximum
        vm.prank(manager);
        baseFeeManager.setMinimumL2BaseFee(0.1 gwei);

        // Test in the middle
        vm.prank(manager);
        baseFeeManager.setMinimumL2BaseFee(0.05 gwei);
    }

    function test_setMinimumL2BaseFee_accessControl() external {
        // Test non-manager cannot call
        vm.expectRevert();
        baseFeeManager.setMinimumL2BaseFee(0.05 gwei);

        // Test admin without manager role cannot call
        vm.prank(admin);
        vm.expectRevert();
        baseFeeManager.setMinimumL2BaseFee(0.05 gwei);

        // Test manager can call
        vm.prank(manager);
        baseFeeManager.setMinimumL2BaseFee(0.05 gwei);
    }

    function test_setMinimumL2BaseFee_invalidBaseFee() external {
        // Test below minimum (0.01 gwei - 1)
        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(BaseFeeManager.InvalidBaseFee.selector, 0.01 gwei - 1)
        );
        baseFeeManager.setMinimumL2BaseFee(0.01 gwei - 1);

        // Test above maximum (0.1 gwei + 1)
        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(BaseFeeManager.InvalidBaseFee.selector, 0.1 gwei + 1)
        );
        baseFeeManager.setMinimumL2BaseFee(0.1 gwei + 1);
    }

    function test_setMinimumL2BaseFee_updatesMinimumForBaseFeeCheck() external {
        // Set a new minimum via the manager contract
        vm.prank(manager);
        baseFeeManager.setMinimumL2BaseFee(0.08 gwei);

        // Confirm the minimum was updated in the shared storage
        assertEq(ARB_GAS_INFO.getMinimumGasPrice(), 0.08 gwei);

        // Setting base fee below the new minimum should revert
        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseFeeManager.BaseFeeBelowMinimum.selector, 0.07 gwei, 0.08 gwei
            )
        );
        baseFeeManager.setL2BaseFee(0.07 gwei);

        // Setting base fee at the new minimum should succeed
        vm.prank(manager);
        baseFeeManager.setL2BaseFee(0.08 gwei);
    }
}

// Since ArbOwner and ArbGasInfo access the same shared database, we create a mock storage contract to hold that storage and access it
// from forwarded calls in ArbOwnerMock and ArbGasInfoMock.
contract StorageContractMock {
    uint256 public l2BaseFee;
    uint256 public minimumL2BaseFee;

    constructor() {
        l2BaseFee = 0.02 gwei;
        minimumL2BaseFee = 0.02 gwei;
    }

    function setL2BaseFee(
        uint256 priceInWei
    ) external {
        l2BaseFee = priceInWei;
    }

    function setMinimumL2BaseFee(
        uint256 priceInWei
    ) external {
        minimumL2BaseFee = priceInWei;
    }

    function getMinimumGasPrice() external view returns (uint256) {
        return minimumL2BaseFee;
    }
}

contract ArbGasInfoMock {
    StorageContractMock internal constant STORAGE =
        StorageContractMock(AddressStore.StorageContractAddress);

    function getMinimumGasPrice() external view returns (uint256) {
        return STORAGE.getMinimumGasPrice();
    }
}

contract ArbOwnerMock {
    StorageContractMock internal constant STORAGE =
        StorageContractMock(AddressStore.StorageContractAddress);

    bool public removeChainOwnerCalled;

    function removeChainOwner(
        address
    ) external {
        removeChainOwnerCalled = true;
    }

    function setL2BaseFee(
        uint256 priceInWei
    ) external {
        STORAGE.setL2BaseFee(priceInWei);
    }

    function setMinimumL2BaseFee(
        uint256 priceInWei
    ) external {
        STORAGE.setMinimumL2BaseFee(priceInWei);
    }

    function getMinimumGasPrice() external view returns (uint256) {
        return STORAGE.getMinimumGasPrice();
    }
}
