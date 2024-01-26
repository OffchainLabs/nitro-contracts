// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

library BlobDataHashReader {
    /// @notice Gets all the data blob hashes on this transaction
    /// @dev    Will revert if called on chains that do not support the 4844 blobhash opcode
    function getDataHashes() internal view returns (bytes32[] memory) {
        bytes32[] memory dataHashes;
        // we use assembly so that we can push into a memory array without resizing
        assembly {
            // get the free mem pointer
            let dataHashesPtr := mload(0x40)
            // and keep track of the number of hashes
            let i := 0
            // prettier-ignore
            for { } 1 { } {
                let h := blobhash(i)
                // the blob hash opcode returns 0 where no blob hash exists for that index
                if iszero(h) {
                    break
                }
                // we will fill the first slot with the array size
                // so we store the hashes after that
                mstore(add(dataHashesPtr, add(mul(i, 32), 32)), h)
                i := add(i, 1)
            }
            // store the hash count
            mstore(dataHashesPtr, i)

            // update the free mem pointer
            let size := add(mul(i, 32), 32)
            mstore(0x40, add(dataHashesPtr, size))

            dataHashes := dataHashesPtr
        }
        return dataHashes;
    }
}
