// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "../precompiles/ArbSys.sol";

contract TestPendingBlkTimeAndNrAdvance {
    uint256 immutable deployedAt;
    uint256 immutable deployedAtBlock;

    constructor() {
        deployedAt = block.timestamp;
        deployedAtBlock = ArbSys(address(100)).arbBlockNumber();
    }

    function test() external {
        require(block.timestamp > deployedAt, "Time didn't advance");
        require(ArbSys(address(100)).arbBlockNumber() > deployedAtBlock, "Block didn't advance");
    }
}
