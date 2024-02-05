// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/nitro/blob/master/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.4;

import {
    AlreadyInit,
    NotRollup,
    ProofTooLong,
    PathNotMinimal,
    UnknownRoot,
    AlreadySpent,
    BridgeCallFailed,
    HadZeroInit,
    BadPostUpgradeInit,
    RollupNotChanged
} from "../libraries/Error.sol";
import "./IBridge.sol";
import "./IOutbox.sol";
import "../libraries/MerkleLib.sol";
import "../libraries/DelegateCallAware.sol";

/// @dev this error is thrown since certain functions are only expected to be used in simulations, not in actual txs
error SimulationOnlyEntrypoint();

abstract contract AbsOutbox is DelegateCallAware, IOutbox {
    address public rollup; // the rollup contract
    IBridge public bridge; // the bridge contract

    mapping(uint256 => bytes32) public spent; // packed spent bitmap
    mapping(bytes32 => bytes32) public roots; // maps root hashes => L2 block hash

    // we're packing this struct into 4 storage slots
    // 1st slot: timestamp, l2Block (128 bits each, max ~3.4*10^38)
    // 2nd slot: outputId (256 bits)
    // 3rd slot: l1Block (96 bits, max ~7.9*10^28), sender (address 160 bits)
    // 4th slot: withdrawalAmount (256 bits)
    struct L2ToL1Context {
        uint128 l2Block;
        uint128 timestamp;
        bytes32 outputId;
        address sender;
        uint96 l1Block;
        uint256 withdrawalAmount;
    }

    // @dev Deprecated in place of transient storage
    L2ToL1Context internal __context;

    // @dev Transient storage slots for L2ToL1Context. Assembly doesn't allow non-direct constants.
    //  keccak256("L2_TO_L1_SENDER_TSLOT")
    //  keccak256("L2_BLOCK_TSLOT")
    //  keccak256("L1_BLOCK_TSLOT")
    //  keccak256("L2_TO_L1_TIMESTAMP_TSLOT")
    //  keccak256("L2_TO_L1_OUTPUT_ID_TSLOT")
    //  keccak256("L2_TO_L1_WITHDRAWAL_AMOUNT_TSLOT")
    bytes32 internal constant L2_TO_L1_SENDER_TSLOT = 0xebabdcd8fe14a14c647a343706bd06da1b2e5aebf8d296b8663ee891cc06cf08;
    bytes32 internal constant L2_BLOCK_TSLOT = 0x447055cbf69f311f2c80a261ffef9aa8f2a2c5b2ade03ecfbc92a8bfd659a6b3;
    bytes32 internal constant L1_BLOCK_TSLOT = 0xa804c75ce466d589b8d6227e9a0269a295b94c47d7db88da6af0b77161a4754d;
    bytes32 internal constant L2_TO_L1_TIMESTAMP_TSLOT = 0xeab03eac502e862d963579369c7da43ef4f9948cb50e6e40a96051fb270cb504;
    bytes32 internal constant L2_TO_L1_OUTPUT_ID_TSLOT = 0x54ac2ba357ff3576d8d2807d265891a0b119c58f75682a7ea98a7440fb38c5f1;
    bytes32 internal constant L2_TO_L1_WITHDRAWAL_AMOUNT_TSLOT = 0xdf31e30ba0b65dfa9a3e515da66d692305a58e8c0318de8340e1e0e54b00f27b;

    uint128 public constant OUTBOX_VERSION = 3;

    function initialize(IBridge _bridge) external onlyDelegated {
        if (address(_bridge) == address(0)) revert HadZeroInit();
        if (address(bridge) != address(0)) revert AlreadyInit();
        bridge = _bridge;
        rollup = address(_bridge.rollup());
    }

    function postUpgradeInit() external onlyDelegated onlyProxyOwner {
    }

    /// @notice Allows the rollup owner to sync the rollup address
    function updateRollupAddress() external {
        if (msg.sender != IOwnable(rollup).owner())
            revert NotOwner(msg.sender, IOwnable(rollup).owner());
        address newRollup = address(bridge.rollup());
        if (rollup == newRollup) revert RollupNotChanged();
        rollup = newRollup;
    }

    function updateSendRoot(bytes32 root, bytes32 l2BlockHash) external {
        if (msg.sender != rollup) revert NotRollup(msg.sender, rollup);
        roots[root] = l2BlockHash;
        emit SendRootUpdated(root, l2BlockHash);
    }

    /// @inheritdoc IOutbox
    function l2ToL1Sender() external view returns (address sender) {
        assembly {
            sender := tload(L2_TO_L1_SENDER_TSLOT)
        }
    }

    /// @inheritdoc IOutbox
    function l2ToL1Block() external view returns (uint256 l2Block) {
        assembly {
            l2Block := tload(L2_BLOCK_TSLOT)
        }
    }

    /// @inheritdoc IOutbox
    function l2ToL1EthBlock() external view returns (uint256 l1Block) {
        assembly {
            l1Block := tload(L1_BLOCK_TSLOT)
        }
    }

    /// @inheritdoc IOutbox
    function l2ToL1Timestamp() external view returns (uint256 _timestamp) {
        assembly {
            _timestamp := tload(L2_TO_L1_TIMESTAMP_TSLOT)
        }
    }

    /// @notice batch number is deprecated and now always returns 0
    function l2ToL1BatchNum() external pure returns (uint256) {
        return 0;
    }

    /// @inheritdoc IOutbox
    function l2ToL1OutputId() external view returns (bytes32 outputId) {
        assembly {
            outputId := tload(L2_TO_L1_OUTPUT_ID_TSLOT)
        }
    }

    /// @inheritdoc IOutbox
    function executeTransaction(
        bytes32[] calldata proof,
        uint256 index,
        address l2Sender,
        address to,
        uint256 l2Block,
        uint256 l1Block,
        uint256 l2Timestamp,
        uint256 value,
        bytes calldata data
    ) external {
        bytes32 userTx = calculateItemHash(
            l2Sender,
            to,
            l2Block,
            l1Block,
            l2Timestamp,
            value,
            data
        );

        recordOutputAsSpent(proof, index, userTx);

        executeTransactionImpl(index, l2Sender, to, l2Block, l1Block, l2Timestamp, value, data);
    }

    /// @inheritdoc IOutbox
    function executeTransactionSimulation(
        uint256 index,
        address l2Sender,
        address to,
        uint256 l2Block,
        uint256 l1Block,
        uint256 l2Timestamp,
        uint256 value,
        bytes calldata data
    ) external {
        if (msg.sender != address(0)) revert SimulationOnlyEntrypoint();
        executeTransactionImpl(index, l2Sender, to, l2Block, l1Block, l2Timestamp, value, data);
    }

    function executeTransactionImpl(
        uint256 outputId,
        address l2Sender,
        address to,
        uint256 l2Block,
        uint256 l1Block,
        uint256 l2Timestamp,
        uint256 value,
        bytes calldata data
    ) internal {
        emit OutBoxTransactionExecuted(to, l2Sender, 0, outputId);

        // we temporarily store the previous values so the outbox can naturally
        // unwind itself when there are nested calls to `executeTransaction`
        // L2ToL1Context memory prevContext = context;
        uint256 prevSender; 
        uint256 prevL2Block; 
        uint256 prevL1Block; 
        uint256 prevTimestamp;
        uint256 prevOutputId;
        uint256 prevWithdrawalAmount;
        assembly {
            prevSender := tload(L2_TO_L1_SENDER_TSLOT)
            prevL2Block := tload(L2_BLOCK_TSLOT)
            prevL1Block := tload(L1_BLOCK_TSLOT)
            prevTimestamp := tload(L2_TO_L1_TIMESTAMP_TSLOT)
            prevOutputId := tload(L2_TO_L1_OUTPUT_ID_TSLOT)
            prevWithdrawalAmount := tload(L2_TO_L1_WITHDRAWAL_AMOUNT_TSLOT)
        }

        // context = L2ToL1Context({
        //     sender: l2Sender,
        //     l2Block: uint128(l2Block),
        //     l1Block: uint96(l1Block),
        //     timestamp: uint128(l2Timestamp),
        //     outputId: bytes32(outputId),
        //     withdrawalAmount: _amountToSetInContext(value)
        // });
        uint256 _withdrawalAmount = _amountToSetInContext(value);
        assembly {
            tstore(L2_TO_L1_SENDER_TSLOT, l2Sender)
            tstore(L2_BLOCK_TSLOT, l2Block)
            tstore(L1_BLOCK_TSLOT, l1Block)
            tstore(L2_TO_L1_TIMESTAMP_TSLOT, l2Timestamp)
            tstore(L2_TO_L1_OUTPUT_ID_TSLOT, outputId)
            tstore(L2_TO_L1_WITHDRAWAL_AMOUNT_TSLOT, _withdrawalAmount)
        }

        // set and reset vars around execution so they remain valid during call
        executeBridgeCall(to, value, data);

        assembly {
            tstore(L2_TO_L1_SENDER_TSLOT, prevSender)
            tstore(L2_BLOCK_TSLOT, prevL2Block)
            tstore(L1_BLOCK_TSLOT, prevL1Block)
            tstore(L2_TO_L1_TIMESTAMP_TSLOT, prevTimestamp)
            tstore(L2_TO_L1_OUTPUT_ID_TSLOT, prevOutputId)
            tstore(L2_TO_L1_WITHDRAWAL_AMOUNT_TSLOT, prevWithdrawalAmount)
        }    
    }

    function _calcSpentIndexOffset(uint256 index)
        internal
        view
        returns (
            uint256,
            uint256,
            bytes32
        )
    {
        uint256 spentIndex = index / 255; // Note: Reserves the MSB.
        uint256 bitOffset = index % 255;
        bytes32 replay = spent[spentIndex];
        return (spentIndex, bitOffset, replay);
    }

    function _isSpent(uint256 bitOffset, bytes32 replay) internal pure returns (bool) {
        return ((replay >> bitOffset) & bytes32(uint256(1))) != bytes32(0);
    }

    /// @inheritdoc IOutbox
    function isSpent(uint256 index) external view returns (bool) {
        (, uint256 bitOffset, bytes32 replay) = _calcSpentIndexOffset(index);
        return _isSpent(bitOffset, replay);
    }

    function recordOutputAsSpent(
        bytes32[] memory proof,
        uint256 index,
        bytes32 item
    ) internal {
        if (proof.length >= 256) revert ProofTooLong(proof.length);
        if (index >= 2**proof.length) revert PathNotMinimal(index, 2**proof.length);

        // Hash the leaf an extra time to prove it's a leaf
        bytes32 calcRoot = calculateMerkleRoot(proof, index, item);
        if (roots[calcRoot] == bytes32(0)) revert UnknownRoot(calcRoot);

        (uint256 spentIndex, uint256 bitOffset, bytes32 replay) = _calcSpentIndexOffset(index);

        if (_isSpent(bitOffset, replay)) revert AlreadySpent(index);
        spent[spentIndex] = (replay | bytes32(1 << bitOffset));
    }

    function executeBridgeCall(
        address to,
        uint256 value,
        bytes memory data
    ) internal {
        (bool success, bytes memory returndata) = bridge.executeCall(to, value, data);
        if (!success) {
            if (returndata.length > 0) {
                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert BridgeCallFailed();
            }
        }
    }

    function calculateItemHash(
        address l2Sender,
        address to,
        uint256 l2Block,
        uint256 l1Block,
        uint256 l2Timestamp,
        uint256 value,
        bytes calldata data
    ) public pure returns (bytes32) {
        return
            keccak256(abi.encodePacked(l2Sender, to, l2Block, l1Block, l2Timestamp, value, data));
    }

    function calculateMerkleRoot(
        bytes32[] memory proof,
        uint256 path,
        bytes32 item
    ) public pure returns (bytes32) {
        return MerkleLib.calculateRoot(proof, path, keccak256(abi.encodePacked(item)));
    }

    /// @notice value to be set for 'amount' field in L2ToL1Context during L2 to L1 transaction execution.
    ///         In case of ERC20-based rollup this is the amount of native token being withdrawn. In case of standard ETH-based
    ///         rollup this amount shall always be 0, because amount of ETH being withdrawn can be read from msg.value.
    /// @return amount of native token being withdrawn in case of ERC20-based rollup, or 0 in case of ETH-based rollup
    function _amountToSetInContext(uint256 value) internal pure virtual returns (uint256);

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[42] private __gap;
}
