// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.24;

import "../bridge/SequencerInbox.sol";
import "../bridge/DelayBuffer.sol";
import "./ISequencerInboxCreator.sol";

contract SequencerInboxCreator is ISequencerInboxCreator {
    function createSequencerInbox(
        IBridge bridge,
        ISequencerInbox.MaxTimeVariation calldata maxTimeVariation,
        IDelayBufferable.ReplenishRate calldata replenishRate,
        IDelayBufferable.Config calldata config,
        uint256 maxDataSize,
        bool isUsingFeeToken
    ) external returns (ISequencerInbox) {
        return
            new SequencerInbox(
                bridge,
                maxTimeVariation,
                replenishRate,
                config,
                maxDataSize,
                isUsingFeeToken
            );
    }
}
