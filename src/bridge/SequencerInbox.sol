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
    RollupNotChanged,
    EmptyBatchData,
    InvalidHeaderFlag
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
    bytes1 public constant DATA_BLOB_HEADER_FLAG = 0x40;

    /// @inheritdoc ISequencerInbox
    bytes1 public constant DAS_MESSAGE_HEADER_FLAG = 0x80;

    /// @inheritdoc ISequencerInbox
    bytes1 public constant TREE_DAS_MESSAGE_HEADER_FLAG = 0x08;

    /// @inheritdoc ISequencerInbox
    bytes1 public constant BROTLI_MESSAGE_HEADER_FLAG = 0x00;

    /// @inheritdoc ISequencerInbox
    bytes1 public constant ZERO_HEAVY_MESSAGE_HEADER_FLAG = 0x20;

    IOwnable public rollup;
    mapping(address => bool) public isBatchPoster;
    // see ISequencerInbox.MaxTimeVariation
    uint64 internal immutable delayBlocks;
    uint64 internal immutable futureBlocks;
    uint64 internal immutable delaySeconds;
    uint64 internal immutable futureSeconds;

    mapping(bytes32 => DasKeySetInfo) public dasKeySetInfo;

    modifier onlyRollupOwner() {
        if (msg.sender != rollup.owner()) revert NotOwner(msg.sender, rollup.owner());
        _;
    }

    mapping(address => bool) public isSequencer;
    IDataHashReader immutable dataHashReader;
    IBlobBasefeeReader immutable blobBasefeeReader;

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
            if (blobBasefeeReader_ == IBlobBasefeeReader(address(0)))
                revert InitParamZero("BlobBasefeeReader");
        }
        dataHashReader = dataHashReader_;
        blobBasefeeReader = blobBasefeeReader_;
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
        (
            uint64 delayBlocks_,
            uint64 futureBlocks_,
            uint64 delaySeconds_,
            uint64 futureSeconds_
        ) = maxTimeVariationInternal();
        if (block.timestamp > delaySeconds_) {
            bounds.minTimestamp = uint64(block.timestamp) - delaySeconds_;
        }
        bounds.maxTimestamp = uint64(block.timestamp) + futureSeconds_;
        if (block.number > delayBlocks_) {
            bounds.minBlockNumber = uint64(block.number) - delayBlocks_;
        }
        bounds.maxBlockNumber = uint64(block.number) + futureBlocks_;
        return bounds;
    }

    function maxTimeVariation() public view returns (ISequencerInbox.MaxTimeVariation memory) {
        (
            uint64 delayBlocks_,
            uint64 futureBlocks_,
            uint64 delaySeconds_,
            uint64 futureSeconds_
        ) = maxTimeVariationInternal();

        return
            ISequencerInbox.MaxTimeVariation({
                delayBlocks: delayBlocks_,
                futureBlocks: futureBlocks_,
                delaySeconds: delaySeconds_,
                futureSeconds: futureSeconds_
            });
    }

    function maxTimeVariationInternal()
        internal
        view
        returns (
            uint64,
            uint64,
            uint64,
            uint64
        )
    {
        if (_chainIdChanged()) {
            return (1, 1, 1, 1);
        } else {
            return (delayBlocks, futureBlocks, delaySeconds, futureSeconds);
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
        (uint256 delayBlocks_, , uint256 delaySeconds_, ) = maxTimeVariationInternal();
        // Can only force-include after the Sequencer-only window has expired.
        if (l1BlockAndTime[0] + delayBlocks_ >= block.number) revert ForceIncludeBlockTooSoon();
        if (l1BlockAndTime[1] + delaySeconds_ >= block.timestamp) revert ForceIncludeTimeTooSoon();

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

        bridge.enqueueSequencerMessage(
            dataHash,
            _totalDelayedMessagesRead,
            prevSeqMsgCount,
            newSeqMsgCount,
            timeBounds,
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
        (bytes32 dataHash, IBridge.TimeBounds memory timeBounds) = formCallDataHash(
            data,
            afterDelayedMessagesRead
        );

        (uint256 seqMessageIndex, , , ) = bridge.enqueueSequencerMessage(
            dataHash,
            afterDelayedMessagesRead,
            prevMessageCount,
            newMessageCount,
            timeBounds,
            IBridge.BatchDataLocation.TxInput
        );

        // ~uint256(0) is type(uint256).max, but ever so slightly cheaper
        if (seqMessageIndex != sequenceNumber && sequenceNumber != ~uint256(0)) {
            revert BadSequencerNumber(seqMessageIndex, sequenceNumber);
        }

        // submit a batch spending report to refund the entity that produced the batch data
        submitBatchSpendingReport(dataHash, seqMessageIndex, block.basefee);
    }

    function addSequencerL2BatchFromBlob(
        uint256 sequenceNumber,
        uint256 afterDelayedMessagesRead,
        IGasRefunder gasRefunder,
        uint256 prevMessageCount,
        uint256 newMessageCount
    ) external refundsGas(gasRefunder) {
        if (!isBatchPoster[msg.sender]) revert NotBatchPoster();
        (bytes32 dataHash, IBridge.TimeBounds memory timeBounds) = formBlobDataHash(
            afterDelayedMessagesRead
        );

        (uint256 seqMessageIndex, , , ) = bridge.enqueueSequencerMessage(
            dataHash,
            afterDelayedMessagesRead,
            prevMessageCount,
            newMessageCount,
            timeBounds,
            IBridge.BatchDataLocation.Blob
        );

        // ~uint256(0) is type(uint256).max, but ever so slightly cheaper
        if (seqMessageIndex != sequenceNumber && sequenceNumber != ~uint256(0)) {
            revert BadSequencerNumber(seqMessageIndex, sequenceNumber);
        }

        // blobs are currently not supported on host arbitrum chains, when support is added it may
        // consume gas in a different way to L1, so explicitly block host arb chains so that if support for blobs
        // on arb is added it will need to explicitly turned on in the sequencer inbox
        if (hostChainIsArbitrum) revert DataBlobsNotSupported();

        // submit a batch spending report to refund the entity that produced the blob batch data
        uint256 blobBasefee = blobBasefeeReader.getBlobBaseFee();
        submitBatchSpendingReport(dataHash, seqMessageIndex, blobBasefee);
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
        (bytes32 dataHash, IBridge.TimeBounds memory timeBounds) = formCallDataHash(
            data,
            afterDelayedMessagesRead
        );

        (uint256 seqMessageIndex, , , ) = bridge.enqueueSequencerMessage(
            dataHash,
            afterDelayedMessagesRead,
            prevMessageCount,
            newMessageCount,
            timeBounds,
            IBridge.BatchDataLocation.SeparateBatchEvent
        );

        // ~uint256(0) is type(uint256).max, but ever so slightly cheaper
        if (seqMessageIndex != sequenceNumber && sequenceNumber != ~uint256(0)) {
            revert BadSequencerNumber(seqMessageIndex, sequenceNumber);
        }

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

    /// @dev    Form a hash for a sequencer message with no batch data
    /// @param  afterDelayedMessagesRead The delayed messages count read up to
    /// @return The data hash
    /// @return The timebounds within which the message should be processed
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

    /// @dev    Since the data is supplied from calldata, the batch poster can choose the data type
    ///         We need to ensure that this data cannot cause a collision with data supplied via another method (eg blobs)
    ///         therefore we restrict which flags can be provided as a header in this field
    ///         This also safe guards unused flags for future use, as we know they would have been disallowed up until this point
    /// @param  headerByte The first byte in the calldata
    function isValidCallDataFlag(bytes1 headerByte) internal pure returns (bool) {
        return
            headerByte == BROTLI_MESSAGE_HEADER_FLAG ||
            headerByte == DAS_MESSAGE_HEADER_FLAG ||
            (headerByte == (DAS_MESSAGE_HEADER_FLAG | TREE_DAS_MESSAGE_HEADER_FLAG)) ||
            headerByte == ZERO_HEAVY_MESSAGE_HEADER_FLAG;
    }

    /// @dev    Form a hash of the data taken from the calldata
    /// @param  data The calldata to be hashed
    /// @param  afterDelayedMessagesRead The delayed messages count read up to
    /// @return The data hash
    /// @return The timebounds within which the message should be processed
    function formCallDataHash(bytes calldata data, uint256 afterDelayedMessagesRead)
        internal
        view
        returns (bytes32, IBridge.TimeBounds memory)
    {
        uint256 fullDataLen = HEADER_LENGTH + data.length;
        if (fullDataLen > maxDataSize) revert DataTooLarge(fullDataLen, maxDataSize);

        (bytes memory header, IBridge.TimeBounds memory timeBounds) = packHeader(
            afterDelayedMessagesRead
        );

        // the batch poster is allowed to submit an empty batch, they can use this to progress the
        // delayed inbox without providing extra batch data
        if (data.length > 0) {
            // The first data byte cannot be the same as any that have been set via other methods (eg 4844 blob header) as this
            // would allow the supplier of the data to spoof an incorrect 4844 data batch
            if (!isValidCallDataFlag(data[0])) revert InvalidHeaderFlag(data[0]);

            // the first byte is used to identify the type of batch data
            // das batches expect to have the type byte set, followed by the keyset (so they should have at least 33 bytes)
            // if invalid data is supplied here the state transition function will process it as an empty block
            // however we can provide a nice additional check here for the batch poster
            if (data[0] & DAS_MESSAGE_HEADER_FLAG != 0 && data.length >= 33) {
                // we skip the first byte, then read the next 32 bytes for the keyset
                bytes32 dasKeysetHash = bytes32(data[1:33]);
                if (!dasKeySetInfo[dasKeysetHash].isValidKeyset) revert NoSuchKeyset(dasKeysetHash);
            }
        }
        return (keccak256(bytes.concat(header, data)), timeBounds);
    }

    /// @dev   Form a hash of the data being provided in 4844 data blobs
    /// @param afterDelayedMessagesRead The delayed messages count read up to
    /// @return The data hash
    /// @return The timebounds within which the message should be processed
    function formBlobDataHash(uint256 afterDelayedMessagesRead)
        internal
        view
        returns (bytes32, IBridge.TimeBounds memory)
    {
        bytes32[] memory dataHashes = dataHashReader.getDataHashes();
        if (dataHashes.length == 0) revert MissingDataHashes();

        (bytes memory header, IBridge.TimeBounds memory timeBounds) = packHeader(
            afterDelayedMessagesRead
        );

        return (
            keccak256(bytes.concat(header, DATA_BLOB_HEADER_FLAG, abi.encodePacked(dataHashes))),
            timeBounds
        );
    }

    /// @dev   Submit a batch spending report message so that the batch poster can be reimbursed on the rollup
    /// @param dataHash The hash of the message the spending report is being submitted for
    /// @param seqMessageIndex The index of the message to submit the spending report for
    /// @param gasPrice The gas price that was paid for the data (standard gas or data gas)
    function submitBatchSpendingReport(
        bytes32 dataHash,
        uint256 seqMessageIndex,
        uint256 gasPrice
    ) internal {
        bytes memory spendingReportMsg;
        address batchPoster = tx.origin;

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
                gasPrice,
                uint64(extraGas)
            );
        } else {
            spendingReportMsg = abi.encodePacked(
                block.timestamp,
                batchPoster,
                dataHash,
                seqMessageIndex,
                gasPrice
            );
        }

        uint256 msgNum = bridge.submitBatchSpendingReport(
            batchPoster,
            keccak256(spendingReportMsg)
        );
        // this is the same event used by Inbox.sol after including a message to the delayed message accumulator
        emit InboxMessageDelivered(msgNum, spendingReportMsg);
    }

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
