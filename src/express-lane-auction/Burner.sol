// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {ERC20BurnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "./Errors.sol";

/// @notice A simple contract that can burn any tokens that are transferred to it
///         Token must support the ERC20BurnableUpgradeable.burn(uint256) interface
contract Burner {
    ERC20BurnableUpgradeable public immutable token;

    constructor(
        address _token
    ) {
        if (_token == address(0)) {
            revert ZeroAddress();
        }
        token = ERC20BurnableUpgradeable(_token);
    }

    /// @notice Can be called at any time by anyone to burn any tokens held by this burner
    function burn() external {
        token.burn(token.balanceOf(address(this)));
    }
}
