// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import 'forge-std/Script.sol';
import '../src/bridge/BridgeTransfer.sol';
import '../src/bridge/BridgeUpgrade.sol';
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';

contract DeployBridgeTransfer is Script {
  function run() external {
    uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
    vm.startBroadcast(deployerPrivateKey);

    // Deploy new implementation
    BridgeTransfer bridgeTransfer = new BridgeTransfer();
    console.log(
      'BridgeTransfer implementation deployed at:',
      address(bridgeTransfer)
    );

    // Deploy upgrade contract
    BridgeUpgrade bridgeUpgrade = new BridgeUpgrade();
    console.log('BridgeUpgrade deployed at:', address(bridgeUpgrade));

    // Get existing proxy and proxy admin addresses from environment
    address proxyAddress = vm.envAddress('BRIDGE_PROXY');
    address proxyAdminAddress = vm.envAddress('PROXY_ADMIN');
    address upgradeExecutorAddress = vm.envAddress('UPGRADE_EXECUTOR');

    // Encode the transfer call
    bytes memory transferCalldata = abi.encodeWithSelector(
      BridgeTransfer.transfer.selector
    );

    // Encode the upgrade and call
    bytes memory upgradeCalldata = abi.encodeWithSelector(
      BridgeUpgrade.upgradeAndCall.selector,
      proxyAddress,
      address(bridgeTransfer),
      proxyAdminAddress,
      transferCalldata
    );

    // Execute upgrade and transfer via UpgradeExecutor
    (bool success, ) = upgradeExecutorAddress.call(upgradeCalldata);
    require(success, 'Upgrade and transfer failed');

    console.log('Upgrade and transfer completed successfully');

    vm.stopBroadcast();
  }
}
