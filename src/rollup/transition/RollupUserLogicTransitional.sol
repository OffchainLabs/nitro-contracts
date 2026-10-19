// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "../RollupUserLogic.sol";
import "./RollupCoreTransition.sol";
import "./IRollupUserTransition.sol";

/// @notice User implementation supporting both MEL and pre-MEL parent configs.
/// @dev Install this implementation while legacy assertions and challenges need support.
///      Adds no storage to RollupUserLogic.
contract RollupUserLogicTransitional is
    RollupUserLogic,
    RollupCoreTransition,
    IRollupUserTransition
{
    using GlobalStateLib for GlobalState;
    using SafeERC20 for IERC20;

    function confirmAssertion(
        bytes32 assertionHash,
        bytes32 prevAssertionHash,
        AssertionState calldata confirmState,
        bytes32 winningEdgeId,
        LegacyConfigData calldata prevConfig,
        bytes32 inboxAcc
    ) external onlyValidator(msg.sender) whenNotPaused {
        // prevAssertionHash is user supplied, but will be validated in RollupCore.confirmAssertionInternal
        AssertionNode storage prevAssertion = getAssertionStorage(prevAssertionHash);
        LegacyRollupLib.validateConfigHash(prevConfig, prevAssertion.configHash);

        _confirmAssertionImpl(
            assertionHash,
            prevAssertionHash,
            confirmState,
            winningEdgeId,
            prevConfig.confirmPeriodBlocks,
            prevConfig.challengeManager,
            prevAssertion.secondChildBlock > 0,
            inboxAcc
        );
    }

    /**
     * @notice Create a new assertion and move stake onto it
     * @param assertion The legacy assertion data
     * @param expectedAssertionHash The hash of the assertion being created (protects against reorgs)
     */
    function stakeOnNewAssertion(
        LegacyAssertionInputs calldata assertion,
        bytes32 expectedAssertionHash
    ) public onlyValidator(msg.sender) whenNotPaused {
        bytes32 parentAssertionHash = _checkAssertionAndStakingInformation(
            assertion.beforeState,
            assertion.beforeStateData.prevPrevAssertionHash,
            assertion.beforeStateData.sequencerBatchAcc,
            assertion.beforeStateData.configData.requiredStake,
            expectedAssertionHash
        );

        (bytes32 newAssertionHash, bool overflowAssertion) =
            createNewAssertion(assertion, parentAssertionHash, expectedAssertionHash);

        _completeAssertionCreation(
            newAssertionHash,
            parentAssertionHash,
            assertion.beforeStateData.configData.requiredStake,
            overflowAssertion
        );
    }

    function fastConfirmNewAssertion(
        LegacyAssertionInputs calldata assertion,
        bytes32 expectedAssertionHash
    ) external whenNotPaused {
        (AssertionStatus status, bytes32 prevAssertion) = _fastConfirmNewAssertionChecks(
            assertion.beforeState,
            assertion.beforeStateData.prevPrevAssertionHash,
            assertion.beforeStateData.sequencerBatchAcc,
            expectedAssertionHash
        );

        if (status == AssertionStatus.NoAssertion) {
            // If not exists, we create the new assertion
            (bytes32 newAssertionHash,) =
                createNewAssertion(assertion, prevAssertion, expectedAssertionHash);
            if (!getAssertionStorage(newAssertionHash).isFirstChild) {
                // only 1 of the children can be confirmed and get their stake refunded
                // so we send the other children's stake to the loserStakeEscrow
                // NOTE: if the losing staker have staked more than requiredStake, the excess stake will be stuck
                IERC20(stakeToken)
                    .safeTransfer(
                        loserStakeEscrow, assertion.beforeStateData.configData.requiredStake
                    );
            }
        }

        _fastConfirmNewAssertionConfirmationImpl(
            assertion.afterState.globalState.getInboxPosition(),
            expectedAssertionHash,
            prevAssertion,
            assertion.afterState
        );
    }

    /**
     * @notice Deprecated, use the function with `withdrawalAddress` instead
     *         Using this default `withdrawalAddress` to msg.sender
     */
    function newStakeOnNewAssertion(
        uint256 tokenAmount,
        LegacyAssertionInputs calldata assertion,
        bytes32 expectedAssertionHash
    ) external {
        newStakeOnNewAssertion(tokenAmount, assertion, expectedAssertionHash, msg.sender);
    }

    /**
     * @notice Create a new stake on a new assertion
     * @param tokenAmount Amount of the rollups staking token to stake
     * @param assertion Assertion describing the state change between the old assertion and the new one
     * @param expectedAssertionHash Assertion hash of the assertion that will be created
     * @param _withdrawalAddress The address the send the stake back upon withdrawal
     */
    function newStakeOnNewAssertion(
        uint256 tokenAmount,
        LegacyAssertionInputs calldata assertion,
        bytes32 expectedAssertionHash,
        address _withdrawalAddress
    ) public {
        require(_withdrawalAddress != address(0), "EMPTY_WITHDRAWAL_ADDRESS");
        // _newStake makes sure the validator is whitelisted if the whitelist is enabled
        _newStake(tokenAmount, _withdrawalAddress);
        stakeOnNewAssertion(assertion, expectedAssertionHash);
        /// @dev This is an external call, safe because it's at the end of the function
        receiveTokens(tokenAmount);
    }
}
