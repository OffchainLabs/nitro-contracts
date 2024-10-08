// Copyright 2021-2024, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

library CalldataChecker {
    /**
     * @notice A EIP-7702 safe check to ensure the calldata is available in the top level tx
     * @return bool true if calldata is guaranteed to be available in the top level tx
     */
    function isCalldataSameAsTx() internal view returns (bool) {
        // solhint-disable-next-line avoid-tx-origin
        return msg.sender == tx.origin && msg.sender.code.length == 0;
    }
}
