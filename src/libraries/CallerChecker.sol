// Copyright 2021-2024, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

library CallerChecker {
    /**
     * @notice A EIP-7702 safe check to ensure the caller is the origin and is codeless
     * @return bool true if the caller is the origin and is codeless, false otherwise
     * @dev    If the caller is the origin and is codeless, then msg.data is guaranteed to be same as tx.data
     *         It also mean the caller would not be able to call a contract multiple times with the same transaction
     */
    function isCallerCodelessOrigin() internal view returns (bool) {
        // solhint-disable-next-line avoid-tx-origin
        return msg.sender == tx.origin && msg.sender.code.length == 0;
    }
}
