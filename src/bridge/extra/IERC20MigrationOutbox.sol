// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.4;

import {IERC20Bridge} from "../IERC20Bridge.sol";

interface IERC20MigrationOutbox {
    error NoBalanceToMigrate();
    error MigrationFailed(bytes returndata);

    function bridge() external view returns (IERC20Bridge);
    function nativeToken() external view returns (address);
    function destination() external view returns (address);

    /// @notice Migrate the native token of the rollup to the destination address, can be called by anyone
    function migrate() external;
}
