// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "../bridge/IBridge.sol";

/**
 * Simple contract for testing bridge calls which include calldata
 */
contract EthVault {
    uint256 public version = 0;
    address public outboxCaller;

    function setVersion(
        uint256 _version
    ) external payable {
        version = _version;
        IBridge bridge = IBridge(msg.sender);
        outboxCaller = bridge.activeOutbox();
    }

    function justRevert() external payable {
        revert("bye");
    }
}
