// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "../bridge/ISequencerInbox.sol";
import "../bridge/IDelayBufferable.sol";
import "../libraries/IReader4844.sol";

interface ISequencerInboxCreator {
    function createSequencerInbox(
        IBridge bridge,
        ISequencerInbox.MaxTimeVariation calldata maxTimeVariation,
        IDelayBufferable.ReplenishRate memory replenishRate_,
        IDelayBufferable.DelayConfig memory delayConfig_,
        uint256 maxDataSize,
        IReader4844 reader4844,
        bool isUsingFeeToken
    ) external returns (ISequencerInbox);
}
