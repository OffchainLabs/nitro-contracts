// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import 'forge-std/Test.sol';
import '../src/bridge/BridgeTransfer.sol';
import '../src/bridge/BridgeUpgrade.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';

contract BridgeTransferTest is Test {
  BridgeTransfer public bridgeTransfer;
  BridgeUpgrade public bridgeUpgrade;
  ProxyAdmin public proxyAdmin;
  TransparentUpgradeableProxy public proxy;
  IERC20 public ghst;

  address public constant GHST = 0x7c6b91D9Be155A6Db01f749217d76fF02A7227F2;
  address public admin = address(0x1);
  address public executor = address(0x2);
  address public user = address(0x3);

  function setUp() public {
    // Deploy implementation
    bridgeTransfer = new BridgeTransfer();

    // Deploy upgrade contract
    bridgeUpgrade = new BridgeUpgrade();

    // Deploy proxy admin
    proxyAdmin = new ProxyAdmin(admin);

    // Deploy proxy
    proxy = new TransparentUpgradeableProxy(
      address(bridgeTransfer),
      address(proxyAdmin),
      abi.encodeWithSelector(BridgeTransfer.initialize.selector)
    );

    // Get GHST interface
    ghst = IERC20(GHST);

    // Set up test environment
    vm.startPrank(admin);

    // Give some GHST to the bridge
    vm.etch(GHST, new bytes(0x1000)); // Mock GHST contract
    vm.store(GHST, bytes32(uint256(0)), bytes32(uint256(1000))); // Set total supply
    vm.store(GHST, bytes32(uint256(1)), bytes32(uint256(1000))); // Set balance of bridge
    vm.store(GHST, bytes32(uint256(2)), bytes32(uint256(1000))); // Set allowance

    vm.stopPrank();
  }

  function testUpgradeAndTransfer() public {
    // Encode the transfer call
    bytes memory transferCalldata = abi.encodeWithSelector(
      BridgeTransfer.transfer.selector
    );

    // Encode the upgrade and call
    bytes memory upgradeCalldata = abi.encodeWithSelector(
      BridgeUpgrade.upgradeAndCall.selector,
      address(proxy),
      address(bridgeTransfer),
      address(proxyAdmin),
      transferCalldata
    );

    // Execute upgrade and transfer
    vm.startPrank(executor);
    (bool success, ) = address(bridgeUpgrade).call(upgradeCalldata);
    require(success, 'Upgrade and transfer failed');
    vm.stopPrank();

    // Verify GHST was transferred to admin
    assertEq(ghst.balanceOf(admin), 1000, 'Admin should have received GHST');
    assertEq(ghst.balanceOf(address(proxy)), 0, 'Bridge should have no GHST');
  }
}
