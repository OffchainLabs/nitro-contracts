// Copyright 2022-2025, Offchain Labs, Inc.
// For license information, see https://github.com/nitro/blob/master/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "../precompiles/ArbOwner.sol";
import "../precompiles/ArbGasInfo.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract BaseFeeManager is AccessControlEnumerable {
    ArbOwner internal constant ARB_OWNER = ArbOwner(address(0x70));
    ArbGasInfo internal constant ARB_GAS_INFO = ArbGasInfo(address(0x6c));
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    uint256 public constant MIN_BASE_FEE_WEI = 0.01 gwei;
    uint256 public constant MAX_BASE_FEE_WEI = 0.1 gwei;

    uint256 public expiryTimestamp;

    error InvalidBaseFee(uint256 newL2BaseFee);
    error BaseFeeBelowMinimum(uint256 newL2BaseFee, uint256 minimumBaseFee);
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

    /// @notice Sets the L2 base fee within the allowed range, and above the minimum base fee
    /// @param newL2BaseFeeInWei The new L2 base fee to set (in wei)
    function setL2BaseFee(
        uint256 newL2BaseFeeInWei
    ) external onlyRole(MANAGER_ROLE) {
        if (newL2BaseFeeInWei < MIN_BASE_FEE_WEI || newL2BaseFeeInWei > MAX_BASE_FEE_WEI) {
            revert InvalidBaseFee(newL2BaseFeeInWei);
        }

        uint256 minimumL2BaseFee = ARB_GAS_INFO.getMinimumGasPrice();
        if (newL2BaseFeeInWei < minimumL2BaseFee) {
            revert BaseFeeBelowMinimum(newL2BaseFeeInWei, minimumL2BaseFee);
        }

        ARB_OWNER.setL2BaseFee(newL2BaseFeeInWei);
    }

    /// @notice Sets the minimum L2 base fee within the allowed range
    /// @param newMinimumL2BaseFeeInWei The new minimum L2 base fee to set (in wei)
    function setMinimumL2BaseFee(
        uint256 newMinimumL2BaseFeeInWei
    ) external onlyRole(MANAGER_ROLE) {
        if (
            newMinimumL2BaseFeeInWei < MIN_BASE_FEE_WEI
                || newMinimumL2BaseFeeInWei > MAX_BASE_FEE_WEI
        ) {
            revert InvalidBaseFee(newMinimumL2BaseFeeInWei);
        }

        ARB_OWNER.setMinimumL2BaseFee(newMinimumL2BaseFeeInWei);
    }
}
