// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';

interface IProxyAdmin {
  function owner() external view returns (address);
}

contract BridgeTransfer is Initializable, OwnableUpgradeable {
  // GHST token address on Base
  address public constant GHST = 0x7c6b91D9Be155A6Db01f749217d76fF02A7227F2;

  function initialize(address initialOwner) public initializer {
    __Ownable_init();
    _transferOwnership(initialOwner);
  }

  function transferAllGHST(address recipient) external onlyOwner {
    require(recipient != address(0), 'Invalid recipient');
    uint256 balance = IERC20(GHST).balanceOf(address(this));
    require(balance > 0, 'No GHST to transfer');
    require(IERC20(GHST).transfer(recipient, balance), 'Transfer failed');
  }

  // Helper to get the ProxyAdmin address (ERC1967 standard)
  function _getProxyAdmin() internal view returns (address admin) {
    bytes32 slot = bytes32(uint256(keccak256('eip1967.proxy.admin')) - 1);
    // solhint-disable-next-line no-inline-assembly
    assembly {
      admin := sload(slot)
    }
  }
}
