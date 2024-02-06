// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "../bridge/ISequencerInbox.sol";
import "../libraries/IReader4844.sol";

interface ISequencerInboxCreator {
    function createSequencerInbox(
        IBridge bridge,
        ISequencerInbox.MaxTimeVariation calldata maxTimeVariation,
        ISequencerInbox.ReplenishRate memory replenishRate_,
        ISequencerInbox.DelaySettings memory delaySettings_,
        uint256 maxDataSize,
        IReader4844 reader4844,
        bool isUsingFeeToken
    ) external returns (ISequencerInbox);
}
