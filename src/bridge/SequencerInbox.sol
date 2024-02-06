// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import {
    AlreadyInit,
    HadZeroInit,
    NotOrigin,
    DataTooLarge,
    SyncProofExpired,
    NotRollup,
    DelayedBackwards,
    DelayedTooFar,
    DelayedNotFarEnough,
    ForceIncludeBlockTooSoon,
    ForceIncludeTimeTooSoon,
    IncorrectMessagePreimage,
    NotBatchPoster,
    BadSequencerNumber,
    DataNotAuthenticated,
    AlreadyValidDASKeyset,
    NoSuchKeyset,
    NotForked,
    NotBatchPosterManager,
    RollupNotChanged,
    DataBlobsNotSupported,
    InitParamZero,
    MissingDataHashes,
    InvalidBlobMetadata,
    InvalidDelayedAccPreimage,
    InvalidInboxAccPreimage,
    NotOwner,
    RollupNotChanged,
    EmptyBatchData,
    InvalidHeaderFlag,
    NativeTokenMismatch,
    Deprecated
} from "../libraries/Error.sol";
import "./IBridge.sol";
import "./IInboxBase.sol";
import "./ISequencerInbox.sol";
import "../rollup/IRollupLogic.sol";
import "./Messages.sol";
import "../precompiles/ArbGasInfo.sol";
import "../precompiles/ArbSys.sol";
import "../libraries/IReader4844.sol";

import {L1MessageType_batchPostingReport} from "../libraries/MessageTypes.sol";
import "../libraries/DelegateCallAware.sol";
import {IGasRefunder} from "../libraries/IGasRefunder.sol";
import {GasRefundEnabled} from "../libraries/GasRefundEnabled.sol";
import "../libraries/ArbitrumChecker.sol";
import {IERC20Bridge} from "./IERC20Bridge.sol";

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
    bytes1 public constant DATA_BLOB_HEADER_FLAG = DATA_AUTHENTICATED_FLAG | 0x10;

    /// @inheritdoc ISequencerInbox
    bytes1 public constant DAS_MESSAGE_HEADER_FLAG = 0x80;

    /// @inheritdoc ISequencerInbox
    bytes1 public constant TREE_DAS_MESSAGE_HEADER_FLAG = 0x08;

    /// @inheritdoc ISequencerInbox
    bytes1 public constant BROTLI_MESSAGE_HEADER_FLAG = 0x00;

    /// @inheritdoc ISequencerInbox
    bytes1 public constant ZERO_HEAVY_MESSAGE_HEADER_FLAG = 0x20;

    // GAS_PER_BLOB from EIP-4844
    uint256 internal constant GAS_PER_BLOB = 1 << 17;

    IOwnable public rollup;

    mapping(address => BatchPosterData) public batchPosterData;

    /// @inheritdoc ISequencerInbox
    DelayData public delayData;

    /// @inheritdoc ISequencerInbox
    SyncMarker public syncMarker;

    /// @notice The last sequenced and proven delay message
    DelayMsgData public delayMsgLastProven;

    /// @notice The round off errors due to delay buffer replenishment, used for internal accounting.
    ReplenishPool internal replenishPool;

    // see ISequencerInbox.MaxTimeVariation
    uint256 internal immutable maxTimeVariationDelayBlocks;
    uint256 internal immutable maxTimeVariationFutureBlocks;
    uint256 internal immutable maxTimeVariationDelaySeconds;
    uint256 internal immutable maxTimeVariationFutureSeconds;

    // see ISequencerInbox.ReplenishRate
    uint256 internal immutable replenishSecondsPerPeriod;
    uint256 internal immutable replenishBlocksPerPeriod;
    uint256 internal immutable replenishPeriodSeconds;
    uint256 internal immutable replenishPeriodBlocks;

    // see ISequencerInbox.DelaySettings
    uint256 internal immutable delayThresholdSeconds;
    uint256 internal immutable delayThresholdBlocks;
    uint256 internal immutable maxDelayBufferSeconds;
    uint256 internal immutable maxDelayBufferBlocks;

    mapping(bytes32 => DasKeySetInfo) public dasKeySetInfo;

    modifier onlyRollupOwner() {
        if (msg.sender != rollup.owner()) revert NotOwner(msg.sender, rollup.owner());
        _;
    }

    modifier onlyRollupOwnerOrBatchPosterManager() {
        if (msg.sender != rollup.owner() && msg.sender != batchPosterManager) {
            revert NotBatchPosterManager(msg.sender);
        }
        _;
    }

    mapping(address => bool) public isSequencer;
    IReader4844 public immutable reader4844;

    /// @inheritdoc ISequencerInbox
    address public batchPosterManager;

    // On L1 this should be set to 117964: 90% of Geth's 128KB tx size limit, leaving ~13KB for proving
    uint256 public immutable maxDataSize;
    uint256 internal immutable deployTimeChainId = block.chainid;
    // If the chain this SequencerInbox is deployed on is an Arbitrum chain.
    bool internal immutable hostChainIsArbitrum = ArbitrumChecker.runningOnArbitrum();
    // True if the chain this SequencerInbox is deployed on uses custom fee token
    bool public immutable isUsingFeeToken;

    constructor(
        IBridge bridge_,
        MaxTimeVariation memory maxTimeVariation_,
        ReplenishRate memory replenishRate_,
        DelaySettings memory delaySettings_,
        uint256 _maxDataSize,
        IReader4844 reader4844_,
        bool _isUsingFeeToken
    ) {
        if (bridge_ == IBridge(address(0))) revert HadZeroInit();
        bridge = bridge_;
        rollup = bridge_.rollup();
        if (address(rollup) == address(0)) revert RollupNotChanged();
        maxTimeVariationDelayBlocks = maxTimeVariation_.delayBlocks;
        maxTimeVariationFutureBlocks = maxTimeVariation_.futureBlocks;
        maxTimeVariationDelaySeconds = maxTimeVariation_.delaySeconds;
        maxTimeVariationFutureSeconds = maxTimeVariation_.futureSeconds;
        replenishSecondsPerPeriod = replenishRate_.secondsPerPeriod;
        replenishBlocksPerPeriod = replenishRate_.blocksPerPeriod;
        replenishPeriodSeconds = replenishRate_.periodSeconds;
        replenishPeriodBlocks = replenishRate_.periodBlocks;
        maxDataSize = _maxDataSize;
        if (hostChainIsArbitrum) {
            if (reader4844_ != IReader4844(address(0))) revert DataBlobsNotSupported();
        } else {
            if (reader4844_ == IReader4844(address(0))) revert InitParamZero("Reader4844");
        }
        reader4844 = reader4844_;
        isUsingFeeToken = _isUsingFeeToken;
        delayThresholdBlocks = delaySettings_.delayThresholdBlocks;
        delayThresholdSeconds = delaySettings_.delayThresholdSeconds;
        maxDelayBufferBlocks = delaySettings_.maxDelayBufferBlocks;
        maxDelayBufferSeconds = delaySettings_.maxDelayBufferSeconds;
        delayData = DelayData({
            bufferBlocks: uint64(maxDelayBufferBlocks),
            bufferSeconds: uint64(maxDelayBufferSeconds),
            syncProofValidUntilBlockNumber: uint64(block.number + delayThresholdBlocks),
            syncProofValidUntilTimestamp: uint64(block.timestamp + delayThresholdSeconds)
        });
        syncMarker = SyncMarker({
            blockSeqNum: uint64(bridge.sequencerMessageCount()),
            timeSeqNum: uint64(bridge.sequencerMessageCount())
        });
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

    function getTimeBounds(uint256 delayBufferBlocks, uint256 delayBufferSeconds)
        internal
        view
        virtual
        returns (IBridge.TimeBounds memory)
    {
        IBridge.TimeBounds memory bounds;
        ISequencerInbox.MaxTimeVariation memory maxTimeVariation_ = maxTimeVariation(
            delayBufferBlocks,
            delayBufferSeconds
        );
        if (block.timestamp > maxTimeVariation_.delaySeconds) {
            bounds.minTimestamp = uint64(block.timestamp - maxTimeVariation_.delaySeconds);
        }
        bounds.maxTimestamp = uint64(block.timestamp + maxTimeVariation_.futureSeconds);
        if (block.number > maxTimeVariation_.delayBlocks) {
            bounds.minBlockNumber = uint64(block.number - maxTimeVariation_.delayBlocks);
        }
        bounds.maxBlockNumber = uint64(block.number + maxTimeVariation_.futureBlocks);
        return (bounds);
    }

    /// @inheritdoc ISequencerInbox
    function maxTimeVariation()
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        MaxTimeVariation memory _maxTimeVariation = maxTimeVariation(
            delayData.bufferBlocks,
            delayData.bufferSeconds
        );
        return (
            _maxTimeVariation.delayBlocks,
            _maxTimeVariation.futureBlocks,
            _maxTimeVariation.delaySeconds,
            _maxTimeVariation.futureSeconds
        );
    }

    function maxTimeVariation(uint256 delayBufferBlocks, uint256 delayBufferSeconds)
        internal
        view
        returns (ISequencerInbox.MaxTimeVariation memory)
    {
        if (_chainIdChanged()) {
            return
                ISequencerInbox.MaxTimeVariation({
                    delayBlocks: 1,
                    futureBlocks: 1,
                    delaySeconds: 1,
                    futureSeconds: 1
                });
        } else {
            return (
                ISequencerInbox.MaxTimeVariation({
                    delayBlocks: maxTimeVariationDelayBlocks < delayBufferBlocks
                        ? maxTimeVariationDelayBlocks
                        : delayBufferBlocks,
                    futureBlocks: maxTimeVariationFutureBlocks,
                    delaySeconds: maxTimeVariationDelaySeconds < delayBufferSeconds
                        ? maxTimeVariationDelaySeconds
                        : delayBufferSeconds,
                    futureSeconds: maxTimeVariationFutureSeconds
                })
            );
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
        DelayData memory _delayData = delayData;
        {
            DelayMsgData memory _delayMsgLastProven = delayMsgLastProven;

            // First apply updates to delay buffers from delayMsgLastProven
            _delayData.bufferBlocks = uint64(
                calculateBuffer(
                    _delayMsgLastProven.blockNumber,
                    uint64(l1BlockAndTime[0]),
                    _delayMsgLastProven.delayBlocks,
                    uint64(delayThresholdBlocks),
                    _delayData.bufferBlocks
                )
            );

            _delayData.bufferSeconds = uint64(
                calculateBuffer(
                    _delayMsgLastProven.timestamp,
                    uint64(l1BlockAndTime[1]),
                    _delayMsgLastProven.delaySeconds,
                    uint64(delayThresholdSeconds),
                    _delayData.bufferSeconds
                )
            );

            // record new delayMsgLastProven to be applied to delay buffers in next batch
            delayMsgLastProven = DelayMsgData({
                blockNumber: uint64(l1BlockAndTime[0]),
                timestamp: uint64(l1BlockAndTime[1]),
                delaySeconds: uint64(block.timestamp - uint256(l1BlockAndTime[1])),
                delayBlocks: uint64(block.number - uint256(l1BlockAndTime[0]))
            });

            delayData = _delayData;
        }
        bytes32 messageHash = Messages.messageHash(
            kind,
            sender,
            l1BlockAndTime[0],
            l1BlockAndTime[1],
            _totalDelayedMessagesRead - 1,
            baseFeeL1,
            messageDataHash
        );

        ISequencerInbox.MaxTimeVariation memory _maxTimeVariation = maxTimeVariation(
            _delayData.bufferBlocks,
            _delayData.bufferSeconds
        );
        // Can only force-include after the Sequencer-only window has expired.
        if (l1BlockAndTime[0] + _maxTimeVariation.delayBlocks >= block.number) {
            revert ForceIncludeBlockTooSoon();
        }
        if (l1BlockAndTime[1] + _maxTimeVariation.delaySeconds >= block.timestamp) {
            revert ForceIncludeTimeTooSoon();
        }

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
            _totalDelayedMessagesRead,
            _delayData.bufferBlocks,
            _delayData.bufferSeconds
        );

        uint256 prevSeqMsgCount = bridge.sequencerReportedSubMessageCount();
        uint256 newSeqMsgCount = prevSeqMsgCount +
            _totalDelayedMessagesRead -
            bridge.totalDelayedMessagesRead();
        bridge.enqueueSequencerMessage(
            dataHash,
            _totalDelayedMessagesRead,
            prevSeqMsgCount,
            newSeqMsgCount,
            timeBounds,
            IBridge.BatchDataLocation.NoData
        );
    }

    /// @inheritdoc ISequencerInbox
    function addSequencerL2BatchFromOrigin(
        uint256 sequenceNumber,
        bytes calldata data,
        uint256 afterDelayedMessagesRead,
        IGasRefunder gasRefunder,
        uint256 prevMessageCount,
        uint256 newMessageCount
    ) public refundsGas(gasRefunder, IReader4844(address(0))) {
        // solhint-disable-next-line avoid-tx-origin
        if (msg.sender != tx.origin) revert NotOrigin();
        if (!isBatchPoster(msg.sender)) revert NotBatchPoster();

        (uint256 delayBufferBlocks, uint256 delayBufferSeconds) = delayBufferSyncedState(
            afterDelayedMessagesRead
        );

        uint256 _sequenceNumber = sequenceNumber;

        addSequencerL2BatchFromCalldataImpl(
            data,
            afterDelayedMessagesRead,
            delayBufferBlocks,
            delayBufferSeconds,
            prevMessageCount,
            newMessageCount,
            _sequenceNumber,
            IBridge.BatchDataLocation.TxInput
        );
    }

    /// @inheritdoc ISequencerInbox
    function addSequencerL2Batch(
        uint256 sequenceNumber,
        bytes calldata data,
        uint256 afterDelayedMessagesRead,
        IGasRefunder gasRefunder,
        uint256 prevMessageCount,
        uint256 newMessageCount
    ) public refundsGas(gasRefunder, IReader4844(address(0))) {
        if (!isBatchPoster(msg.sender) && msg.sender != address(rollup)) revert NotBatchPoster();

        (uint256 delayBufferBlocks, uint256 delayBufferSeconds) = delayBufferSyncedState(
            afterDelayedMessagesRead
        );

        uint256 _sequenceNumber = sequenceNumber;

        addSequencerL2BatchFromCalldataImpl(
            data,
            afterDelayedMessagesRead,
            delayBufferBlocks,
            delayBufferSeconds,
            prevMessageCount,
            newMessageCount,
            _sequenceNumber,
            IBridge.BatchDataLocation.SeparateBatchEvent
        );

        emit SequencerBatchData(sequenceNumber, data);
    }

    /// @inheritdoc ISequencerInbox
    function addSequencerL2BatchFromBlobs(
        uint256 sequenceNumber,
        uint256 afterDelayedMessagesRead,
        IGasRefunder gasRefunder,
        uint256 prevMessageCount,
        uint256 newMessageCount,
        DelayAccPreimage calldata delayProof
    ) external refundsGas(gasRefunder, reader4844) {
        if (!isBatchPoster(msg.sender)) revert NotBatchPoster();
        {
            uint256 _totalDelayedMessagesRead = bridge.totalDelayedMessagesRead();
            bytes32 delayedAcc = bridge.delayedInboxAccs(_totalDelayedMessagesRead);
            if (afterDelayedMessagesRead <= _totalDelayedMessagesRead) revert DelayedNotFarEnough();
            if (!isValidDelayedAccPreimage(delayProof, delayedAcc)) {
                revert InvalidDelayedAccPreimage();
            }
        }

        DelayData memory _delayData = delayData;
        uint256 _sequenceNumber = sequenceNumber;

        (uint256 seqMessageIndex, ) = addSequencerL2BatchFromBlobsImpl(
            afterDelayedMessagesRead,
            delayData.bufferBlocks,
            delayData.bufferSeconds,
            prevMessageCount,
            newMessageCount,
            _sequenceNumber
        );

        if (uint256(delayMsgLastProven.delayBlocks) > delayThresholdBlocks) {
            // unsynced: prev batch is late
            // backward difference: decrease delay buffers from due to previous batch
            _delayData.bufferBlocks = uint64(
                calculateBuffer(
                    uint256(delayMsgLastProven.blockNumber),
                    uint256(delayProof.blockNumber),
                    uint256(delayMsgLastProven.delayBlocks),
                    delayThresholdBlocks,
                    uint256(_delayData.bufferBlocks)
                )
            );
            if (block.number - uint256(delayProof.blockNumber) <= delayThresholdBlocks) {
                // unsynced -> synced: prev batch is late and this batch is timely
                // reset replenish pool to avoid replenishing delay buffers too quickly
                replenishPool.roundOffBlocks = uint64(0);
                syncMarker.blockSeqNum = uint64(seqMessageIndex);
            }
        } else if (block.number - uint256(delayProof.blockNumber) <= delayThresholdBlocks) {
            // synced -> synced: prev AND current batches are timely
            if (uint256(_delayData.bufferBlocks) < maxDelayBufferBlocks) {
                // replenish delay buffer if depleted
                (_delayData.bufferBlocks, replenishPool.roundOffBlocks) = calculateReplenish(
                    uint256(delayMsgLastProven.blockNumber),
                    uint256(delayProof.blockNumber),
                    uint256(replenishPool.roundOffBlocks),
                    replenishPeriodBlocks,
                    replenishBlocksPerPeriod,
                    uint256(_delayData.bufferBlocks),
                    maxDelayBufferBlocks
                );
            }
            // store proof validity window
            _delayData.syncProofValidUntilBlockNumber = uint64(
                uint256(delayProof.blockNumber) + delayThresholdBlocks
            );
            if (uint256(_delayData.bufferBlocks) == maxDelayBufferBlocks) {
                // as a gas opt, pack the sync validity into the batch poster authentication
                batchPosterData[msg.sender].maxBufferAndSyncProofValidUntilBlockNumber = uint64(
                    uint256(delayProof.blockNumber) + delayThresholdBlocks
                );
            }
        } else {
            // synced -> unsynced: prev batch is timely and this batch is late
            // do nothing, delay buffer will be decreased in next batch
        }

        if (uint256(delayMsgLastProven.delaySeconds) > delayThresholdSeconds) {
            // unsynced: prev batch is late
            // backward difference: decrease delay buffers from due to previous batch
            _delayData.bufferSeconds = uint64(
                calculateBuffer(
                    uint256(delayMsgLastProven.timestamp),
                    uint256(delayProof.blockTimestamp),
                    uint256(delayMsgLastProven.delaySeconds),
                    delayThresholdSeconds,
                    uint256(_delayData.bufferSeconds)
                )
            );
            if (block.timestamp - uint256(delayProof.blockTimestamp) <= delayThresholdSeconds) {
                // unsynced -> synced: prev batch is late and this batch is timely
                // reset replenish pool to avoid replenishing delay buffers too quickly
                replenishPool.roundOffSeconds = uint64(0);
                syncMarker.timeSeqNum = uint64(seqMessageIndex);
            }
        } else if (block.timestamp - uint256(delayProof.blockTimestamp) <= delayThresholdSeconds) {
            // synced -> synced: prev AND current batches are timely
            if (uint256(_delayData.bufferSeconds) < maxDelayBufferSeconds) {
                // replenish delay buffer if depleted
                (_delayData.bufferSeconds, replenishPool.roundOffSeconds) = calculateReplenish(
                    uint256(delayMsgLastProven.timestamp),
                    uint256(delayProof.blockTimestamp),
                    uint256(replenishPool.roundOffSeconds),
                    replenishPeriodSeconds,
                    replenishSecondsPerPeriod,
                    uint256(_delayData.bufferSeconds),
                    maxDelayBufferSeconds
                );
            }

            // store sync proof validity window
            _delayData.syncProofValidUntilTimestamp = uint64(
                uint256(delayProof.blockTimestamp) + delayThresholdSeconds
            );
            if (uint256(_delayData.bufferSeconds) == maxDelayBufferSeconds) {
                // as a gas opt, pack the sync validity into the batch poster authentication
                batchPosterData[msg.sender].maxBufferAndSyncProofValidUntilTimestamp = uint64(
                    uint256(delayProof.blockTimestamp) + delayThresholdSeconds
                );
            }
        } else {
            // synced -> unsynced: prev batch is timely and this batch is late
            // do nothing, delay buffer will be decreased in next batch
        }

        delayData = _delayData;

        delayMsgLastProven = DelayMsgData({
            blockNumber: delayProof.blockNumber,
            timestamp: delayProof.blockTimestamp,
            delaySeconds: uint64(block.timestamp - uint256(delayProof.blockTimestamp)),
            delayBlocks: uint64(block.number - uint256(delayProof.blockNumber))
        });
    }

    /// @inheritdoc ISequencerInbox
    function addSequencerL2BatchFromBlobs(
        uint256 sequenceNumber,
        uint256 afterDelayedMessagesRead,
        IGasRefunder gasRefunder,
        uint256 prevMessageCount,
        uint256 newMessageCount,
        InboxAccPreimage calldata syncProof
    ) external refundsGas(gasRefunder, IReader4844(address(0))) {
        bytes32 beforeAcc = addSequencerL2BatchFromBlobs(
            sequenceNumber,
            afterDelayedMessagesRead,
            gasRefunder,
            prevMessageCount,
            newMessageCount
        );
        if (
            beforeAcc !=
            keccak256(
                abi.encodePacked(
                    syncProof.beforeAccBeforeAcc,
                    syncProof.beforeAccDataHash,
                    syncProof.beforeAccDelayedAcc
                )
            )
        ) revert InvalidInboxAccPreimage();
        if (
            !isValidDelayedAccPreimage(syncProof.delayedAccPreimage, syncProof.beforeAccDelayedAcc)
        ) {
            revert InvalidDelayedAccPreimage();
        }

        // update the sync proof validity window
        delayData.syncProofValidUntilBlockNumber = uint64(
            syncProof.delayedAccPreimage.blockNumber + delayThresholdBlocks
        );
        delayData.syncProofValidUntilTimestamp = uint64(
            syncProof.delayedAccPreimage.blockTimestamp + delayThresholdSeconds
        );
        // as a gas optimization, we pack the sync validity into the batch poster authentication
        if (uint256(delayData.bufferBlocks) == maxDelayBufferBlocks) {
            batchPosterData[msg.sender].maxBufferAndSyncProofValidUntilBlockNumber = uint64(
                uint256(syncProof.delayedAccPreimage.blockNumber) + delayThresholdBlocks
            );
        }
        if (uint256(delayData.bufferSeconds) == maxDelayBufferSeconds) {
            batchPosterData[msg.sender].maxBufferAndSyncProofValidUntilTimestamp = uint64(
                uint256(syncProof.delayedAccPreimage.blockTimestamp) + delayThresholdSeconds
            );
        }
    }

    /// @inheritdoc ISequencerInbox
    function addSequencerL2BatchFromBlobs(
        uint256 sequenceNumber,
        uint256 afterDelayedMessagesRead,
        IGasRefunder gasRefunder,
        uint256 prevMessageCount,
        uint256 newMessageCount
    ) public refundsGas(gasRefunder, IReader4844(address(0))) returns (bytes32 beforeAcc) {
        if (!isBatchPoster(msg.sender)) revert NotBatchPoster();
        (uint256 delayBufferBlocks, uint256 delayBufferSeconds) = delayBufferSyncedState(
            afterDelayedMessagesRead
        );

        uint256 sequenceNumber_ = sequenceNumber;

        (, beforeAcc) = addSequencerL2BatchFromBlobsImpl(
            afterDelayedMessagesRead,
            delayBufferBlocks,
            delayBufferSeconds,
            prevMessageCount,
            newMessageCount,
            sequenceNumber_
        );
    }

    function addSequencerL2BatchFromCalldataImpl(
        bytes calldata data,
        uint256 afterDelayedMessagesRead,
        uint256 delayBufferBlocks,
        uint256 delayBufferSeconds,
        uint256 prevMessageCount,
        uint256 newMessageCount,
        uint256 sequenceNumber,
        IBridge.BatchDataLocation batchDataLocation
    ) internal {
        (bytes32 dataHash, IBridge.TimeBounds memory timeBounds) = formCallDataHash(
            data,
            afterDelayedMessagesRead,
            delayBufferBlocks,
            delayBufferSeconds
        );

        (uint256 seqMessageIndex, , , ) = bridge.enqueueSequencerMessage(
            dataHash,
            afterDelayedMessagesRead,
            prevMessageCount,
            newMessageCount,
            timeBounds,
            batchDataLocation
        );

        // ~uint256(0) is type(uint256).max, but ever so slightly cheaper
        if (seqMessageIndex != sequenceNumber && sequenceNumber != ~uint256(0)) {
            revert BadSequencerNumber(seqMessageIndex, sequenceNumber);
        }

        // solhint-disable-next-line avoid-tx-origin
        if (msg.sender == tx.origin) {
            // only report batch poster spendings if chain is using ETH as native currency
            if (!isUsingFeeToken) {
                submitBatchSpendingReport(dataHash, seqMessageIndex, block.basefee, 0);
            }
        } else {
            emit SequencerBatchData(sequenceNumber, data);
        }
    }

    function addSequencerL2BatchFromBlobsImpl(
        uint256 afterDelayedMessagesRead,
        uint256 delayBufferBlocks,
        uint256 delayBufferSeconds,
        uint256 prevMessageCount,
        uint256 newMessageCount,
        uint256 sequenceNumber
    ) internal returns (uint256 seqMessageIndex, bytes32 beforeAcc) {
        (
            bytes32 dataHash,
            IBridge.TimeBounds memory timeBounds,
            uint256 blobGas
        ) = formBlobDataHash(afterDelayedMessagesRead, delayBufferBlocks, delayBufferSeconds);

        (seqMessageIndex, beforeAcc, , ) = bridge.enqueueSequencerMessage(
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
        // same as using calldata, we only submit spending report if the caller is the origin of the tx
        // such that one cannot "double-claim" batch posting refund in the same tx
        // solhint-disable-next-line avoid-tx-origin
        if (msg.sender == tx.origin && !isUsingFeeToken) {
            submitBatchSpendingReport(dataHash, seqMessageIndex, block.basefee, blobGas);
        }
    }

    function packHeader(
        uint256 afterDelayedMessagesRead,
        uint256 delayBufferBlocks,
        uint256 delayBufferSeconds
    ) internal view returns (bytes memory, IBridge.TimeBounds memory) {
        IBridge.TimeBounds memory timeBounds = getTimeBounds(delayBufferBlocks, delayBufferSeconds);
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
    function formEmptyDataHash(
        uint256 afterDelayedMessagesRead,
        uint256 delayBufferBlocks,
        uint256 delayBufferSeconds
    ) internal view returns (bytes32, IBridge.TimeBounds memory) {
        (bytes memory header, IBridge.TimeBounds memory timeBounds) = packHeader(
            afterDelayedMessagesRead,
            delayBufferBlocks,
            delayBufferSeconds
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
    function formCallDataHash(
        bytes calldata data,
        uint256 afterDelayedMessagesRead,
        uint256 delayBufferBlocks,
        uint256 delayBufferSeconds
    ) internal view returns (bytes32, IBridge.TimeBounds memory) {
        uint256 fullDataLen = HEADER_LENGTH + data.length;
        if (fullDataLen > maxDataSize) revert DataTooLarge(fullDataLen, maxDataSize);

        (bytes memory header, IBridge.TimeBounds memory timeBounds) = packHeader(
            afterDelayedMessagesRead,
            delayBufferBlocks,
            delayBufferSeconds
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
    /// @return The normalized amount of gas used for blob posting
    function formBlobDataHash(
        uint256 afterDelayedMessagesRead,
        uint256 delayBufferBlocks,
        uint256 delayBufferSeconds
    )
        internal
        view
        returns (
            bytes32,
            IBridge.TimeBounds memory,
            uint256
        )
    {
        bytes32[] memory dataHashes = reader4844.getDataHashes();
        if (dataHashes.length == 0) revert MissingDataHashes();

        (bytes memory header, IBridge.TimeBounds memory timeBounds) = packHeader(
            afterDelayedMessagesRead,
            delayBufferBlocks,
            delayBufferSeconds
        );

        uint256 blobCost = reader4844.getBlobBaseFee() * GAS_PER_BLOB * dataHashes.length;
        return (
            keccak256(bytes.concat(header, DATA_BLOB_HEADER_FLAG, abi.encodePacked(dataHashes))),
            timeBounds,
            block.basefee > 0 ? blobCost / block.basefee : 0
        );
    }

    /// @dev Validates the synchronization by conditionally reading state and returns the delay buffer.
    /// @param afterDelayedMessagesRead The delayed messages count read up to
    function delayBufferSyncedState(uint256 afterDelayedMessagesRead)
        internal
        view
        returns (uint256, uint256)
    {
        if (
            uint256(batchPosterData[msg.sender].maxBufferAndSyncProofValidUntilBlockNumber) >
            block.number &&
            uint256(batchPosterData[msg.sender].maxBufferAndSyncProofValidUntilTimestamp) >
            block.timestamp
        ) {
            // as a gas opt, check if sync validity is packed into the batch poster authentication
            return (maxDelayBufferBlocks, maxDelayBufferSeconds);
        } else if (
            (block.number < delayData.syncProofValidUntilBlockNumber &&
                block.timestamp < delayData.syncProofValidUntilTimestamp) ||
            afterDelayedMessagesRead == bridge.totalDelayedMessagesRead()
        ) {
            // check for sync validity OR no new delayed messages read
            return (uint256(delayData.bufferBlocks), uint256(delayData.bufferSeconds));
        } else {
            revert SyncProofExpired();
        }
    }

    /// @dev   Validates a delayed accumulator preimage
    /// @param preimage The preimage to validate
    /// @param delayedAcc The delayed accumulator to validate against
    function isValidDelayedAccPreimage(DelayAccPreimage memory preimage, bytes32 delayedAcc)
        internal
        pure
        returns (bool)
    {
        return
            delayedAcc ==
            Messages.accumulateInboxMessage(
                preimage.beforeDelayedAcc,
                Messages.messageHash(
                    preimage.kind,
                    preimage.sender,
                    preimage.blockNumber,
                    preimage.blockTimestamp,
                    preimage.count,
                    preimage.baseFeeL1,
                    preimage.messageDataHash
                )
            );
    }

    /// @dev   Decrements the delay buffer saturating at the threshold
    /// @param start The beginning reference point
    /// @param end The ending reference point
    /// @param delay The delay to be applied
    /// @param threshold The threshold to saturate at
    /// @param buffer The buffer to be decremented
    function calculateBuffer(
        uint256 start,
        uint256 end,
        uint256 delay,
        uint256 threshold,
        uint256 buffer
    ) internal pure returns (uint256) {
        uint256 elapsed = end > start ? end - start : 0;
        uint256 unexpectedDelay = delay > threshold ? delay - threshold : 0;
        uint256 decrease = unexpectedDelay > elapsed ? elapsed : unexpectedDelay;
        buffer = decrease > buffer ? 0 : buffer - decrease;
        buffer = buffer > threshold ? buffer : threshold;
        return buffer;
    }

    /// @dev   Replenishes the delay buffer saturating at maxBuffer
    /// @param start The beginning reference point
    /// @param end The ending reference point
    /// @param repelenishRoundoff The roundoff from the last replenish
    /// @param replenishPeriod The replenish period
    /// @param replenishPerPeriod The amount to replenish per period
    /// @param buffer The buffer to be replenished
    /// @param maxBuffer The maximum buffer
    function calculateReplenish(
        uint256 start,
        uint256 end,
        uint256 repelenishRoundoff,
        uint256 replenishPeriod,
        uint256 replenishPerPeriod,
        uint256 buffer,
        uint256 maxBuffer
    ) internal pure returns (uint64, uint64) {
        uint256 elapsed = end > start ? end - start + repelenishRoundoff : 0;
        uint256 replenish = (elapsed / replenishPeriod) * replenishPerPeriod;
        repelenishRoundoff = elapsed % replenishPeriod;
        buffer += replenish;
        if (buffer > maxBuffer) {
            buffer = maxBuffer;
            repelenishRoundoff = 0;
        }
        return (uint64(buffer), uint64(repelenishRoundoff));
    }

    /// @dev   Submit a batch spending report message so that the batch poster can be reimbursed on the rollup
    ///        This function expect msg.sender is tx.origin, and will always record tx.origin as the spender
    /// @param dataHash The hash of the message the spending report is being submitted for
    /// @param seqMessageIndex The index of the message to submit the spending report for
    /// @param gasPrice The gas price that was paid for the data (standard gas or data gas)
    function submitBatchSpendingReport(
        bytes32 dataHash,
        uint256 seqMessageIndex,
        uint256 gasPrice,
        uint256 extraGas
    ) internal {
        // report the account who paid the gas (tx.origin) for the tx as batch poster
        // if msg.sender is used and is a contract, it might not be able to spend the refund on l2
        // solhint-disable-next-line avoid-tx-origin
        address batchPoster = tx.origin;

        // this msg isn't included in the current sequencer batch, but instead added to
        // the delayed messages queue that is yet to be included
        if (hostChainIsArbitrum) {
            // Include extra gas for the host chain's L1 gas charging
            uint256 l1Fees = ArbGasInfo(address(0x6c)).getCurrentTxL1GasFees();
            extraGas += l1Fees / block.basefee;
        }
        //require(extraGas <= type(uint64).max, "EXTRA_GAS_NOT_UINT64");
        bytes memory spendingReportMsg = abi.encodePacked(
            block.timestamp,
            batchPoster,
            dataHash,
            seqMessageIndex,
            gasPrice,
            uint64(extraGas)
        );

        uint256 msgNum = bridge.submitBatchSpendingReport(
            batchPoster,
            keccak256(spendingReportMsg)
        );
        // this is the same event used by Inbox.sol after including a message to the delayed message accumulator
        emit InboxMessageDelivered(msgNum, spendingReportMsg);
    }

    /// @inheritdoc ISequencerInbox
    function replenishRate()
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (
            replenishSecondsPerPeriod,
            replenishBlocksPerPeriod,
            replenishPeriodSeconds,
            replenishPeriodBlocks
        );
    }

    /// @inheritdoc ISequencerInbox
    function delaySettings()
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (
            delayThresholdSeconds,
            delayThresholdBlocks,
            maxDelayBufferSeconds,
            maxDelayBufferBlocks
        );
    }

    function inboxAccs(uint256 index) external view returns (bytes32) {
        return bridge.sequencerInboxAccs(index);
    }

    function batchCount() external view returns (uint256) {
        return bridge.sequencerMessageCount();
    }

    /// @inheritdoc ISequencerInbox
    function setIsBatchPoster(address addr, bool isBatchPoster_)
        public
        onlyRollupOwnerOrBatchPosterManager
    {
        batchPosterData[addr].isBatchPoster = isBatchPoster_;
        // we used to have OwnerFunctionCalled(0) for setting the maxTimeVariation
        // so we dont use index = 0 here, even though this is the first owner function
        // to stay compatible with legacy events
        emit OwnerFunctionCalled(1);
    }

    /// @inheritdoc ISequencerInbox
    function setValidKeyset(bytes calldata keysetBytes) external onlyRollupOwner {
        uint256 ksWord = uint256(keccak256(bytes.concat(hex"fe", keccak256(keysetBytes))));
        bytes32 ksHash = bytes32(ksWord ^ (1 << 255));
        //require(keysetBytes.length < 64 * 1024, "keyset is too large");

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
    function setIsSequencer(address addr, bool isSequencer_)
        external
        onlyRollupOwnerOrBatchPosterManager
    {
        isSequencer[addr] = isSequencer_;
        emit OwnerFunctionCalled(4); // Owner in this context can also be batch poster manager
    }

    /// @inheritdoc ISequencerInbox
    function setBatchPosterManager(address newBatchPosterManager) external onlyRollupOwner {
        batchPosterManager = newBatchPosterManager;
        emit OwnerFunctionCalled(5);
    }

    function isValidKeysetHash(bytes32 ksHash) external view returns (bool) {
        return dasKeySetInfo[ksHash].isValidKeyset;
    }

    function isBatchPoster(address addr) public view returns (bool) {
        return batchPosterData[addr].isBatchPoster;
    }

    /// @inheritdoc ISequencerInbox
    function getKeysetCreationBlock(bytes32 ksHash) external view returns (uint256) {
        DasKeySetInfo memory ksInfo = dasKeySetInfo[ksHash];
        if (ksInfo.creationBlock == 0) revert NoSuchKeyset(ksHash);
        return uint256(ksInfo.creationBlock);
    }
}
