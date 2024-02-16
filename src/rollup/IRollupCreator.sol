// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./Config.sol";

interface IRollupCreator {
    struct RollupParams {
        Config config;
        address[] validators;
        address nativeToken;
        bool deployFactoriesToL2;
        uint256 maxFeePerGasForRetryables;
        //// @dev The address of the batch poster, not used when set to zero address
        address[] batchPosters;
        address batchPosterManager;
        uint256 maxDataSize;
    }
}
