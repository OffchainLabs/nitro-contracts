// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "../bridge/SequencerInbox.sol";
import "../bridge/IEthBridge.sol";
import {INITIALIZATION_MSG_TYPE} from "../libraries/MessageTypes.sol";

contract SequencerInboxStub is SequencerInbox {
    constructor(
        IBridge bridge_,
        address sequencer_,
        ISequencerInbox.MaxTimeVariation memory maxTimeVariation_,
        uint256 maxDataSize_,
        IDataHashReader dataHashReader_,
        IBlobBasefeeReader blobBasefeeReader_
    )
        SequencerInbox(
            bridge_,
            maxTimeVariation_,
            maxDataSize_,
            dataHashReader_,
            blobBasefeeReader_
        )
    {
        isBatchPoster[sequencer_] = true;
    }

    function addInitMessage(uint256 chainId) external {
        bytes memory initMsg = abi.encodePacked(chainId);
        uint256 num = IEthBridge(address(bridge)).enqueueDelayedMessage(
            INITIALIZATION_MSG_TYPE,
            address(0),
            keccak256(initMsg)
        );
        require(num == 0, "ALREADY_DELAYED_INIT");
        emit InboxMessageDelivered(num, initMsg);
        (bytes32 dataHash, ICommon.TimeBounds memory timeBounds) = formEmptyDataHash(1);
        addSequencerL2BatchImpl(0, dataHash, timeBounds, 1, 0, 0, ICommon.BatchDataLocation.NoData);
    }

    function getTimeBounds() internal view override returns (ICommon.TimeBounds memory bounds) {
        this; // silence warning about function not being view
        return bounds;
    }
}
