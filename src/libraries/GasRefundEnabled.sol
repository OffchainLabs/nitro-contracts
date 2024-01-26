// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.24;

import "./BlobDataHashReader.sol";
import "./IGasRefunder.sol";

abstract contract GasRefundEnabled {
    uint256 immutable gasPerBlob = 2**17;

    /// @dev this refunds the sender for execution costs of the tx
    /// calldata costs are only refunded if `msg.sender == tx.origin` to guarantee the value refunded relates to charging
    /// for the `tx.input`. this avoids a possible attack where you generate large calldata from a contract and get over-refunded
    modifier refundsGas(IGasRefunder gasRefunder, bool includeBlobCosts) {
        uint256 startGasLeft = gasleft();
        _;
        if (address(gasRefunder) != address(0)) {
            uint256 calldataSize = msg.data.length;
            uint256 calldataWords = (calldataSize + 31) / 32;
            // account for the CALLDATACOPY cost of the proxy contract, including the memory expansion cost
            startGasLeft += calldataWords * 6 + (calldataWords**2) / 512;
            // if triggered in a contract call, the spender may be overrefunded by appending dummy data to the call
            // so we check if it is a top level call, which would mean the sender paid calldata as part of tx.input
            // solhint-disable-next-line avoid-tx-origin
            if (msg.sender != tx.origin) {
                // We can't be sure if this calldata came from the top level tx,
                // so to be safe we tell the gas refunder there was no calldata.
                calldataSize = 0;
            } else {
                // for similar reasons to above we only refund blob gas when the tx.origin is the msg.sender
                // this avoids the caller being able to send blobs to other contracts and still get refunded here

                // since 4844 may not be enabled on this chain we do not want to always call the
                // blobhash or blobbasefee opcodes. We can only detect the presence of these opcodes without reverting
                // by either doing a call and checking success or providing a bool for specific code paths. We go for
                // the bool approach as it's cheaper
                if (includeBlobCosts) {
                    // add any cost for 4844 data, the data hash reader throws an error prior to 4844 being activated
                    // we do this addition here rather in the GasRefunder so that we can check the msg.sender is the tx.origin
                    bytes32[] memory dataHashes = BlobDataHashReader.getDataHashes();
                    if (dataHashes.length != 0 && block.basefee > 0) {
                        startGasLeft +=
                            (dataHashes.length * gasPerBlob * block.blobbasefee) /
                            block.basefee;
                    }
                }
            }

            gasRefunder.onGasSpent(payable(msg.sender), startGasLeft - gasleft(), calldataSize);
        }
    }
}
