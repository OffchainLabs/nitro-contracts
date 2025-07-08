// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import {
    BaseNitroContractsUpgradeAction,
    ImplementationsRegistry
} from "./BaseNitroContractsUpgradeAction.sol";
import {IOutbox} from "../bridge/IOutbox.sol";

contract NitroContractsUpgradeAction_4_0_0 is BaseNitroContractsUpgradeAction {
    constructor(
        ImplementationsRegistry _prevImplementationsRegistry,
        ImplementationsRegistry _nextImplementationsRegistry
    ) BaseNitroContractsUpgradeAction(_prevImplementationsRegistry, _nextImplementationsRegistry) {}

    function perform(address proxyAdmin, address inbox, uint256 dummyOutboxArg) external {
        _upgradeAllProxies(proxyAdmin, inbox);

        // let's say the outbox is the only contract that needs a postUpgradeInit call, it would look like this:
        // IOutbox(_outbox(inbox)).postUpgradeInit(dummyOutboxArg);
    }
}
