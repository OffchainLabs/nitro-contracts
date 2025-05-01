// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';

contract BridgeUpgrade {
  function upgradeAndCall(
    address proxy,
    address newImplementation,
    address proxyAdmin,
    bytes calldata data
  ) external {
    ProxyAdmin(proxyAdmin).upgradeAndCall(
      TransparentUpgradeableProxy(payable(proxy)),
      newImplementation,
      data
    );
  }
}
