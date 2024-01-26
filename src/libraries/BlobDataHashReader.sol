// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

// solhint-disable-next-line compiler-version
pragma solidity ^0.8.24;

library BlobDataHashReader {
    /// @notice Gets all the data blob hashes on this transaction
    /// @dev    Will revert if called on chains that do not support the 4844 blobhash opcode
    function getDataHashes() internal view returns(bytes32[] memory) {
        // we use assembly so that we can efficiently push into a memory arracy
        assembly {
            let i := 0
            for { } true { }
            {
                let h := blobhash(i)
                // the blob hash opcode returns 0 where no blob hash exists for that index
                if iszero(h) { break }

                // store the blob hash
                mstore(add(mul(i, 32), 64), h)

                // set the number of hashes
                i := add(i, 1)
            }
            // format an return an array of the data blob hashes
            mstore(0, 32)
            mstore(32, i)
            return(0, add(mul(i, 32), 64))
        }
    }
}