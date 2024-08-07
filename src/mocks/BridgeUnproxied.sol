// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./InboxStub.sol";
import {BadSequencerMessageNumber} from "../libraries/Error.sol";

import "../bridge/Bridge.sol";

contract BridgeUnproxied is Bridge {
    uint256 public DUMMYVAR = 0; // This is a dummy variable to disambiguous with the Bridge contract

    constructor() {
        _activeOutbox = EMPTY_ACTIVEOUTBOX;
        rollup = IOwnable(msg.sender);
    }
}
