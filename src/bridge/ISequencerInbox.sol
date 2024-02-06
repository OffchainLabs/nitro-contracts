// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

// solhint-disable-next-line compiler-version
pragma solidity >=0.6.9 <0.9.0;
pragma experimental ABIEncoderV2;

import "../libraries/IGasRefunder.sol";
import "./IDelayedMessageProvider.sol";
import "./IBridge.sol";

interface ISequencerInbox is IDelayedMessageProvider {
    /// @notice The maximum amount of time variatin between a message being posted on the L1 and being executed on the L2
    /// @param delayBlocks The max amount of blocks in the past that a message can be received on L2
    /// @param futureBlocks The max amount of blocks in the future that a message can be received on L2
    /// @param delaySeconds The max amount of seconds in the past that a message can be received on L2
    /// @param futureSeconds The max amount of seconds in the future that a message can be received on L2
    struct MaxTimeVariation {
        uint256 delayBlocks;
        uint256 futureBlocks;
        uint256 delaySeconds;
        uint256 futureSeconds;
    }

    /// @notice The rate at which the delay buffer is replenished.
    /// @param secondsPerPeriod The amount of time in seconds that is added to the delay buffer every period
    /// @param blocksPerPeriod The amount of blocks that is added to the delay buffer every period
    /// @param periodSeconds The amount of time in seconds that is waited between replenishing the delay buffer
    /// @param periodBlocks The amount of blocks that is waited between replenishing the delay buffer
    struct ReplenishRate {
        uint256 secondsPerPeriod;
        uint256 blocksPerPeriod;
        uint256 periodSeconds;
        uint256 periodBlocks;
    }

    /// @notice Delay buffer and delay threshold settings
    /// @param delayThresholdSeconds The maximum amount of time in seconds that a message is expected to be delayed
    /// @param delayThresholdBlocks The maximum amount of blocks that a message is expected to be delayed
    /// @param maxDelayBufferSeconds The maximum the delay buffer seconds can be
    /// @param maxDelayBufferBlocks The maximum the delay blocks seconds can be
    struct DelaySettings {
        uint256 delayThresholdSeconds;
        uint256 delayThresholdBlocks;
        uint256 maxDelayBufferSeconds;
        uint256 maxDelayBufferBlocks;
    }

    /// @notice Used to keep track of the time and block sync between L1 and L2
    /// @param blockSeqNum The sequence number when block synchronization began.
    /// @param timeSeqNum The sequence number when time synchronization began.
    struct SyncMarker {
        uint64 blockSeqNum;
        uint64 timeSeqNum;
    }

    /// @notice Packs batch poster authentication with sync validity state for gas optimization
    /// @param isBatchPoster If the mapped address is a batch poster.
    /// @param maxBufferAndSyncProofValidUntilBlockNumber The block number until which the sequencer can post without a delay / sync proof.
    /// @param maxBufferAndSyncProofValidUntilTimestamp The timestamp until which the sequencer can post without a delay / sync proof.
    struct BatchPosterData {
        bool isBatchPoster;
        uint64 maxBufferAndSyncProofValidUntilBlockNumber;
        uint64 maxBufferAndSyncProofValidUntilTimestamp;
    }

    /// @notice The delay buffer packed with the sync proof validity window for gas optimization
    /// @param bufferBlocks The amount of blocks in the delay buffer.
    /// @param bufferSeconds The amount of seconds in the delay buffer.
    /// @param syncProofValidUntilBlockNumber The block number until which the sequencer can post batches in a block synced state without proof.
    /// @param syncProofValidUntilTimestamp The timestamp until which the sequencer can post batches in a time synced state without proof.
    struct DelayData {
        uint64 bufferBlocks;
        uint64 bufferSeconds;
        uint64 syncProofValidUntilBlockNumber;
        uint64 syncProofValidUntilTimestamp;
    }

    /// @notice The header and delay of a sequenced delayed message.
    /// @param blockNumber The block number when the message was created.
    /// @param timestamp The timestamp when the message was created.
    /// @param delayBlocks The amount of blocks the message was delayed.
    /// @param delaySeconds The amount of seconds the message was delayed.
    struct DelayMsgData {
        uint64 blockNumber;
        uint64 timestamp;
        uint64 delayBlocks;
        uint64 delaySeconds;
    }

    /// @notice The roundoff calculations for replenishing the delay buffer.
    /// @param roundOffBlocks The amount of roundoff blocks to carry over to the next replenish calculation.
    /// @param roundOffSeconds The amount of roundoff seconds to carry over to the next replenish calculation.
    struct ReplenishPool {
        uint64 roundOffBlocks;
        uint64 roundOffSeconds;
    }

    /// @notice The data for proving a delayed message against a delayed accumulator
    struct DelayAccPreimage {
        bytes32 beforeDelayedAcc;
        uint8 kind;
        address sender;
        uint64 blockNumber;
        uint64 blockTimestamp;
        uint256 count;
        uint256 baseFeeL1;
        bytes32 messageDataHash;
    }

    /// @notice The data for proving a delayed message against an inbox accumulator
    struct InboxAccPreimage {
        bytes32 beforeAccBeforeAcc;
        bytes32 beforeAccDataHash;
        bytes32 beforeAccDelayedAcc;
        DelayAccPreimage delayedAccPreimage;
    }

    event OwnerFunctionCalled(uint256 indexed id);

    /// @dev a separate event that emits batch data when this isn't easily accessible in the tx.input
    event SequencerBatchData(uint256 indexed batchSequenceNumber, bytes data);

    /// @dev a valid keyset was added
    event SetValidKeyset(bytes32 indexed keysetHash, bytes keysetBytes);

    /// @dev a keyset was invalidated
    event InvalidateKeyset(bytes32 indexed keysetHash);

    /// @notice The total number of delated messages read in the bridge
    /// @dev    We surface this here for backwards compatibility
    function totalDelayedMessagesRead() external view returns (uint256);

    function bridge() external view returns (IBridge);

    /// @dev The size of the batch header
    // solhint-disable-next-line func-name-mixedcase
    function HEADER_LENGTH() external view returns (uint256);

    /// @dev If the first batch data byte after the header has this bit set,
    ///      the sequencer inbox has authenticated the data. Currently only used for 4844 blob support.
    ///      See: https://github.com/OffchainLabs/nitro/blob/69de0603abf6f900a4128cab7933df60cad54ded/arbstate/das_reader.go
    // solhint-disable-next-line func-name-mixedcase
    function DATA_AUTHENTICATED_FLAG() external view returns (bytes1);

    /// @dev If the first data byte after the header has this bit set,
    ///      then the batch data is to be found in 4844 data blobs
    ///      See: https://github.com/OffchainLabs/nitro/blob/69de0603abf6f900a4128cab7933df60cad54ded/arbstate/das_reader.go
    // solhint-disable-next-line func-name-mixedcase
    function DATA_BLOB_HEADER_FLAG() external view returns (bytes1);

    /// @dev If the first data byte after the header has this bit set,
    ///      then the batch data is a das message
    ///      See: https://github.com/OffchainLabs/nitro/blob/69de0603abf6f900a4128cab7933df60cad54ded/arbstate/das_reader.go
    // solhint-disable-next-line func-name-mixedcase
    function DAS_MESSAGE_HEADER_FLAG() external view returns (bytes1);

    /// @dev If the first data byte after the header has this bit set,
    ///      then the batch data is a das message that employs a merklesization strategy
    ///      See: https://github.com/OffchainLabs/nitro/blob/69de0603abf6f900a4128cab7933df60cad54ded/arbstate/das_reader.go
    // solhint-disable-next-line func-name-mixedcase
    function TREE_DAS_MESSAGE_HEADER_FLAG() external view returns (bytes1);

    /// @dev If the first data byte after the header has this bit set,
    ///      then the batch data has been brotli compressed
    ///      See: https://github.com/OffchainLabs/nitro/blob/69de0603abf6f900a4128cab7933df60cad54ded/arbstate/das_reader.go
    // solhint-disable-next-line func-name-mixedcase
    function BROTLI_MESSAGE_HEADER_FLAG() external view returns (bytes1);

    /// @dev If the first data byte after the header has this bit set,
    ///      then the batch data uses a zero heavy encoding
    ///      See: https://github.com/OffchainLabs/nitro/blob/69de0603abf6f900a4128cab7933df60cad54ded/arbstate/das_reader.go
    // solhint-disable-next-line func-name-mixedcase
    function ZERO_HEAVY_MESSAGE_HEADER_FLAG() external view returns (bytes1);

    function rollup() external view returns (IOwnable);

    function isBatchPoster(address) external view returns (bool);

    function isSequencer(address) external view returns (bool);

    function maxDataSize() external view returns (uint256);

    /// @notice The batch poster manager has the ability to change the batch poster addresses
    ///         This enables the batch poster to do key rotation
    function batchPosterManager() external view returns (address);

    struct DasKeySetInfo {
        bool isValidKeyset;
        uint64 creationBlock;
    }

    /// @dev returns 4 uint256 to be compatible with older version
    function maxTimeVariation()
        external
        view
        returns (
            uint256 delayBlocks,
            uint256 futureBlocks,
            uint256 delaySeconds,
            uint256 futureSeconds
        );

    function replenishRate()
        external
        view
        returns (
            uint256 secondsPerPeriod,
            uint256 blocksPerPeriod,
            uint256 periodSeconds,
            uint256 periodBlocks
        );

    function delaySettings()
        external
        view
        returns (
            uint256 delayThresholdSeconds,
            uint256 delayThresholdBlocks,
            uint256 maxDelayBufferSeconds,
            uint256 maxDelayBufferBlocks
        );

    function syncMarker() external view returns (uint64 blocksSeqNum, uint64 timeSeqNum);

    function delayData()
        external
        view
        returns (
            uint64 bufferBlocks,
            uint64 bufferSeconds,
            uint64 syncProofValidUntilBlockNumber,
            uint64 syncProofValidUntilTimestamp
        );

    function dasKeySetInfo(bytes32) external view returns (bool, uint64);

    /// @notice Force messages from the delayed inbox to be included in the chain
    ///         Callable by any address, but message can only be force-included after maxTimeVariation.delayBlocks and
    ///         maxTimeVariation.delaySeconds has elapsed. As part of normal behaviour the sequencer will include these
    ///         messages so it's only necessary to call this if the sequencer is down, or not including any delayed messages.
    /// @param _totalDelayedMessagesRead The total number of messages to read up to
    /// @param kind The kind of the last message to be included
    /// @param l1BlockAndTime The l1 block and the l1 timestamp of the last message to be included
    /// @param baseFeeL1 The l1 gas price of the last message to be included
    /// @param sender The sender of the last message to be included
    /// @param messageDataHash The messageDataHash of the last message to be included
    function forceInclusion(
        uint256 _totalDelayedMessagesRead,
        uint8 kind,
        uint64[2] calldata l1BlockAndTime,
        uint256 baseFeeL1,
        address sender,
        bytes32 messageDataHash
    ) external;

    function inboxAccs(uint256 index) external view returns (bytes32);

    function batchCount() external view returns (uint256);

    function isValidKeysetHash(bytes32 ksHash) external view returns (bool);

    /// @notice the creation block is intended to still be available after a keyset is deleted
    function getKeysetCreationBlock(bytes32 ksHash) external view returns (uint256);

    // ---------- BatchPoster functions ----------

    /// @dev Sequences messages without any delay / sync proof, and posts an L2 batch with calldata.
    /// @notice Normally the sequencer will call this function when posting batches with calldata.
    function addSequencerL2BatchFromOrigin(
        uint256 sequenceNumber,
        bytes calldata data,
        uint256 afterDelayedMessagesRead,
        IGasRefunder gasRefunder,
        uint256 prevMessageCount,
        uint256 newMessageCount
    ) external;

    /// @dev Sequences messages without any delay / sync proof, and posts an L2 batch with calldata. Can be called by contracts.
    /// @notice Normally the rollup creation process will call this function to post the first batch.
    ///         The sequencer will not typically call this function since it will not be refunded for gas.
    function addSequencerL2Batch(
        uint256 sequenceNumber,
        bytes calldata data,
        uint256 afterDelayedMessagesRead,
        IGasRefunder gasRefunder,
        uint256 prevMessageCount,
        uint256 newMessageCount
    ) external;

    /// @dev    Proves message delays, updates delay buffers, and posts an L2 batch with blob data.
    ///         Must read atleast one new delayed message.
    /// @notice Normally the sequencer will only call this function after the sequencer has been offline for a while.
    ///         The extra proof adds cost to batch posting, and while the sequencer is online, the proof is unnecessary.
    function addSequencerL2BatchFromBlobs(
        uint256 sequenceNumber,
        uint256 afterDelayedMessagesRead,
        IGasRefunder gasRefunder,
        uint256 prevMessageCount,
        uint256 newMessageCount,
        DelayAccPreimage calldata delayProof
    ) external;

    /// @dev    Proves sequenced messages are synchronized in timestamp & blocknumber, extends the sync validity window,
    ///         and posts an L2 batch with blob data.
    /// @notice Normally the sequencer will only call this function once every delayThresholdSeconds / delayThresholdBlocks.
    ///         The proof stores a time / block range for which the proof is valid and the sequencer can batch without proof.
    function addSequencerL2BatchFromBlobs(
        uint256 sequenceNumber,
        uint256 afterDelayedMessagesRead,
        IGasRefunder gasRefunder,
        uint256 prevMessageCount,
        uint256 newMessageCount,
        InboxAccPreimage calldata syncProof
    ) external;

    /// @dev Sequences messages without any delay / sync proof, and posts an L2 batch with blob data.
    /// @notice Normally the sequencer will call this function when posting batches with blob data.
    function addSequencerL2BatchFromBlobs(
        uint256 sequenceNumber,
        uint256 afterDelayedMessagesRead,
        IGasRefunder gasRefunder,
        uint256 prevMessageCount,
        uint256 newMessageCount
    ) external returns (bytes32);

    // ---------- onlyRollupOrOwner functions ----------

    /**
     * @notice Updates whether an address is authorized to be a batch poster at the sequencer inbox
     * @param addr the address
     * @param isBatchPoster_ if the specified address should be authorized as a batch poster
     */
    function setIsBatchPoster(address addr, bool isBatchPoster_) external;

    /**
     * @notice Makes Data Availability Service keyset valid
     * @param keysetBytes bytes of the serialized keyset
     */
    function setValidKeyset(bytes calldata keysetBytes) external;

    /**
     * @notice Invalidates a Data Availability Service keyset
     * @param ksHash hash of the keyset
     */
    function invalidateKeysetHash(bytes32 ksHash) external;

    /**
     * @notice Updates whether an address is authorized to be a sequencer.
     * @dev The IsSequencer information is used only off-chain by the nitro node to validate sequencer feed signer.
     * @param addr the address
     * @param isSequencer_ if the specified address should be authorized as a sequencer
     */
    function setIsSequencer(address addr, bool isSequencer_) external;

    /**
     * @notice Updates the batch poster manager, the address which has the ability to rotate batch poster keys
     * @param newBatchPosterManager The new batch poster manager to be set
     */
    function setBatchPosterManager(address newBatchPosterManager) external;

    /// @notice Allows the rollup owner to sync the rollup address
    function updateRollupAddress() external;
}
