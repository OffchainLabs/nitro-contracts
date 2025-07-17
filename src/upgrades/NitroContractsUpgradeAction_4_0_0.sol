// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import {
    BaseNitroContractsUpgradeAction,
    ImplementationsRegistry
} from "./BaseNitroContractsUpgradeAction.sol";
import {IOutbox} from "../bridge/IOutbox.sol";

/// @notice An example of a Nitro contracts upgrade action for version 4.0.0.
///         Inherits the base upgrade action contract. Verifies that all contracts are currently on 3.1.0 and upgrades all to 4.0.0
contract NitroContractsUpgradeAction_4_0_0 is BaseNitroContractsUpgradeAction {
    constructor(
        ImplementationsRegistry implRegistry_3_1_0,
        ImplementationsRegistry implRegistry_4_0_0
    ) BaseNitroContractsUpgradeAction(implRegistry_3_1_0, implRegistry_4_0_0) {}

    function perform(address proxyAdmin, address inbox, uint256 dummyOutboxArg) external {
        _upgradeAllContracts(proxyAdmin, inbox);

        // let's say the outbox is the only contract that needs a postUpgradeInit call, it would look like this:
        // IOutbox(_outbox(inbox)).postUpgradeInit(dummyOutboxArg);
    }
}
