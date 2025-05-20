// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.4;

import {IERC20Bridge} from "../IERC20Bridge.sol";

interface IERC20MigrationOutbox {
    /// @notice Thrown when there is no balance to migrate.
    error NoBalanceToMigrate();

    /// @notice Thrown when the migration process fails.
    /// @param returndata The return data from the failed migration call.
    error MigrationFailed(bytes returndata);

    /// @notice Thrown when the destination address is invalid.
    error InvalidDestination();

    /// @notice Emitted when a migration is completed.
    event CollateralMigrated(address indexed destination, uint256 amount);

    /// @notice Returns the address of the bridge contract.
    /// @return The IERC20Bridge contract address.
    function bridge() external view returns (IERC20Bridge);

    /// @notice Returns the address of the native token to be migrated.
    /// @return The address of the native token.
    function nativeToken() external view returns (address);

    /// @notice Returns the destination address for the migration.
    /// @return The address where the native token will be migrated to.
    function destination() external view returns (address);

    /// @notice Migrate the native token of the rollup to the destination address.
    /// @dev Can be called by anyone. Reverts if there is no balance to migrate or if the migration fails.
    function migrate() external;
}
