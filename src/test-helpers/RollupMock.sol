// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.9;

contract RollupMock {
    event WithdrawTriggered();
    event ZombieTriggered();

    address public owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function withdrawStakerFunds() external returns (uint256) {
        emit WithdrawTriggered();
        return 0;
    }

    function removeOldZombies(
        uint256 /* startIndex */
    ) external {
        emit ZombieTriggered();
    }
}
