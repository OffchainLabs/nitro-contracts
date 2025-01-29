// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./AbsRollupEventInbox.sol";
import "../bridge/IEthBridge.sol";
import {INITIALIZATION_MSG_TYPE} from "../libraries/MessageTypes.sol";

/**
 * @title The inbox for rollup protocol events
 */
contract RollupEventInbox is AbsRollupEventInbox {
    constructor() AbsRollupEventInbox() {}

    function _enqueueInitializationMsg(
        bytes memory initMsg
    ) internal override returns (uint256) {
        return IEthBridge(address(bridge)).enqueueDelayedMessage(
            INITIALIZATION_MSG_TYPE, address(0), keccak256(initMsg)
        );
    }

    function _currentDataCostToReport() internal view override returns (uint256) {
        uint256 currentDataCost = block.basefee;
        if (ArbitrumChecker.runningOnArbitrum()) {
            currentDataCost += ArbGasInfo(address(0x6c)).getL1BaseFeeEstimate();
        }
        return currentDataCost;
    }
}
