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
        uint64 delayBlocks;
        uint64 futureBlocks;
        uint64 delaySeconds;
        uint64 futureSeconds;
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

    function addSequencerL2BatchFromOrigin(
        uint256 sequenceNumber,
        bytes calldata data,
        uint256 afterDelayedMessagesRead,
        IGasRefunder gasRefunder,
        uint256 prevMessageCount,
        uint256 newMessageCount
    ) external;

    function addSequencerL2Batch(
        uint256 sequenceNumber,
        bytes calldata data,
        uint256 afterDelayedMessagesRead,
        IGasRefunder gasRefunder,
        uint256 prevMessageCount,
        uint256 newMessageCount
    ) external;

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

    /// @notice Allows the rollup owner to sync the rollup address
    function updateRollupAddress() external;
}

interface IDataHashReader {
    /// @notice Returns all the data hashes of all the blobs on the current transaction
    function getDataHashes() external view returns (bytes32[] memory);
}

interface IBlobBasefeeReader {
    /// @notice Returns the current BLOBBASEFEE
    function getBlobBaseFee() external view returns (uint256);
}
