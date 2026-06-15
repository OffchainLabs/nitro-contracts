// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../../foundry/Rollup.t.sol";

// Additional coverage for the rollup side: negative/positive paths in
// RollupCore.createNewAssertion, RollupUserLogic.stakeOnNewAssertion, and the RollupAdminLogic
// admin surface that the existing test/foundry/Rollup.t.sol does not exercise.
//
// Inherits RollupTest to reuse its full deployment harness, constants and helpers
// (testSuccessCreateAssertion, firstState/firstMELState, etc). As a result the base suite's
// tests also run under this contract — that redundancy is the cost of harness reuse.
contract RollupCoverageTest is RollupTest {
    using GlobalStateLib for GlobalState;
    using MELStateLib for MELState;

    // Re-declared locally for vm.expectEmit (not declared in RollupTest). MELConfigSet is
    // inherited from RollupTest.
    event InboxSet(address inbox);
    event AssertionCreated(
        bytes32 indexed assertionHash,
        bytes32 indexed parentAssertionHash,
        AssertionInputs assertion,
        bytes32 nextParentChainBlockHash,
        bytes32 wasmModuleRoot,
        uint256 requiredStake,
        address challengeManager,
        uint64 confirmPeriodBlocks
    );

    // ---------------------------------------------------------------------------------------
    // createNewAssertion + RollupUserLogic
    // ---------------------------------------------------------------------------------------

    // A wrong nextParentChainBlockHash in the before-config no longer hashes to the prev
    // (genesis) stored config; locks in that nextParentChainBlockHash is part of the domain.
    function testRevertWrongConfigHash() public {
        AssertionState memory beforeState;
        beforeState.machineStatus = MachineStatus.FINISHED;
        AssertionInputs memory inputs = AssertionInputs({
            beforeStateData: BeforeStateData({
                prevPrevAssertionHash: bytes32(0),
                configData: ConfigData({
                    wasmModuleRoot: WASM_MODULE_ROOT,
                    requiredStake: BASE_STAKE,
                    challengeManager: address(challengeManager),
                    confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
                    nextParentChainBlockHash: keccak256("WRONG_CONFIG_TARGET")
                })
            }),
            beforeState: beforeState,
            afterState: firstState,
            afterMELState: firstMELState
        });

        vm.prank(validator1);
        vm.expectRevert("CONFIG_HASH_MISMATCH");
        userRollup.newStakeOnNewAssertion({
            tokenAmount: BASE_STAKE,
            assertion: inputs,
            expectedAssertionHash: bytes32(0),
            _withdrawalAddress: validator1Withdrawal
        });
    }

    // A non-terminal afterState (RUNNING) is rejected.
    function testRevertBadAfterStatus() public {
        AssertionState memory beforeState;
        beforeState.machineStatus = MachineStatus.FINISHED;
        AssertionState memory afterState = firstState;
        afterState.machineStatus = MachineStatus.RUNNING;

        AssertionInputs memory inputs = AssertionInputs({
            beforeStateData: BeforeStateData({
                prevPrevAssertionHash: bytes32(0),
                configData: ConfigData({
                    wasmModuleRoot: WASM_MODULE_ROOT,
                    requiredStake: BASE_STAKE,
                    challengeManager: address(challengeManager),
                    confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
                    nextParentChainBlockHash: firstAssertionParentChainBlockHash
                })
            }),
            beforeState: beforeState,
            afterState: afterState,
            afterMELState: firstMELState
        });

        vm.prank(validator1);
        vm.expectRevert("BAD_AFTER_STATUS");
        userRollup.newStakeOnNewAssertion({
            tokenAmount: BASE_STAKE,
            assertion: inputs,
            expectedAssertionHash: bytes32(0),
            _withdrawalAddress: validator1Withdrawal
        });
    }

    // An assertion cannot be built on top of an ERRORED before-state. We first create an
    // errored assertion on genesis, then attempt a follow-up using that errored state as the
    // before-state (so it authenticates against the errored prev, then hits BAD_PREV_STATUS).
    function testRevertBadPrevStatus() public {
        // 1) errored assertion on genesis
        AssertionState memory genesisBefore;
        genesisBefore.machineStatus = MachineStatus.FINISHED;
        AssertionState memory erroredState = firstState;
        erroredState.machineStatus = MachineStatus.ERRORED;
        bytes32 erroredHash = RollupLib.assertionHash(genesisHash, erroredState);

        vm.prank(validator1);
        userRollup.newStakeOnNewAssertion({
            tokenAmount: BASE_STAKE,
            assertion: AssertionInputs({
                beforeStateData: BeforeStateData({
                    prevPrevAssertionHash: bytes32(0),
                    configData: ConfigData({
                        wasmModuleRoot: WASM_MODULE_ROOT,
                        requiredStake: BASE_STAKE,
                        challengeManager: address(challengeManager),
                        confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
                        nextParentChainBlockHash: firstAssertionParentChainBlockHash
                    })
                }),
                beforeState: genesisBefore,
                afterState: erroredState,
                afterMELState: firstMELState
            }),
            expectedAssertionHash: erroredHash,
            _withdrawalAddress: validator1Withdrawal
        });
        bytes32 nextParentChainBlockHash = blockhash(block.number - 1);

        // 2) follow-up whose before-state is the errored state -> BAD_PREV_STATUS
        AssertionState memory afterState = firstState; // FINISHED, MEL slot consistent
        vm.roll(block.number + 75);
        vm.prank(validator2);
        vm.expectRevert("BAD_PREV_STATUS");
        userRollup.newStakeOnNewAssertion({
            tokenAmount: BASE_STAKE,
            assertion: AssertionInputs({
                beforeStateData: BeforeStateData({
                    prevPrevAssertionHash: genesisHash,
                    configData: ConfigData({
                        wasmModuleRoot: WASM_MODULE_ROOT,
                        requiredStake: BASE_STAKE,
                        challengeManager: address(challengeManager),
                        confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
                        nextParentChainBlockHash: nextParentChainBlockHash
                    })
                }),
                beforeState: erroredState,
                afterState: afterState,
                afterMELState: firstMELState
            }),
            expectedAssertionHash: bytes32(0),
            _withdrawalAddress: validator2Withdrawal
        });
    }

    // A follow-up whose ExecutedMsgCount regresses below the before-state is rejected.
    function testRevertExecutedMessagesBackwards() public {
        (
            bytes32 beforeAssertionHash,
            AssertionState memory beforeState,
            MELState memory beforeMELState,
            bytes32 nextParentChainBlockHash
        ) = testSuccessCreateAssertion();

        MELState memory afterMELState = beforeMELState;
        afterMELState.parentChainBlockHash = nextParentChainBlockHash;

        AssertionState memory afterState;
        afterState.machineStatus = MachineStatus.FINISHED;
        afterState.globalState.u64Vals[0] = beforeState.globalState.u64Vals[0];
        // ExecutedMsgCount goes backwards (before is INITIAL_MSG_COUNT = 1)
        afterState.globalState.u64Vals[1] = beforeState.globalState.u64Vals[1] - 1;
        afterState.globalState.bytes32Vals[2] = afterMELState.hash();
        bytes32 expectedHash = RollupLib.assertionHash(beforeAssertionHash, afterState);

        vm.roll(block.number + 75);
        vm.prank(validator1);
        vm.expectRevert("INBOX_BACKWARDS");
        userRollup.stakeOnNewAssertion({
            assertion: AssertionInputs({
                beforeStateData: BeforeStateData({
                    prevPrevAssertionHash: genesisHash,
                    configData: ConfigData({
                        wasmModuleRoot: WASM_MODULE_ROOT,
                        requiredStake: BASE_STAKE,
                        challengeManager: address(challengeManager),
                        confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
                        nextParentChainBlockHash: nextParentChainBlockHash
                    })
                }),
                beforeState: beforeState,
                afterState: afterState,
                afterMELState: afterMELState
            }),
            expectedAssertionHash: expectedHash
        });
    }

    // An overflow assertion (msgCount > ExecutedMsgCount) that makes no execution progress
    // over its before-state is rejected.
    function testRevertOverflowStandstill() public {
        (
            bytes32 beforeAssertionHash,
            AssertionState memory beforeState,
            MELState memory beforeMELState,
            bytes32 nextParentChainBlockHash
        ) = testSuccessCreateAssertion();

        MELState memory afterMELState = beforeMELState;
        afterMELState.parentChainBlockHash = nextParentChainBlockHash;
        afterMELState.msgCount = beforeMELState.msgCount + 4; // extraction ran ahead

        AssertionState memory afterState;
        afterState.machineStatus = MachineStatus.FINISHED;
        afterState.globalState.u64Vals[0] = beforeState.globalState.u64Vals[0];
        // no execution progress: ExecutedMsgCount equals the before-state's
        afterState.globalState.u64Vals[1] = beforeState.globalState.u64Vals[1];
        afterState.globalState.bytes32Vals[2] = afterMELState.hash();
        bytes32 expectedHash = RollupLib.assertionHash(beforeAssertionHash, afterState);

        vm.roll(block.number + 75);
        vm.prank(validator1);
        vm.expectRevert("OVERFLOW_STANDSTILL");
        userRollup.stakeOnNewAssertion({
            assertion: AssertionInputs({
                beforeStateData: BeforeStateData({
                    prevPrevAssertionHash: genesisHash,
                    configData: ConfigData({
                        wasmModuleRoot: WASM_MODULE_ROOT,
                        requiredStake: BASE_STAKE,
                        challengeManager: address(challengeManager),
                        confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
                        nextParentChainBlockHash: nextParentChainBlockHash
                    })
                }),
                beforeState: beforeState,
                afterState: afterState,
                afterMELState: afterMELState
            }),
            expectedAssertionHash: expectedHash
        });
    }

    // A non-overflow assertion created sooner than minimumAssertionPeriod (75) is rejected.
    function testRevertCreateAssertionTimeDelta() public {
        (
            bytes32 beforeAssertionHash,
            AssertionState memory beforeState,
            MELState memory beforeMELState,
            bytes32 nextParentChainBlockHash
        ) = testSuccessCreateAssertion();

        MELState memory afterMELState = beforeMELState;
        afterMELState.parentChainBlockHash = nextParentChainBlockHash;
        afterMELState.msgCount = beforeMELState.msgCount + 1;

        AssertionState memory afterState;
        afterState.machineStatus = MachineStatus.FINISHED;
        afterState.globalState.u64Vals[0] = beforeState.globalState.u64Vals[0] + 1;
        // execution keeps up with extraction => NOT an overflow assertion
        afterState.globalState.u64Vals[1] = beforeState.globalState.u64Vals[1] + 1;
        afterState.globalState.bytes32Vals[2] = afterMELState.hash();
        bytes32 expectedHash = RollupLib.assertionHash(beforeAssertionHash, afterState);

        // only +1 block (< minimumAssertionPeriod), but >= 1 so SAME_BLOCK_ASSERTION passes
        vm.roll(block.number + 1);
        vm.prank(validator1);
        vm.expectRevert("TIME_DELTA");
        userRollup.stakeOnNewAssertion({
            assertion: AssertionInputs({
                beforeStateData: BeforeStateData({
                    prevPrevAssertionHash: genesisHash,
                    configData: ConfigData({
                        wasmModuleRoot: WASM_MODULE_ROOT,
                        requiredStake: BASE_STAKE,
                        challengeManager: address(challengeManager),
                        confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
                        nextParentChainBlockHash: nextParentChainBlockHash
                    })
                }),
                beforeState: beforeState,
                afterState: afterState,
                afterMELState: afterMELState
            }),
            expectedAssertionHash: expectedHash
        });
    }

    // An overflow assertion (with execution progress) is exempt from minimumAssertionPeriod
    // and can be created back-to-back (+1 block).
    function testSuccessOverflowAssertionSkipsTimeDelta() public {
        (
            bytes32 beforeAssertionHash,
            AssertionState memory beforeState,
            MELState memory beforeMELState,
            bytes32 nextParentChainBlockHash
        ) = testSuccessCreateAssertion();

        MELState memory afterMELState = beforeMELState;
        afterMELState.parentChainBlockHash = nextParentChainBlockHash;
        afterMELState.msgCount = beforeMELState.msgCount + 4; // extraction ahead of execution

        AssertionState memory afterState;
        afterState.machineStatus = MachineStatus.FINISHED;
        afterState.globalState.u64Vals[0] = beforeState.globalState.u64Vals[0] + 1;
        // some progress over before-state (so it's not a standstill), but still < msgCount
        afterState.globalState.u64Vals[1] = beforeState.globalState.u64Vals[1] + 1;
        afterState.globalState.bytes32Vals[2] = afterMELState.hash();
        bytes32 expectedHash = RollupLib.assertionHash(beforeAssertionHash, afterState);

        vm.roll(block.number + 1); // back-to-back; would fail TIME_DELTA if not overflow
        vm.prank(validator1);
        userRollup.stakeOnNewAssertion({
            assertion: AssertionInputs({
                beforeStateData: BeforeStateData({
                    prevPrevAssertionHash: genesisHash,
                    configData: ConfigData({
                        wasmModuleRoot: WASM_MODULE_ROOT,
                        requiredStake: BASE_STAKE,
                        challengeManager: address(challengeManager),
                        confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
                        nextParentChainBlockHash: nextParentChainBlockHash
                    })
                }),
                beforeState: beforeState,
                afterState: afterState,
                afterMELState: afterMELState
            }),
            expectedAssertionHash: expectedHash
        });

        assertTrue(
            userRollup.getAssertion(expectedHash).status == AssertionStatus.Pending,
            "overflow assertion should have been created"
        );
    }

    // ---------------------------------------------------------------------------------------
    // RollupAdminLogic admin surface
    // ---------------------------------------------------------------------------------------

    // The first MEL config must be version 0.
    function testRevertSetMELConfigInitialVersionNonZero() public {
        vm.prank(upgradeExecutorAddr);
        vm.expectRevert("INVALID_MEL_VERSION");
        adminRollup.setMELConfig(1, address(0xdead01), address(0xdead02));
    }

    // A later MEL config must strictly increase the version; success path v0 -> v2.
    function testSuccessSetMELConfigVersionIncrease() public {
        address inbox2 = address(0xdead11);
        address seqInbox2 = address(0xdead12);

        vm.startPrank(upgradeExecutorAddr);
        adminRollup.setMELConfig(0, address(0xdead01), address(0xdead02));
        bytes32 hash0 = userRollup.currentMelConfigHash();
        adminRollup.setMELConfig(2, inbox2, seqInbox2);
        vm.stopPrank();

        bytes32 hash2 = userRollup.currentMelConfigHash();
        assertTrue(hash2 != hash0, "currentMelConfigHash should advance");

        (uint64 version, address inbox, address sequencerInbox,) = userRollup.melConfig(hash2);
        assertEq(uint256(version), 2, "stored version should be 2");
        assertEq(inbox, inbox2, "stored inbox");
        assertEq(sequencerInbox, seqInbox2, "stored sequencerInbox");
        assertEq(address(userRollup.inbox()), inbox2, "inbox pointer should update");
    }

    // Re-setting the same version (not strictly increasing) is rejected.
    function testRevertSetMELConfigVersionNotIncreasing() public {
        vm.startPrank(upgradeExecutorAddr);
        adminRollup.setMELConfig(0, address(0xdead01), address(0xdead02));
        vm.expectRevert("INVALID_MEL_VERSION");
        adminRollup.setMELConfig(0, address(0xdead01), address(0xdead02));
        vm.stopPrank();
    }

    // setMELConfig is gated to the proxy admin (upgrade executor).
    function testRevertSetMELConfigNotOwner() public {
        vm.expectRevert();
        adminRollup.setMELConfig(0, address(0xdead01), address(0xdead02));
    }

    // Standalone setInbox updates the inbox pointer and emits InboxSet.
    function testSuccessSetInbox() public {
        address newInbox = address(0xb0b1);
        vm.expectEmit(true, true, true, true);
        emit InboxSet(newInbox);
        vm.prank(upgradeExecutorAddr);
        adminRollup.setInbox(IInboxBase(newInbox));
        assertEq(address(userRollup.inbox()), newInbox, "inbox pointer should update");
    }

    // setInbox is gated to the proxy admin (upgrade executor).
    function testRevertSetInboxNotOwner() public {
        vm.expectRevert();
        adminRollup.setInbox(IInboxBase(address(0xb0b1)));
    }

    // ---------------------------------------------------------------------------------------
    // Hash-domain / event / genesis
    // ---------------------------------------------------------------------------------------

    // configHash unit test — the preimage includes nextParentChainBlockHash.
    function testConfigHash() public {
        bytes32 expected = keccak256(
            abi.encodePacked(
                WASM_MODULE_ROOT,
                uint256(BASE_STAKE),
                address(challengeManager),
                CONFIRM_PERIOD_BLOCKS,
                firstAssertionParentChainBlockHash
            )
        );
        bytes32 actual = RollupLib.configHash(
            WASM_MODULE_ROOT,
            BASE_STAKE,
            address(challengeManager),
            CONFIRM_PERIOD_BLOCKS,
            firstAssertionParentChainBlockHash
        );
        assertEq(actual, expected, "configHash must commit nextParentChainBlockHash");
    }

    // AssertionCreated carries nextParentChainBlockHash == blockhash(block.number - 1).
    function testAssertionCreatedEvent() public {
        AssertionState memory beforeState;
        beforeState.machineStatus = MachineStatus.FINISHED;
        AssertionInputs memory inputs = AssertionInputs({
            beforeStateData: BeforeStateData({
                prevPrevAssertionHash: bytes32(0),
                configData: ConfigData({
                    wasmModuleRoot: WASM_MODULE_ROOT,
                    requiredStake: BASE_STAKE,
                    challengeManager: address(challengeManager),
                    confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
                    nextParentChainBlockHash: firstAssertionParentChainBlockHash
                })
            }),
            beforeState: beforeState,
            afterState: firstState,
            afterMELState: firstMELState
        });
        bytes32 expectedHash = RollupLib.assertionHash(genesisHash, firstState);

        vm.expectEmit(true, true, false, true);
        emit AssertionCreated(
            expectedHash,
            genesisHash,
            inputs,
            blockhash(block.number - 1),
            WASM_MODULE_ROOT,
            BASE_STAKE,
            address(challengeManager),
            CONFIRM_PERIOD_BLOCKS
        );
        vm.prank(validator1);
        userRollup.newStakeOnNewAssertion({
            tokenAmount: BASE_STAKE,
            assertion: inputs,
            expectedAssertionHash: expectedHash,
            _withdrawalAddress: validator1Withdrawal
        });
    }

    // The genesis config hash commits nextParentChainBlockHash = blockhash(block.number - 1)
    // captured at initialize time.
    function testGenesisConfigHashCommitsParentChainBlockHash() public {
        // the correct config validates against the stored genesis config hash
        userRollup.validateConfig(
            genesisHash,
            ConfigData({
                wasmModuleRoot: WASM_MODULE_ROOT,
                requiredStake: BASE_STAKE,
                challengeManager: address(challengeManager),
                confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
                nextParentChainBlockHash: firstAssertionParentChainBlockHash
            })
        );
        // a wrong nextParentChainBlockHash does not -> it is part of the genesis config domain
        vm.expectRevert("CONFIG_HASH_MISMATCH");
        userRollup.validateConfig(
            genesisHash,
            ConfigData({
                wasmModuleRoot: WASM_MODULE_ROOT,
                requiredStake: BASE_STAKE,
                challengeManager: address(challengeManager),
                confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
                nextParentChainBlockHash: keccak256("WRONG_GENESIS_TARGET")
            })
        );
    }
}
