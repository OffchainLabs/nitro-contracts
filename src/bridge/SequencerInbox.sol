// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import {
    AlreadyInit,
    HadZeroInit,
    NotOrigin,
    DataTooLarge,
    NotRollup,
    DelayedBackwards,
    DelayedTooFar,
    ForceIncludeBlockTooSoon,
    ForceIncludeTimeTooSoon,
    IncorrectMessagePreimage,
    NotBatchPoster,
    BadSequencerNumber,
    DataNotAuthenticated,
    AlreadyValidDASKeyset,
    NoSuchKeyset,
    NotForked,
    DataBlobsNotSupported,
    InitParamZero,
    MissingDataHashes,
    InvalidBlobMetadata,
    NotOwner,
    RollupNotChanged
} from "../libraries/Error.sol";
import "./IBridge.sol";
import "./IInboxBase.sol";
import "./ISequencerInbox.sol";
import "../rollup/IRollupLogic.sol";
import "./Messages.sol";
import "../precompiles/ArbGasInfo.sol";
import "../precompiles/ArbSys.sol";

import {L1MessageType_batchPostingReport} from "../libraries/MessageTypes.sol";
import {GasRefundEnabled, IGasRefunder} from "../libraries/IGasRefunder.sol";
import "../libraries/ArbitrumChecker.sol";

/**
 * @title Accepts batches from the sequencer and adds them to the rollup inbox.
 * @notice Contains the inbox accumulator which is the ordering of all data and transactions to be processed by the rollup.
 * As part of submitting a batch the sequencer is also expected to include items enqueued
 * in the delayed inbox (Bridge.sol). If items in the delayed inbox are not included by a
 * sequencer within a time limit they can be force included into the rollup inbox by anyone.
 */
contract SequencerInbox is GasRefundEnabled, ISequencerInbox {
    IBridge public immutable bridge;

    /// @inheritdoc ISequencerInbox
    uint256 public constant HEADER_LENGTH = 40;

    /// @inheritdoc ISequencerInbox
    bytes1 public constant DATA_AUTHENTICATED_FLAG = 0x40;

    /// @inheritdoc ISequencerInbox
    bytes1 public constant DATA_BLOB_HEADER_FLAG = 0x10;

    /// @inheritdoc ISequencerInbox
    bytes1 public constant DAS_MESSAGE_HEADER_FLAG = 0x80;

    IOwnable public rollup;
    mapping(address => bool) public isBatchPoster;
    // see ISequencerInbox.MaxTimeVariation
    uint256 internal immutable delayBlocks;
    uint256 internal immutable futureBlocks;
    uint256 internal immutable delaySeconds;
    uint256 internal immutable futureSeconds;

    mapping(bytes32 => DasKeySetInfo) public dasKeySetInfo;

    modifier onlyRollupOwner() {
        if (msg.sender != rollup.owner()) revert NotOwner(msg.sender, address(rollup));
        _;
    }

    mapping(address => bool) public isSequencer;
    IDataHashReader dataHashReader;
    IBlobBasefeeReader blobBasefeeReader;

    // On L1 this should be set to 117964: 90% of Geth's 128KB tx size limit, leaving ~13KB for proving
    uint256 public immutable maxDataSize;
    uint256 internal immutable deployTimeChainId = block.chainid;
    // If the chain this SequencerInbox is deployed on is an Arbitrum chain.
    bool internal immutable hostChainIsArbitrum = ArbitrumChecker.runningOnArbitrum();

    constructor(
        IBridge bridge_,
        ISequencerInbox.MaxTimeVariation memory maxTimeVariation_,
        uint256 _maxDataSize,
        IDataHashReader dataHashReader_,
        IBlobBasefeeReader blobBasefeeReader_
    ) {
        if (bridge_ == IBridge(address(0))) revert HadZeroInit();
        bridge = bridge_;
        rollup = bridge_.rollup();
        if (address(rollup) == address(0)) revert RollupNotChanged();
        delayBlocks = maxTimeVariation_.delayBlocks;
        futureBlocks = maxTimeVariation_.futureBlocks;
        delaySeconds = maxTimeVariation_.delaySeconds;
        futureSeconds = maxTimeVariation_.futureSeconds;
        maxDataSize = _maxDataSize;
        if (hostChainIsArbitrum) {
            if (dataHashReader_ != IDataHashReader(address(0))) revert DataBlobsNotSupported();
            if (blobBasefeeReader_ != IBlobBasefeeReader(address(0)))
                revert DataBlobsNotSupported();
        } else {
            if (dataHashReader_ == IDataHashReader(address(0)))
                revert InitParamZero("DataHashReader");
            dataHashReader = dataHashReader_;
            if (blobBasefeeReader_ == IBlobBasefeeReader(address(0)))
                revert InitParamZero("BlobBasefeeReader");
            blobBasefeeReader = blobBasefeeReader_;
        }
    }

    function _chainIdChanged() internal view returns (bool) {
        return deployTimeChainId != block.chainid;
    }

    /// @inheritdoc ISequencerInbox
    function updateRollupAddress() external {
        if (msg.sender != IOwnable(rollup).owner())
            revert NotOwner(msg.sender, IOwnable(rollup).owner());
        IOwnable newRollup = bridge.rollup();
        if (rollup == newRollup) revert RollupNotChanged();
        rollup = newRollup;
    }

    /// @inheritdoc ISequencerInbox
    function totalDelayedMessagesRead() public view returns (uint256) {
        return bridge.totalDelayedMessagesRead();
    }

    function getTimeBounds() internal view virtual returns (IBridge.TimeBounds memory) {
        IBridge.TimeBounds memory bounds;
        ISequencerInbox.MaxTimeVariation memory maxTimeVariation_ = maxTimeVariation();
        if (block.timestamp > maxTimeVariation_.delaySeconds) {
            bounds.minTimestamp = uint64(block.timestamp - maxTimeVariation_.delaySeconds);
        }
        bounds.maxTimestamp = uint64(block.timestamp + maxTimeVariation_.futureSeconds);
        if (block.number > maxTimeVariation_.delayBlocks) {
            bounds.minBlockNumber = uint64(block.number - maxTimeVariation_.delayBlocks);
        }
        bounds.maxBlockNumber = uint64(block.number + maxTimeVariation_.futureBlocks);
        return bounds;
    }

    function maxTimeVariation() public view returns (ISequencerInbox.MaxTimeVariation memory) {
        if (_chainIdChanged()) {
            return
                ISequencerInbox.MaxTimeVariation({
                    delayBlocks: 1,
                    futureBlocks: 1,
                    delaySeconds: 1,
                    futureSeconds: 1
                });
        } else {
            return
                ISequencerInbox.MaxTimeVariation({
                    delayBlocks: delayBlocks,
                    futureBlocks: futureBlocks,
                    delaySeconds: delaySeconds,
                    futureSeconds: futureSeconds
                });
        }
    }

    /// @inheritdoc ISequencerInbox
    function forceInclusion(
        uint256 _totalDelayedMessagesRead,
        uint8 kind,
        uint64[2] calldata l1BlockAndTime,
        uint256 baseFeeL1,
        address sender,
        bytes32 messageDataHash
    ) external {
        if (_totalDelayedMessagesRead <= totalDelayedMessagesRead()) revert DelayedBackwards();
        bytes32 messageHash = Messages.messageHash(
            kind,
            sender,
            l1BlockAndTime[0],
            l1BlockAndTime[1],
            _totalDelayedMessagesRead - 1,
            baseFeeL1,
            messageDataHash
        );
        ISequencerInbox.MaxTimeVariation memory maxTimeVariation_ = maxTimeVariation();
        // Can only force-include after the Sequencer-only window has expired.
        if (l1BlockAndTime[0] + maxTimeVariation_.delayBlocks >= block.number)
            revert ForceIncludeBlockTooSoon();
        if (l1BlockAndTime[1] + maxTimeVariation_.delaySeconds >= block.timestamp)
            revert ForceIncludeTimeTooSoon();

        // Verify that message hash represents the last message sequence of delayed message to be included
        {
            bytes32 prevDelayedAcc = 0;
            if (_totalDelayedMessagesRead > 1) {
                prevDelayedAcc = bridge.delayedInboxAccs(_totalDelayedMessagesRead - 2);
            }
            if (
                bridge.delayedInboxAccs(_totalDelayedMessagesRead - 1) !=
                Messages.accumulateInboxMessage(prevDelayedAcc, messageHash)
            ) revert IncorrectMessagePreimage();
        }

        (bytes32 dataHash, IBridge.TimeBounds memory timeBounds) = formEmptyDataHash(
            _totalDelayedMessagesRead
        );
        uint256 prevSeqMsgCount = bridge.sequencerReportedSubMessageCount();
        uint256 newSeqMsgCount = prevSeqMsgCount +
            _totalDelayedMessagesRead -
            totalDelayedMessagesRead();

        addSequencerL2BatchImpl(
            type(uint256).max,
            dataHash,
            timeBounds,
            _totalDelayedMessagesRead,
            prevSeqMsgCount,
            newSeqMsgCount,
            IBridge.BatchDataLocation.NoData
        );
    }

    function addSequencerL2BatchFromOrigin(
        uint256 sequenceNumber,
        bytes calldata data,
        uint256 afterDelayedMessagesRead,
        IGasRefunder gasRefunder,
        uint256 prevMessageCount,
        uint256 newMessageCount
    ) external refundsGas(gasRefunder) {
        // solhint-disable-next-line avoid-tx-origin
        if (msg.sender != tx.origin) revert NotOrigin();
        if (!isBatchPoster[msg.sender]) revert NotBatchPoster();
        (bytes32 dataHash, IBridge.TimeBounds memory timeBounds) = formDataHash(
            data,
            afterDelayedMessagesRead,
            IBridge.BatchDataLocation.TxInput
        );
        addSequencerL2BatchImpl(
            sequenceNumber,
            dataHash,
            timeBounds,
            afterDelayedMessagesRead,
            prevMessageCount,
            newMessageCount,
            IBridge.BatchDataLocation.TxInput
        );
    }

    function addSequencerL2BatchFromBlob(
        uint256 sequenceNumber,
        // CHRIS: TODO: this isnt strictly necessary atm, but I'll leave it here until we decide if we want to specify blob indices
        bytes calldata data,
        uint256 afterDelayedMessagesRead,
        IGasRefunder gasRefunder,
        uint256 prevMessageCount,
        uint256 newMessageCount
    ) external refundsGas(gasRefunder) {
        if (!isBatchPoster[msg.sender]) revert NotBatchPoster();
        (bytes32 dataHash, IBridge.TimeBounds memory timeBounds) = formDataHash(
            data,
            afterDelayedMessagesRead,
            IBridge.BatchDataLocation.Blob
        );
        addSequencerL2BatchImpl(
            sequenceNumber,
            dataHash,
            timeBounds,
            afterDelayedMessagesRead,
            prevMessageCount,
            newMessageCount,
            IBridge.BatchDataLocation.Blob
        );
        emit SequencerBatchData(sequenceNumber, data);
    }

    function addSequencerL2Batch(
        uint256 sequenceNumber,
        bytes calldata data,
        uint256 afterDelayedMessagesRead,
        IGasRefunder gasRefunder,
        uint256 prevMessageCount,
        uint256 newMessageCount
    ) external override refundsGas(gasRefunder) {
        if (!isBatchPoster[msg.sender] && msg.sender != address(rollup)) revert NotBatchPoster();
        (bytes32 dataHash, IBridge.TimeBounds memory timeBounds) = formDataHash(
            data,
            afterDelayedMessagesRead,
            IBridge.BatchDataLocation.SeparateBatchEvent
        );
        addSequencerL2BatchImpl(
            sequenceNumber,
            dataHash,
            timeBounds,
            afterDelayedMessagesRead,
            prevMessageCount,
            newMessageCount,
            IBridge.BatchDataLocation.SeparateBatchEvent
        );
        emit SequencerBatchData(sequenceNumber, data);
    }

    function packHeader(uint256 afterDelayedMessagesRead)
        internal
        view
        returns (bytes memory, IBridge.TimeBounds memory)
    {
        IBridge.TimeBounds memory timeBounds = getTimeBounds();
        bytes memory header = abi.encodePacked(
            timeBounds.minTimestamp,
            timeBounds.maxTimestamp,
            timeBounds.minBlockNumber,
            timeBounds.maxBlockNumber,
            uint64(afterDelayedMessagesRead)
        );
        // This must always be true from the packed encoding
        assert(header.length == HEADER_LENGTH);
        return (header, timeBounds);
    }

    function formEmptyDataHash(uint256 afterDelayedMessagesRead)
        internal
        view
        returns (bytes32, IBridge.TimeBounds memory)
    {
        (bytes memory header, IBridge.TimeBounds memory timeBounds) = packHeader(
            afterDelayedMessagesRead
        );
        return (keccak256(header), timeBounds);
    }

    function formDataHash(
        bytes calldata data,
        uint256 afterDelayedMessagesRead,
        IBridge.BatchDataLocation dataLocation
    ) internal view returns (bytes32, IBridge.TimeBounds memory) {
        uint256 fullDataLen = HEADER_LENGTH + data.length;
        if (fullDataLen > maxDataSize) revert DataTooLarge(fullDataLen, maxDataSize);
        if (data.length > 0 && (data[0] & DATA_AUTHENTICATED_FLAG) == DATA_AUTHENTICATED_FLAG) {
            revert DataNotAuthenticated();
        }

        (bytes memory header, IBridge.TimeBounds memory timeBounds) = packHeader(
            afterDelayedMessagesRead
        );
        if (dataLocation == IBridge.BatchDataLocation.Blob) {
            bytes32[] memory dataHashes = dataHashReader.getDataHashes();
            if (dataHashes.length == 0) revert MissingDataHashes();
            if (data.length != 1) revert InvalidBlobMetadata();
            if (data[0] & DATA_BLOB_HEADER_FLAG == 0) revert InvalidBlobMetadata();

            return (
                keccak256(bytes.concat(header, data, abi.encodePacked(dataHashes))),
                timeBounds
            );
        } else {
            // the first byte is used to identify the type of batch data
            // das batches expect to have the type byte set, followed by the keyset (so they should have at least 33 bytes)
            if (data.length >= 33 && data[0] & DAS_MESSAGE_HEADER_FLAG != 0) {
                // we skip the first byte, then read the next 32 bytes for the keyset
                bytes32 dasKeysetHash = bytes32(data[1:33]);
                if (!dasKeySetInfo[dasKeysetHash].isValidKeyset) revert NoSuchKeyset(dasKeysetHash);
            }
            return (keccak256(bytes.concat(header, data)), timeBounds);
        }
    }

    function addSequencerL2BatchImpl(
        uint256 sequenceNumber,
        bytes32 dataHash,
        IBridge.TimeBounds memory timeBounds,
        uint256 afterDelayedMessagesRead,
        uint256 prevMessageCount,
        uint256 newMessageCount,
        IBridge.BatchDataLocation batchDataLocation
    ) internal returns (uint256 seqMessageIndex) {
        (seqMessageIndex, , , ) = bridge.enqueueSequencerMessage(
            dataHash,
            afterDelayedMessagesRead,
            prevMessageCount,
            newMessageCount,
            timeBounds,
            batchDataLocation
        );

        // submit a batch spending report to refund the entity that produced the batch data
        submitBatchSpendingReport(dataHash, seqMessageIndex, batchDataLocation);

        // ~uint256(0) is type(uint256).max, but ever so slightly cheaper
        if (seqMessageIndex != sequenceNumber && sequenceNumber != ~uint256(0)) {
            revert BadSequencerNumber(seqMessageIndex, sequenceNumber);
        }
    }

    function submitBatchSpendingReport(
        bytes32 dataHash,
        uint256 seqMessageIndex,
        IBridge.BatchDataLocation dataLocation
    ) internal {
        bytes memory spendingReportMsg;
        address batchPoster = tx.origin;

        if (dataLocation == IBridge.BatchDataLocation.TxInput) {
            // this msg isn't included in the current sequencer batch, but instead added to
            // the delayed messages queue that is yet to be included
            if (hostChainIsArbitrum) {
                // Include extra gas for the host chain's L1 gas charging
                uint256 l1Fees = ArbGasInfo(address(0x6c)).getCurrentTxL1GasFees();
                uint256 extraGas = l1Fees / block.basefee;
                require(extraGas <= type(uint64).max, "L1_GAS_NOT_UINT64");
                spendingReportMsg = abi.encodePacked(
                    block.timestamp,
                    batchPoster,
                    dataHash,
                    seqMessageIndex,
                    block.basefee,
                    uint64(extraGas)
                );
            } else {
                spendingReportMsg = abi.encodePacked(
                    block.timestamp,
                    batchPoster,
                    dataHash,
                    seqMessageIndex,
                    block.basefee
                );
            }
        } else if (dataLocation == IBridge.BatchDataLocation.Blob) {
            // this msg isn't included in the current sequencer batch, but instead added to
            // the delayed messages queue that is yet to be included
            uint256 blobBasefee = blobBasefeeReader.getBlobBaseFee();
            if (hostChainIsArbitrum) revert DataBlobsNotSupported();
            spendingReportMsg = abi.encodePacked(
                block.timestamp,
                batchPoster,
                dataHash,
                seqMessageIndex,
                blobBasefee
            );
        } else {
            // do nothing, we only submit spending reports for tx input and blob
            return;
        }

        uint256 msgNum = bridge.submitBatchSpendingReport(
            batchPoster,
            keccak256(spendingReportMsg)
        );
        // this is the same event used by Inbox.sol after including a message to the delayed message accumulator
        emit InboxMessageDelivered(msgNum, spendingReportMsg);
    }

    function submitBlobBatchSpendingReport(bytes32 dataHash, uint256 seqMessageIndex) internal {}

    function inboxAccs(uint256 index) external view returns (bytes32) {
        return bridge.sequencerInboxAccs(index);
    }

    function batchCount() external view returns (uint256) {
        return bridge.sequencerMessageCount();
    }

    /// @inheritdoc ISequencerInbox
    function setIsBatchPoster(address addr, bool isBatchPoster_) external onlyRollupOwner {
        isBatchPoster[addr] = isBatchPoster_;
        // we used to have OwnerFunctionCalled(0) for setting the maxTimeVariation
        // so we dont use index = 0 here, even though this is the first owner function
        // to stay compatible with legacy events
        emit OwnerFunctionCalled(1);
    }

    /// @inheritdoc ISequencerInbox
    function setValidKeyset(bytes calldata keysetBytes) external onlyRollupOwner {
        uint256 ksWord = uint256(keccak256(bytes.concat(hex"fe", keccak256(keysetBytes))));
        bytes32 ksHash = bytes32(ksWord ^ (1 << 255));
        require(keysetBytes.length < 64 * 1024, "keyset is too large");

        if (dasKeySetInfo[ksHash].isValidKeyset) revert AlreadyValidDASKeyset(ksHash);
        uint256 creationBlock = block.number;
        if (hostChainIsArbitrum) {
            creationBlock = ArbSys(address(100)).arbBlockNumber();
        }
        dasKeySetInfo[ksHash] = DasKeySetInfo({
            isValidKeyset: true,
            creationBlock: uint64(creationBlock)
        });
        emit SetValidKeyset(ksHash, keysetBytes);
        emit OwnerFunctionCalled(2);
    }

    /// @inheritdoc ISequencerInbox
    function invalidateKeysetHash(bytes32 ksHash) external onlyRollupOwner {
        if (!dasKeySetInfo[ksHash].isValidKeyset) revert NoSuchKeyset(ksHash);
        // we don't delete the block creation value since its used to fetch the SetValidKeyset
        // event efficiently. The event provides the hash preimage of the key.
        // this is still needed when syncing the chain after a keyset is invalidated.
        dasKeySetInfo[ksHash].isValidKeyset = false;
        emit InvalidateKeyset(ksHash);
        emit OwnerFunctionCalled(3);
    }

    /// @inheritdoc ISequencerInbox
    function setIsSequencer(address addr, bool isSequencer_) external onlyRollupOwner {
        isSequencer[addr] = isSequencer_;
        emit OwnerFunctionCalled(4);
    }

    function isValidKeysetHash(bytes32 ksHash) external view returns (bool) {
        return dasKeySetInfo[ksHash].isValidKeyset;
    }

    /// @inheritdoc ISequencerInbox
    function getKeysetCreationBlock(bytes32 ksHash) external view returns (uint256) {
        DasKeySetInfo memory ksInfo = dasKeySetInfo[ksHash];
        if (ksInfo.creationBlock == 0) revert NoSuchKeyset(ksHash);
        return uint256(ksInfo.creationBlock);
    }
}
