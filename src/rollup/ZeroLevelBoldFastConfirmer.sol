// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

// dummy interface for the SNARK verifier.
interface ISnarkVerifier {
    function verifyProof(bytes calldata inputS) external view returns (bool);
}

contract ZeroLevelBoldFastConfirmer is OwnableUpgradeable {
    /// @notice Gnosis Safe multisig address of the guardian council
    address public guardianCouncil;

    /// @notice SNARK verifier contract address
    ISnarkVerifier public snarkVerifier;

    event GuardianCouncilSet(address indexed newGuardianCouncil);

    function initialize(address _guardianCouncil, address _initialOwner, address _snarkVerifier) public initializer {
        __Ownable_init();
        guardianCouncil = _guardianCouncil;
        _transferOwnership(_initialOwner);
        snarkVerifier = ISnarkVerifier(_snarkVerifier);
    }

    /// @notice Fast confirms an assertion
    /// @dev    MUST revert if we cannot validate the guardian council signatures or the SNARK
    function fastConfirmAssertion(
        bytes32 assertionHash,
        bytes32 parentAssertionHash,
        AssertionState calldata confirmState,
        bytes32 inboxAcc
    ) public {
        // todo: check 1271 of guardian council
        // todo: check snark
        // todo: confirm the assertion
    }

    function setGuardianCouncil(address _guardianCouncil) external onlyOwner {
        guardianCouncil = _guardianCouncil;
        emit GuardianCouncilSet(_guardianCouncil);
    }

    function setSnarkVerifier(address _snarkVerifier) external onlyOwner {
        snarkVerifier = ISnarkVerifier(_snarkVerifier);
    }
}