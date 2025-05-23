// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Bridge} from "../IERC20Bridge.sol";
import {IERC20MigrationOutbox} from "./IERC20MigrationOutbox.sol";

/**
 * @title  An outbox for migrating nativeToken of a rollup from the native bridge to a new address
 * @notice For some custom fee token orbit chains, they might want to have their native token being managed by an external bridge. This
 *         contract allow permissionless migration of the native bridge collateral, without requiring any change in the vanilla outbox.
 * @dev    This contract should be allowed as an outbox in conjunction with the vanilla outbox contract. Nonzero value withdrawal via the
 *         native bridge (ArbSys) must be disabled on the child chain or funds and messages will be stuck.
 */
contract ERC20MigrationOutbox is IERC20MigrationOutbox {
    IERC20Bridge public immutable bridge;
    address public immutable nativeToken;
    address public immutable destination;

    constructor(IERC20Bridge _bridge, address _destination) {
        if (_destination == address(0)) {
            revert InvalidDestination();
        }
        bridge = _bridge;
        destination = _destination;
        nativeToken = bridge.nativeToken();
    }

    /// @inheritdoc IERC20MigrationOutbox
    function migrate() external {
        uint256 bal = IERC20(nativeToken).balanceOf(address(bridge));
        if (bal == 0) {
            revert NoBalanceToMigrate();
        }
        (bool success, bytes memory returndata) = bridge.executeCall(destination, bal, "");
        if (!success) {
            revert MigrationFailed(returndata);
        }
        emit CollateralMigrated(destination, bal);
    }
}
