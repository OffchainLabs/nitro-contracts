// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import 'forge-std/Script.sol';
import '../src/bridge/BridgeTransfer.sol';
import '../src/bridge/BridgeUpgrade.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/access/IAccessControl.sol';
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

interface ITransparentUpgradeableProxy {
  function admin() external view returns (address);
}

interface IUpgradeExecutor is IAccessControl {
  function grantRole(bytes32 role, address account) external;
  function execute(
    address upgrade,
    bytes calldata upgradeCallData
  ) external payable;
}

contract TestBridgeTransfer is Script {
  // Base mainnet addresses
  address public constant BRIDGE_PROXY =
    0x9F904Fea0efF79708B37B99960e05900fE310A8E; // Replace with actual bridge proxy
  address public constant PROXY_ADMIN =
    0xaDD83738fd8a1cdCccab49e761F36ED1C93805FD; // Base's default proxy admin
  address public constant GHST = 0xcD2F22236DD9Dfe2356D7C543161D4d260FD9BcB;
  address public constant NEW_EXECUTOR =
    0x01F010a5e001fe9d6940758EA5e8c777885E351e;
  bytes32 public constant EXECUTOR_ROLE = keccak256('EXECUTOR_ROLE');

  function run() external {
    // 1. Deploy a new UpgradeExecutor contract
    // NOTE: Replace with your actual UpgradeExecutor deployment logic if needed
    address[] memory executors = new address[](1);
    executors[0] = NEW_EXECUTOR;
    UpgradeExecutorMock newUpgradeExecutor = new UpgradeExecutorMock();
    newUpgradeExecutor.initialize(msg.sender, executors);
    address newUpgradeExecutorAddress = address(newUpgradeExecutor);
    console.log('New UpgradeExecutor deployed at:', newUpgradeExecutorAddress);

    // 2. Transfer ownership of the ProxyAdmin to the new UpgradeExecutor
    vm.startPrank(msg.sender); // msg.sender must be the current owner of ProxyAdmin
    ProxyAdmin proxyAdmin = ProxyAdmin(PROXY_ADMIN);
    proxyAdmin.transferOwnership(newUpgradeExecutorAddress);
    vm.stopPrank();
    console.log('ProxyAdmin ownership transferred to new UpgradeExecutor');

    // 3. Grant EXECUTOR_ROLE to NEW_EXECUTOR on the new UpgradeExecutor
    vm.startPrank(newUpgradeExecutorAddress);
    newUpgradeExecutor.grantRole(EXECUTOR_ROLE, NEW_EXECUTOR);
    vm.stopPrank();
    console.log('EXECUTOR_ROLE granted to NEW_EXECUTOR');

    // 4. Deploy new implementation
    BridgeTransfer bridgeTransfer = new BridgeTransfer();
    console.log(
      'BridgeTransfer implementation deployed at:',
      address(bridgeTransfer)
    );

    // 5. Deploy upgrade contract
    BridgeUpgrade bridgeUpgrade = new BridgeUpgrade();
    console.log('BridgeUpgrade deployed at:', address(bridgeUpgrade));

    IERC20 ghst = IERC20(GHST);
    uint256 initialBridgeBalance = ghst.balanceOf(BRIDGE_PROXY);
    console.log('Initial bridge GHST balance:', initialBridgeBalance);

    bytes memory transferCalldata = abi.encodeWithSelector(
      BridgeTransfer.transfer.selector
    );

    bytes memory upgradeAndCallCalldata = abi.encodeWithSelector(
      BridgeUpgrade.upgradeAndCall.selector,
      BRIDGE_PROXY,
      address(bridgeTransfer),
      address(proxyAdmin),
      transferCalldata
    );

    // 6. Impersonate NEW_EXECUTOR to execute the upgrade via new UpgradeExecutor
    vm.startPrank(NEW_EXECUTOR);
    newUpgradeExecutor.execute(address(bridgeUpgrade), upgradeAndCallCalldata);
    vm.stopPrank();

    uint256 finalBridgeBalance = ghst.balanceOf(BRIDGE_PROXY);
    uint256 adminBalance = ghst.balanceOf(address(proxyAdmin));
    console.log('Final bridge GHST balance:', finalBridgeBalance);
    console.log('Admin GHST balance:', adminBalance);
  }
}
