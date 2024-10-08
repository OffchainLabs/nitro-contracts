// Copyright 2021-2024, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

library CallerChecker {
    /**
     * @notice A EIP-7702 safe check to ensure the caller is a codeless origin
     * @return bool true if the caller is a codeless origin, false otherwise
     * @dev    If the caller is a codeless origin, then the calldata is guaranteed to be available in the transaction
     *         It also mean the caller would not be able to call a contract multiple times with the same transaction
     */
    function isCallerCodelessOrigin() internal view returns (bool) {
        // solhint-disable-next-line avoid-tx-origin
        return msg.sender == tx.origin && msg.sender.code.length == 0;
    }
}
