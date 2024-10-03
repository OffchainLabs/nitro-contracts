// Copyright 2021-2024, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

library CallerChecker {
    /**
     * @notice A EIP-7702 safe check for top level caller, used to ensure the calldata is available in the tx
     * @return bool true if the caller is a top level caller, false otherwise
     */
    function isCallerTopLevel() internal view returns (bool) {
        // solhint-disable-next-line avoid-tx-origin
        return msg.sender == tx.origin && msg.sender.code.length == 0;
    }
}
