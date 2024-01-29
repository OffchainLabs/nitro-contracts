// Copyright 2021-2024, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

struct MultiStack {
    bytes32 inactiveStackHash;
    bytes32 remainingHash;
}

library MultiStackLib {
    function hash(MultiStack memory multi, bytes32 activeStackHash, bool cothread) internal pure returns (bytes32 h) {
        if (cothread) {
            return keccak256(abi.encodePacked("Multistack:", multi.inactiveStackHash, activeStackHash, multi.remainingHash));
        } else {
            return keccak256(abi.encodePacked("Multistack:", activeStackHash, multi.inactiveStackHash, multi.remainingHash));
        }
    }
}
