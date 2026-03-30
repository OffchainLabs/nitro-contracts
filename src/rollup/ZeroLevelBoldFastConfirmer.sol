// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import {AssertionInputs} from "./Assertion.sol";
import {AssertionState, AssertionStateLib} from "./AssertionState.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    EIP712Upgradeable
} from "@openzeppelin/contracts-upgradeable/utils/cryptography/draft-EIP712Upgradeable.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IRollupUser} from "./IRollupLogic.sol";

// dummy interface for the SNARK verifier.
interface ISnarkVerifier {
    function verifyProof(
        bytes calldata inputS
    ) external view returns (bool);
}

contract ZeroLevelBoldFastConfirmer is OwnableUpgradeable, EIP712Upgradeable {
    using AssertionStateLib for AssertionState;

    bytes32 public constant FAST_CONFIRM_TYPEHASH =
        keccak256("FastConfirmAssertion(bytes32 assertionHash)");

    /// @notice The rollup contract to fast confirm on
    IRollupUser public rollup;

    /// @notice Gnosis Safe multisig address of the guardian council
    address public guardianCouncil;

    /// @notice SNARK verifier contract address
    ISnarkVerifier public snarkVerifier;

    error InvalidGuardianSignature();
    error InvalidSnarkProof();

    event GuardianCouncilSet(address indexed newGuardianCouncil);

    function initialize(
        address _rollup,
        address _guardianCouncil,
        address _initialOwner,
        address _snarkVerifier
    ) public initializer {
        __Ownable_init();
        __EIP712_init("ZeroLevelBoldFastConfirmer", "1");
        rollup = IRollupUser(_rollup);
        guardianCouncil = _guardianCouncil;
        _transferOwnership(_initialOwner);
        snarkVerifier = ISnarkVerifier(_snarkVerifier);
    }

    function fastConfirmAssertion(
        bytes32 assertionHash,
        bytes32 parentAssertionHash,
        AssertionState calldata confirmState,
        bytes32 inboxAcc,
        bytes calldata guardianSignature,
        bytes calldata snarkProof
    ) public {
        _verifyProofs(assertionHash, guardianSignature, snarkProof);
        rollup.fastConfirmAssertion(assertionHash, parentAssertionHash, confirmState, inboxAcc);
    }

    function fastConfirmNewAssertion(
        AssertionInputs calldata assertion,
        bytes32 assertionHash,
        bytes calldata guardianSignature,
        bytes calldata snarkProof
    ) external {
        _verifyProofs(assertionHash, guardianSignature, snarkProof);
        rollup.fastConfirmNewAssertion(assertion, assertionHash);
    }

    function getFastConfirmAssertionMessageDigest(
        bytes32 assertionHash
    ) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(FAST_CONFIRM_TYPEHASH, assertionHash)));
    }

    function setGuardianCouncil(
        address _guardianCouncil
    ) external onlyOwner {
        guardianCouncil = _guardianCouncil;
        emit GuardianCouncilSet(_guardianCouncil);
    }

    function setSnarkVerifier(
        address _snarkVerifier
    ) external onlyOwner {
        snarkVerifier = ISnarkVerifier(_snarkVerifier);
    }

    function _verifyProofs(
        bytes32 assertionHash,
        bytes calldata guardianSignature,
        bytes calldata snarkProof
    ) internal view {
        bytes32 messageDigest = getFastConfirmAssertionMessageDigest(assertionHash);
        if (
            IERC1271(guardianCouncil).isValidSignature(messageDigest, guardianSignature)
                != 0x1626ba7e
        ) {
            revert InvalidGuardianSignature();
        }

        if (!snarkVerifier.verifyProof(snarkProof)) {
            revert InvalidSnarkProof();
        }
    }
}
