// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./AbsRollupEventInbox.sol";
import "../bridge/IERC20Bridge.sol";
import {INITIALIZATION_MSG_TYPE} from "../libraries/MessageTypes.sol";

/**
 * @title The inbox for rollup protocol events
 */
contract ERC20RollupEventInbox is AbsRollupEventInbox {
    constructor() AbsRollupEventInbox() {}

    function _enqueueInitializationMsg(
        bytes memory initMsg
    ) internal override returns (uint256) {
        uint256 tokenAmount = 0;
        return IERC20Bridge(address(bridge)).enqueueDelayedMessage(
            INITIALIZATION_MSG_TYPE, address(0), keccak256(initMsg), tokenAmount
        );
    }

    function _currentDataCostToReport() internal pure override returns (uint256) {
        // at the moment chains using fee token in Anytrust mode do not charge for the data posting fees
        return 0;
    }
}
