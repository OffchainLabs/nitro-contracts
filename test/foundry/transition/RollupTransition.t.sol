// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../../src/rollup/RollupProxy.sol";
import "../../../src/rollup/RollupCore.sol";
import "../../../src/rollup/RollupUserLogic.sol";
import "../../../src/rollup/RollupAdminLogic.sol";
import "../../../src/rollup/RollupCreator.sol";
import "../../../src/rollup/transition/RollupUserLogicTransitional.sol";
import "../../../src/osp/OneStepProver0.sol";
import "../../../src/osp/OneStepProverMemory.sol";
import "../../../src/osp/OneStepProverMath.sol";
import "../../../src/osp/OneStepProverHostIo.sol";
import "../../../src/osp/OneStepProofEntry.sol";
import "../../../src/challengeV2/EdgeChallengeManager.sol";
import "../../../src/mocks/TestWETH9.sol";
import "../../../src/mocks/UpgradeExecutorMock.sol";
import "./TransitionTestHelpers.sol";

/// @notice Deploys a stock rollup, confirms one MEL assertion on it, then upgrades both logic
///         contracts in place to the transitional implementations, as a live chain would.
///         The confirmed post-genesis assertion is then given a pre-MEL config hash, so every
///         test starts from an upgraded chain whose tip is still a pre-MEL assertion.
contract RollupTransitionTestBase is Test {
    address constant owner = address(1337);
    address constant sequencer = address(7331);
    address constant validator1 = address(100001);
    address constant validator2 = address(100002);
    address constant validator1Withdrawal = address(1000010);
    address constant loserStakeEscrow = address(200001);
    address constant anyTrustFastConfirmer = address(300001);

    bytes32 constant WASM_MODULE_ROOT = keccak256("WASM_MODULE_ROOT");
    uint256 constant BASE_STAKE = 10;
    uint64 constant CONFIRM_PERIOD_BLOCKS = 100;
    uint256 constant MAX_DATA_SIZE = 117964;
    uint64 constant CHALLENGE_GRACE_PERIOD_BLOCKS = 10;
    bytes32 constant GENESIS_ASSERTION_TARGET_PARENT_CHAIN_BLOCK_HASH = keccak256("genesis");

    // Legacy ChallengeManager used in pre-MEL assertions (only an address is needed)
    address constant legacyChallengeManagerAddress = address(0x1e8ac1c3);

    IERC20 token;
    address rollup;
    RollupUserLogicTransitional userRollup;
    RollupAdminLogicTransitionalTestHelper adminRollup;
    EdgeChallengeManager challengeManager;
    address upgradeExecutorAddr;
    uint256 minimumAssertionPeriod;

    GlobalState emptyGlobalState;
    AssertionState genesisAssertionState =
        AssertionState(emptyGlobalState, MachineStatus.FINISHED, bytes32(0));
    bytes32 genesisAssertionHash =
        RollupLib.assertionHash(bytes32(0), genesisAssertionState, bytes32(0));
    ConfigData genesisConfigData;

    // Empty assertion on top of genesis, confirmed in setUp as a MEL assertion and then
    // re-shaped as a pre-MEL one
    AssertionState postGenesisAssertionState =
        AssertionState(emptyGlobalState, MachineStatus.FINISHED, bytes32(0));
    bytes32 postGenesisAssertionHash =
        RollupLib.assertionHash(genesisAssertionHash, postGenesisAssertionState, bytes32(0));
    LegacyConfigData postGenesisConfigData;

    // Consumes the batch posted in setUp (the creator posts an initialization batch before it)
    AssertionState firstAssertionState;
    uint64 firstInboxCount;

    // For post-MEL assertions created on top of pre-MEL ones
    event AssertionCreated(
        bytes32 indexed assertionHash,
        bytes32 indexed parentAssertionHash,
        LegacyAssertionInputs assertion,
        bytes32 afterInboxBatchAcc,
        bytes32 targetParentChainBlockHash,
        bytes32 wasmModuleRoot,
        uint256 requiredStake,
        address challengeManager,
        uint64 confirmPeriodBlocks
    );

    IReader4844 dummyReader4844 = IReader4844(address(137));
    BridgeCreator.BridgeTemplates ethBasedTemplates = BridgeCreator.BridgeTemplates({
        bridge: new Bridge(),
        sequencerInbox: new SequencerInbox(MAX_DATA_SIZE, dummyReader4844, false, false),
        delayBufferableSequencerInbox: new SequencerInbox(
            MAX_DATA_SIZE, dummyReader4844, false, true
        ),
        inbox: new Inbox(MAX_DATA_SIZE),
        rollupEventInbox: new RollupEventInbox(),
        outbox: new Outbox()
    });
    BridgeCreator.BridgeTemplates erc20BasedTemplates = BridgeCreator.BridgeTemplates({
        bridge: new ERC20Bridge(),
        sequencerInbox: new SequencerInbox(MAX_DATA_SIZE, dummyReader4844, true, false),
        delayBufferableSequencerInbox: new SequencerInbox(
            MAX_DATA_SIZE, dummyReader4844, true, true
        ),
        inbox: new ERC20Inbox(MAX_DATA_SIZE),
        rollupEventInbox: new ERC20RollupEventInbox(),
        outbox: new ERC20Outbox()
    });

    function setUp() public {
        OneStepProver0 oneStepProver = new OneStepProver0();
        OneStepProverMemory oneStepProverMemory = new OneStepProverMemory();
        OneStepProverMath oneStepProverMath = new OneStepProverMath();
        OneStepProverHostIo oneStepProverHostIo = new OneStepProverHostIo(address(0));
        OneStepProofEntry oneStepProofEntry = new OneStepProofEntry(
            oneStepProver, oneStepProverMemory, oneStepProverMath, oneStepProverHostIo
        );
        EdgeChallengeManager edgeChallengeManager = new EdgeChallengeManager();

        BridgeCreator bridgeCreator = new BridgeCreator(ethBasedTemplates, erc20BasedTemplates);
        RollupAdminLogic rollupAdminLogicImpl = new RollupAdminLogic();
        RollupUserLogic rollupUserLogicImpl = new RollupUserLogic();
        DeployHelper deployHelper = new DeployHelper();
        IUpgradeExecutor upgradeExecutorLogic = new UpgradeExecutorMock();
        RollupCreator rollupCreator = new RollupCreator(
            address(this),
            bridgeCreator,
            oneStepProofEntry,
            edgeChallengeManager,
            rollupAdminLogicImpl,
            rollupUserLogicImpl,
            upgradeExecutorLogic,
            address(0),
            deployHelper
        );

        token = new TestWETH9("Test", "TEST");
        IWETH9(address(token)).deposit{value: 10 ether}();

        uint256[] memory miniStakeValues = new uint256[](5);
        miniStakeValues[0] = 1 ether;
        miniStakeValues[1] = 2 ether;
        miniStakeValues[2] = 3 ether;
        miniStakeValues[3] = 4 ether;
        miniStakeValues[4] = 5 ether;

        Config memory config = Config({
            baseStake: BASE_STAKE,
            chainId: 0,
            chainConfig: "{}",
            minimumAssertionPeriod: 75,
            validatorAfkBlocks: 201600,
            confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
            owner: owner,
            sequencerInboxMaxTimeVariation: ISequencerInbox.MaxTimeVariation({
                delayBlocks: (60 * 60 * 24) / 15,
                futureBlocks: 12,
                delaySeconds: 60 * 60 * 24,
                futureSeconds: 60 * 60
            }),
            stakeToken: address(token),
            wasmModuleRoot: WASM_MODULE_ROOT,
            loserStakeEscrow: loserStakeEscrow,
            genesisAssertionState: genesisAssertionState,
            miniStakeValues: miniStakeValues,
            layerZeroBlockEdgeHeight: 2 ** 5,
            layerZeroBigStepEdgeHeight: 2 ** 5,
            layerZeroSmallStepEdgeHeight: 2 ** 5,
            anyTrustFastConfirmer: anyTrustFastConfirmer,
            numBigStepLevel: 3,
            challengeGracePeriodBlocks: CHALLENGE_GRACE_PERIOD_BLOCKS,
            bufferConfig: BufferConfig({threshold: 600, max: 14400, replenishRateInBasis: 500}),
            dataCostEstimate: 0
        });
        RollupCreator.RollupDeploymentParams memory param = RollupCreator.RollupDeploymentParams({
            config: config,
            validators: new address[](0),
            maxDataSize: MAX_DATA_SIZE,
            nativeToken: address(0),
            deployFactoriesToL2: false,
            maxFeePerGasForRetryables: 0,
            batchPosters: new address[](0),
            batchPosterManager: address(0),
            feeTokenPricer: IFeeTokenPricer(address(0)),
            customOsp: address(0)
        });
        rollup = rollupCreator.createRollup(param);
        userRollup = RollupUserLogicTransitional(rollup);
        adminRollup = RollupAdminLogicTransitionalTestHelper(rollup);
        challengeManager = EdgeChallengeManager(address(userRollup.challengeManager()));
        upgradeExecutorAddr = userRollup.owner();

        address[] memory validatorList = new address[](2);
        validatorList[0] = validator1;
        validatorList[1] = validator2;
        bool[] memory flags = new bool[](2);
        flags[0] = true;
        flags[1] = true;
        vm.startPrank(upgradeExecutorAddr);
        adminRollup.setValidator(validatorList, flags);
        adminRollup.sequencerInbox().setIsBatchPoster(sequencer, true);
        vm.stopPrank();

        token.transfer(validator1, 1 ether);
        vm.prank(validator1);
        token.approve(rollup, type(uint256).max);
        token.transfer(validator2, 1 ether);
        vm.prank(validator2);
        token.approve(rollup, type(uint256).max);
        vm.deal(sequencer, 1 ether);

        // Advance `minimumAssertionPeriod` blocks
        minimumAssertionPeriod = userRollup.minimumAssertionPeriod();
        vm.roll(block.number + minimumAssertionPeriod);

        // Create a new batch
        // (in a regular chain, a batch will be posted before creating the postGenesis assertion)
        firstInboxCount = uint64(_createNewBatch());
        vm.roll(block.number + 2);

        // Create the first assertion (consumes no batches)
        // This is now a post-MEL assertion, but it's transformed into a pre-MEL assertion below
        genesisConfigData = ConfigData({
            wasmModuleRoot: WASM_MODULE_ROOT,
            requiredStake: BASE_STAKE,
            challengeManager: address(challengeManager),
            confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
            targetParentChainBlockHash: GENESIS_ASSERTION_TARGET_PARENT_CHAIN_BLOCK_HASH
        });
        AssertionInputs memory postGenesisInputs = AssertionInputs({
            beforeStateData: BeforeStateData({
                prevPrevAssertionHash: bytes32(0),
                sequencerBatchAcc: bytes32(0),
                configData: genesisConfigData
            }),
            beforeState: genesisAssertionState,
            afterState: postGenesisAssertionState
        });
        vm.prank(validator1);
        userRollup.newStakeOnNewAssertion(
            BASE_STAKE, postGenesisInputs, postGenesisAssertionHash, validator1Withdrawal
        );

        // Confirm it so new assertions can be created on top of it
        vm.roll(block.number + CONFIRM_PERIOD_BLOCKS + 1);
        vm.prank(validator1);
        userRollup.confirmAssertion(
            postGenesisAssertionHash,
            genesisAssertionHash,
            postGenesisAssertionState,
            bytes32(0),
            genesisConfigData,
            bytes32(0)
        );

        // Change the Rollup implementations to the transitional contracts
        vm.startPrank(upgradeExecutorAddr);
        adminRollup.upgradeTo(address(new RollupAdminLogicTransitionalTestHelper()));
        adminRollup.upgradeSecondaryTo(address(new RollupUserLogicTransitional()));
        vm.stopPrank();

        // Re-shape the confirmed assertion as a pre-MEL assertion, to simulate a pre-MEL chain that has been upgraded
        postGenesisConfigData = LegacyConfigData({
            wasmModuleRoot: WASM_MODULE_ROOT,
            requiredStake: BASE_STAKE,
            challengeManager: legacyChallengeManagerAddress,
            confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
            nextInboxPosition: firstInboxCount
        });
        _plantLegacyConfig(postGenesisAssertionHash, postGenesisConfigData);

        firstAssertionState =
            _getAssertionState(firstInboxCount, 0, MachineStatus.FINISHED, "first");

        // Advance `minimumAssertionPeriod` blocks again
        vm.roll(block.number + minimumAssertionPeriod);
    }

    function _createNewBatch() internal returns (uint256) {
        uint256 count = userRollup.bridge().sequencerMessageCount();
        vm.startPrank(sequencer);
        userRollup.sequencerInbox().addSequencerL2Batch({
            sequenceNumber: count,
            data: "",
            afterDelayedMessagesRead: 1,
            gasRefunder: IGasRefunder(address(0)),
            prevMessageCount: 0,
            newMessageCount: 0
        });
        vm.stopPrank();
        assertEq(userRollup.bridge().sequencerMessageCount(), ++count);
        return count;
    }

    /// @dev Craft a MEL configuration for an assertion
    function _craftMelConfig(
        bytes32 targetParentChainBlockHash
    ) internal view returns (ConfigData memory) {
        return ConfigData({
            wasmModuleRoot: WASM_MODULE_ROOT,
            requiredStake: BASE_STAKE,
            challengeManager: address(challengeManager),
            confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
            targetParentChainBlockHash: targetParentChainBlockHash
        });
    }

    /// @dev Modify the config hash of an assertion to use a legacy configuration
    function _plantLegacyConfig(
        bytes32 assertionHash,
        LegacyConfigData memory config
    ) internal {
        vm.prank(upgradeExecutorAddr);
        adminRollup.setConfigHash(
            assertionHash,
            LegacyRollupLib.legacyConfigHash(
                config.wasmModuleRoot,
                config.requiredStake,
                config.challengeManager,
                config.confirmPeriodBlocks,
                config.nextInboxPosition
            )
        );
    }

    function _getMelAssertionInputs(
        bytes32 prevPrevAssertionHash,
        bytes32 sequencerBatchAcc,
        ConfigData memory config,
        AssertionState memory beforeState,
        AssertionState memory afterState
    ) internal pure returns (AssertionInputs memory) {
        return AssertionInputs({
            beforeStateData: BeforeStateData({
                prevPrevAssertionHash: prevPrevAssertionHash,
                sequencerBatchAcc: sequencerBatchAcc,
                configData: config
            }),
            beforeState: beforeState,
            afterState: afterState
        });
    }

    function _getLegacyAssertionInputs(
        bytes32 prevPrevAssertionHash,
        bytes32 sequencerBatchAcc,
        LegacyConfigData memory config,
        AssertionState memory beforeState,
        AssertionState memory afterState
    ) internal pure returns (LegacyAssertionInputs memory) {
        return LegacyAssertionInputs({
            beforeStateData: LegacyBeforeStateData({
                prevPrevAssertionHash: prevPrevAssertionHash,
                sequencerBatchAcc: sequencerBatchAcc,
                configData: config
            }),
            beforeState: beforeState,
            afterState: afterState
        });
    }

    /// @dev LegacyAssertionInputs for a child of the pre-MEL (legacy) postGenesis assertion (shortcut)
    function _getLegacyAssertionInputs(
        AssertionState memory afterState
    ) internal view returns (LegacyAssertionInputs memory) {
        return _getLegacyAssertionInputs(
            genesisAssertionHash,
            bytes32(0),
            postGenesisConfigData,
            postGenesisAssertionState,
            afterState
        );
    }

    function _getAssertionState(
        uint64 inboxPosition,
        uint64 positionInMessage,
        MachineStatus status,
        string memory salt
    ) internal pure returns (AssertionState memory state) {
        state.globalState.bytes32Vals[0] = keccak256(abi.encodePacked(salt, "blockhash"));
        state.globalState.bytes32Vals[1] = keccak256(abi.encodePacked(salt, "sendroot"));
        state.globalState.u64Vals[0] = inboxPosition;
        state.globalState.u64Vals[1] = positionInMessage;
        state.machineStatus = status;
    }

    function _inboxAcc(
        AssertionState memory state
    ) internal view returns (bytes32) {
        uint64 position = state.globalState.u64Vals[0];
        return position == 0 ? bytes32(0) : userRollup.bridge().sequencerInboxAccs(position - 1);
    }

    function _calculateAssertionHash(
        bytes32 parentAssertionHash,
        AssertionState memory afterState
    ) internal view returns (bytes32) {
        return RollupLib.assertionHash(parentAssertionHash, afterState, _inboxAcc(afterState));
    }

    /// @dev Creates a post-MEL assertion on top of a pre-MEL parent
    function _createAssertionOnTopOfLegacyPostGenesisParent(
        address validator,
        AssertionState memory afterState
    ) internal returns (bytes32 assertionHash) {
        assertionHash = _calculateAssertionHash(postGenesisAssertionHash, afterState);
        LegacyAssertionInputs memory inputs = _getLegacyAssertionInputs(afterState);
        bool isStaked = userRollup.isStaked(validator);
        vm.prank(validator);
        if (isStaked) {
            userRollup.stakeOnNewAssertion(inputs, assertionHash);
        } else {
            userRollup.newStakeOnNewAssertion(BASE_STAKE, inputs, assertionHash, validator);
        }
    }

    /// @dev Confirms a child of a pre-MEL parent once its confirm period has passed
    function _confirmAssertionWithLegacyParentConfig(
        bytes32 assertionHash,
        bytes32 parentAssertionHash,
        AssertionState memory state,
        LegacyConfigData memory parentConfig
    ) internal {
        bytes32 inboxAcc = _inboxAcc(state);
        vm.roll(block.number + CONFIRM_PERIOD_BLOCKS + 1);
        vm.prank(validator1);
        userRollup.confirmAssertion(
            assertionHash, parentAssertionHash, state, bytes32(0), parentConfig, inboxAcc
        );
        assertEq(userRollup.latestConfirmed(), assertionHash);
    }

    // ----------------------------------------------------------------
    // Creating post-MEL assertions
    // ----------------------------------------------------------------
    function testSuccessCreateChildOfLegacyParent() public {
        LegacyAssertionInputs memory assertionInputs =
            _getLegacyAssertionInputs(firstAssertionState);
        bytes32 inboxAcc = _inboxAcc(firstAssertionState);
        bytes32 assertionHash =
            RollupLib.assertionHash(postGenesisAssertionHash, firstAssertionState, inboxAcc);
        bytes32 targetParentChainBlockHash = blockhash(block.number - 1);

        vm.expectEmit(true, true, false, true, rollup);
        emit AssertionCreated(
            assertionHash,
            postGenesisAssertionHash,
            assertionInputs,
            inboxAcc,
            targetParentChainBlockHash,
            WASM_MODULE_ROOT,
            BASE_STAKE,
            address(challengeManager),
            CONFIRM_PERIOD_BLOCKS
        );
        vm.prank(validator1);
        userRollup.stakeOnNewAssertion(assertionInputs, assertionHash);

        assertEq(
            userRollup.getAssertion(assertionHash).configHash,
            RollupLib.configHash(
                WASM_MODULE_ROOT,
                BASE_STAKE,
                address(challengeManager),
                CONFIRM_PERIOD_BLOCKS,
                targetParentChainBlockHash
            )
        );
        assertEq(userRollup.latestStakedAssertion(validator1), assertionHash);
    }

    function testConfigShapesDoNotCross() public {
        // Trying to create a post-MEL assertion, on top of a pre-MEL assertion,
        // but sending a post-MEL config in AssertionInputs
        ConfigData memory postGenesisMelConfigData = ConfigData({
            wasmModuleRoot: WASM_MODULE_ROOT,
            requiredStake: BASE_STAKE,
            challengeManager: address(challengeManager),
            confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
            targetParentChainBlockHash: blockhash(block.number - 1)
        });
        AssertionInputs memory melAssertionInputs = _getMelAssertionInputs(
            genesisAssertionHash,
            bytes32(0),
            postGenesisMelConfigData,
            postGenesisAssertionState,
            firstAssertionState
        );
        vm.prank(validator1);
        vm.expectRevert("CONFIG_HASH_MISMATCH");
        userRollup.stakeOnNewAssertion(melAssertionInputs, bytes32(0));

        // Create a valid post-MEL assertion on top of the legacy parent
        _createAssertionOnTopOfLegacyPostGenesisParent(validator1, firstAssertionState);

        // Trying to create a pre-MEL assertion, on top of a post-MEL assertion,
        // but sending a pre-MEL config in AssertionInputs
        LegacyConfigData memory firstAssertionConfigData = LegacyConfigData({
            wasmModuleRoot: WASM_MODULE_ROOT,
            requiredStake: BASE_STAKE,
            challengeManager: address(challengeManager),
            confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
            nextInboxPosition: firstInboxCount
        });
        LegacyAssertionInputs memory legacyInputs = _getLegacyAssertionInputs(
            postGenesisAssertionHash,
            _inboxAcc(firstAssertionState),
            firstAssertionConfigData,
            firstAssertionState,
            _getAssertionState(firstInboxCount, 0, MachineStatus.FINISHED, "grandchild")
        );
        vm.prank(validator1);
        vm.expectRevert("CONFIG_HASH_MISMATCH");
        userRollup.stakeOnNewAssertion(legacyInputs, bytes32(0));
    }

    /// @dev Legacy-boundary case: the first post-MEL assertion may process nothing
    function testSuccessEmptyChildOfLegacyParent() public {
        // Creating an assertion with the same state as the parent
        _createAssertionOnTopOfLegacyPostGenesisParent(validator1, postGenesisAssertionState);
    }

    function testSecondLegacyChildSendsStakeToEscrow() public {
        _createAssertionOnTopOfLegacyPostGenesisParent(validator1, firstAssertionState);

        uint256 escrowBefore = token.balanceOf(loserStakeEscrow);
        _createAssertionOnTopOfLegacyPostGenesisParent(
            validator2, _getAssertionState(firstInboxCount, 0, MachineStatus.FINISHED, "sibling")
        );
        assertEq(token.balanceOf(loserStakeEscrow) - escrowBefore, BASE_STAKE);
    }

    function testHandoffLegacyParentToMelGrandchild() public {
        // Create first post-MEL assertion
        bytes32 childAssertionHash =
            _createAssertionOnTopOfLegacyPostGenesisParent(validator1, firstAssertionState);
        bytes32 targetParentChainBlockHash = blockhash(block.number - 1);
        bytes32 childInboxAcc = _inboxAcc(firstAssertionState);
        ConfigData memory childConfigData = ConfigData({
            wasmModuleRoot: WASM_MODULE_ROOT,
            requiredStake: BASE_STAKE,
            challengeManager: address(challengeManager),
            confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
            targetParentChainBlockHash: targetParentChainBlockHash
        });

        // Create second post-MEL assertion (on top of another post-MEL assertion)
        uint64 newInboxCount = uint64(_createNewBatch());
        vm.roll(block.number + minimumAssertionPeriod);
        AssertionState memory grandchildState =
            _getAssertionState(newInboxCount, 0, MachineStatus.FINISHED, "grandchild");
        bytes32 grandchildAssertionHash =
            _calculateAssertionHash(childAssertionHash, grandchildState);

        AssertionInputs memory inputs = _getMelAssertionInputs(
            postGenesisAssertionHash,
            childInboxAcc,
            childConfigData,
            firstAssertionState,
            grandchildState
        );

        vm.prank(validator1);
        userRollup.stakeOnNewAssertion(inputs, grandchildAssertionHash);
        assertEq(userRollup.latestStakedAssertion(validator1), grandchildAssertionHash);
    }

    /// @dev A child of a pre-MEL parent is still run by the pre-MEL replay binary (the parent's config pins the
    ///      pre-MEL wasm module root and challenge manager), so the parent's nextInboxPosition still bounds it
    function testRevertChildOfLegacyParentPastNextInboxPosition() public {
        uint64 inboxCount = uint64(_createNewBatch());

        // Creating an assertion that exceeds the pre-MEL parent's nextInboxPosition
        vm.prank(validator1);
        vm.expectRevert("INBOX_TOO_FAR");
        AssertionState memory assertionState =
            _getAssertionState(inboxCount, 0, MachineStatus.FINISHED, "past");
        LegacyAssertionInputs memory legacyAssertionInputs =
            _getLegacyAssertionInputs(assertionState);
        userRollup.stakeOnNewAssertion(legacyAssertionInputs, bytes32(0));

        // Creating an assertion that exactly matches the pre-MEL parent's nextInboxPosition, but it's one position beyond
        vm.prank(validator1);
        vm.expectRevert("INBOX_TOO_FAR");
        userRollup.stakeOnNewAssertion(
            _getLegacyAssertionInputs(
                _getAssertionState(
                    postGenesisConfigData.nextInboxPosition, 1, MachineStatus.FINISHED, "mid"
                )
            ),
            bytes32(0)
        );

        // Creating an assertion that is within the pre-MEL parent's nextInboxPosition should succeed
        _createAssertionOnTopOfLegacyPostGenesisParent(validator1, firstAssertionState);
    }

    /// @dev Pre-MEL recorded nextInboxPosition = count + 1 when an assertion consumed the whole inbox, so a
    ///      tip that saw no batch after it has a bound past the inbox at upgrade time. Its first child must
    ///      wait for that batch, as it did pre-MEL
    function testChildOfLegacyParentWaitsForPlusOneBound() public {
        // Modifying the parent config to have its nextInboxPosition incremented by 1
        LegacyConfigData memory plusOneConfig = postGenesisConfigData;
        plusOneConfig.nextInboxPosition += 1;
        _plantLegacyConfig(postGenesisAssertionHash, plusOneConfig);
        LegacyAssertionInputs memory assertionInputs = _getLegacyAssertionInputs(
            genesisAssertionHash,
            bytes32(0),
            plusOneConfig,
            postGenesisAssertionState,
            firstAssertionState
        );

        // Attempting to create a new assertion
        vm.prank(validator1);
        vm.expectRevert("INBOX_NOT_POPULATED");
        userRollup.stakeOnNewAssertion(assertionInputs, bytes32(0));

        // Reading a new batch should allow creating the assertion
        uint64 newInboxCount = uint64(_createNewBatch());
        assertionInputs.afterState =
            _getAssertionState(newInboxCount, 0, MachineStatus.FINISHED, "first");
        bytes32 assertionHash =
            _calculateAssertionHash(postGenesisAssertionHash, assertionInputs.afterState);
        vm.prank(validator1);
        userRollup.stakeOnNewAssertion(assertionInputs, assertionHash);
        assertEq(userRollup.latestStakedAssertion(validator1), assertionHash);
    }

    // ----------------------------------------------------------------
    // Confirmation under a legacy parent
    // ----------------------------------------------------------------
    function testConfirmLegacyChild() public {
        // Creating a post-MEL assertion
        bytes32 assertionHash =
            _createAssertionOnTopOfLegacyPostGenesisParent(validator1, firstAssertionState);
        bytes32 inboxAcc = _inboxAcc(firstAssertionState);

        // Confirm the first post-MEL assertion
        vm.roll(block.number + CONFIRM_PERIOD_BLOCKS + 1);
        vm.prank(validator1);
        userRollup.confirmAssertion(
            assertionHash,
            postGenesisAssertionHash,
            firstAssertionState,
            bytes32(0),
            postGenesisConfigData,
            inboxAcc
        );
        assertEq(userRollup.latestConfirmed(), assertionHash);
    }

    function testConfirmChallengedLegacyChildReadsLegacyChallengeManager() public {
        // Create 2 sibling assertions
        bytes32 assertionHash =
            _createAssertionOnTopOfLegacyPostGenesisParent(validator1, firstAssertionState);
        _createAssertionOnTopOfLegacyPostGenesisParent(
            validator2, _getAssertionState(firstInboxCount, 0, MachineStatus.FINISHED, "sibling")
        );
        bytes32 inboxAcc = _inboxAcc(firstAssertionState);
        vm.roll(block.number + CONFIRM_PERIOD_BLOCKS + 1);

        // Set the winning edge in the legacy challenge manager
        bytes32 winningEdgeId = keccak256("winning edge");
        ChallengeEdge memory edge;
        edge.claimId = assertionHash;
        edge.status = EdgeStatus.Confirmed;
        edge.confirmedAtBlock = uint64(block.number);
        vm.etch(legacyChallengeManagerAddress, hex"00");
        vm.mockCall(
            legacyChallengeManagerAddress,
            abi.encodeWithSelector(IEdgeChallengeManager.getEdge.selector, winningEdgeId),
            abi.encode(edge)
        );
        vm.roll(block.number + CHALLENGE_GRACE_PERIOD_BLOCKS);

        // Try to confirm the assertion
        vm.expectCall(
            legacyChallengeManagerAddress,
            abi.encodeWithSelector(IEdgeChallengeManager.getEdge.selector, winningEdgeId)
        );
        vm.prank(validator1);
        userRollup.confirmAssertion(
            assertionHash,
            postGenesisAssertionHash,
            firstAssertionState,
            winningEdgeId,
            postGenesisConfigData,
            inboxAcc
        );
        assertEq(userRollup.latestConfirmed(), assertionHash);
    }

    /// @dev The pre-MEL EdgeChallengeManager calls validateConfig with the pre-MEL ConfigData shape
    function testLegacyChallengeManagerCanValidateLegacyParentConfig() public {
        bytes4 legacySelector = IAssertionChainTransition.validateConfig.selector;

        // Call the pre-Mel validateConfig with the legacy config data
        LegacyConfigData memory config = postGenesisConfigData;
        (bool legacySelectorCallResult,) = rollup.staticcall(
            abi.encodeWithSelector(legacySelector, postGenesisAssertionHash, config)
        );
        assertTrue(legacySelectorCallResult);

        // Call the pre-Mel validateConfig with the wrong config data
        config.nextInboxPosition += 1;
        (bool wrongConfigResult, bytes memory wrongConfigErrorData) = rollup.staticcall(
            abi.encodeWithSelector(legacySelector, postGenesisAssertionHash, config)
        );
        assertFalse(wrongConfigResult);
        assertEq(
            wrongConfigErrorData, abi.encodeWithSignature("Error(string)", "CONFIG_HASH_MISMATCH")
        );

        // Call the pre-Mel validateConfig with a post-MEL parent
        bytes32 assertionHash =
            _createAssertionOnTopOfLegacyPostGenesisParent(validator1, firstAssertionState);
        (bool postMelCallResult, bytes memory postMelCallErrorData) = rollup.staticcall(
            abi.encodeWithSelector(legacySelector, assertionHash, postGenesisConfigData)
        );
        assertFalse(postMelCallResult);
        assertEq(
            postMelCallErrorData, abi.encodeWithSignature("Error(string)", "CONFIG_HASH_MISMATCH")
        );
    }

    /// @dev Confirming pre-MEL assertions created before the chain upgrade
    function testPendingLegacyAssertionAtUpgradeHandsOffToMel() public {
        // Create a pending pre-MEL assertion on top of postGenesis
        AssertionState memory legacyAssertionState = firstAssertionState;
        bytes32 legacyAssertionHash =
            _createAssertionOnTopOfLegacyPostGenesisParent(validator1, legacyAssertionState);
        LegacyConfigData memory legacyConfig = postGenesisConfigData;
        legacyConfig.nextInboxPosition = firstInboxCount + 1;
        _plantLegacyConfig(legacyAssertionHash, legacyConfig);
        uint64 newInboxCount = uint64(_createNewBatch());

        // Confirm it
        _confirmAssertionWithLegacyParentConfig(
            legacyAssertionHash,
            postGenesisAssertionHash,
            legacyAssertionState,
            postGenesisConfigData
        );

        // Create the first post-MEL assertion
        AssertionState memory firstMelState =
            _getAssertionState(newInboxCount, 0, MachineStatus.FINISHED, "firstMel");
        bytes32 firstMelHash = _calculateAssertionHash(legacyAssertionHash, firstMelState);
        LegacyAssertionInputs memory firstMelInputs = _getLegacyAssertionInputs(
            postGenesisAssertionHash,
            _inboxAcc(legacyAssertionState),
            legacyConfig,
            legacyAssertionState,
            firstMelState
        );
        vm.prank(validator1);
        userRollup.stakeOnNewAssertion(firstMelInputs, firstMelHash);

        // Confirm it
        ConfigData memory firstMelConfig = _craftMelConfig(blockhash(block.number - 1));
        _confirmAssertionWithLegacyParentConfig(
            firstMelHash, legacyAssertionHash, firstMelState, legacyConfig
        );

        // Create and confirm one last post-MEL assertion (empty, so it uses the same state)
        bytes32 assertionHash = _calculateAssertionHash(firstMelHash, firstMelState);
        AssertionInputs memory assertionInputs = _getMelAssertionInputs(
            legacyAssertionHash,
            _inboxAcc(firstMelState),
            firstMelConfig,
            firstMelState,
            firstMelState
        );
        vm.prank(validator1);
        userRollup.stakeOnNewAssertion(assertionInputs, assertionHash);

        bytes32 inboxAcc = _inboxAcc(firstMelState);
        vm.roll(block.number + CONFIRM_PERIOD_BLOCKS + 1);
        vm.prank(validator1);
        userRollup.confirmAssertion(
            assertionHash, firstMelHash, firstMelState, bytes32(0), firstMelConfig, inboxAcc
        );
        assertEq(userRollup.latestConfirmed(), assertionHash);
    }

    function testSuccessFastConfirmNewLegacyAssertion() public {
        LegacyAssertionInputs memory assertionInputs =
            _getLegacyAssertionInputs(firstAssertionState);
        bytes32 assertionHash =
            _calculateAssertionHash(postGenesisAssertionHash, firstAssertionState);

        vm.prank(anyTrustFastConfirmer);
        userRollup.fastConfirmNewAssertion(assertionInputs, assertionHash);
        assertEq(userRollup.latestConfirmed(), assertionHash);
    }

    function testSuccessForceCreateAndConfirmLegacyAssertion() public {
        LegacyAssertionInputs memory assertionInputs =
            _getLegacyAssertionInputs(firstAssertionState);
        bytes32 inboxAcc = _inboxAcc(firstAssertionState);
        bytes32 assertionHash =
            RollupLib.assertionHash(postGenesisAssertionHash, firstAssertionState, inboxAcc);

        vm.startPrank(upgradeExecutorAddr);
        adminRollup.pause();
        adminRollup.forceCreateAssertion(postGenesisAssertionHash, assertionInputs, assertionHash);
        adminRollup.forceConfirmAssertion(
            assertionHash, postGenesisAssertionHash, firstAssertionState, inboxAcc
        );
        vm.stopPrank();
        assertEq(userRollup.latestConfirmed(), assertionHash);
    }

    /// @dev The transition contracts can't be removed before all pre-MEL and transitional assertions have been confirmed
    function testFinalImplsCannotExtendLegacyParent() public {
        // Create a post-MEL assertion on top of the pre-MEL parent and let its confirm period pass
        bytes32 firstAssertionHash =
            _createAssertionOnTopOfLegacyPostGenesisParent(validator2, firstAssertionState);
        bytes32 firstAssertionInboxAcc = _inboxAcc(firstAssertionState);
        vm.roll(block.number + CONFIRM_PERIOD_BLOCKS + 1);

        // Deploy final implementations and upgrade the rollup to them
        vm.startPrank(upgradeExecutorAddr);
        adminRollup.upgradeTo(address(new RollupAdminLogic()));
        adminRollup.upgradeSecondaryTo(address(new RollupUserLogic()));
        vm.stopPrank();

        // Pre-MEL assertions can't be created
        LegacyAssertionInputs memory legacyInputs = _getLegacyAssertionInputs(firstAssertionState);
        vm.prank(validator1);
        vm.expectRevert(bytes(""));
        userRollup.stakeOnNewAssertion(legacyInputs, bytes32(0));

        // Post-MEL assertions on top of pre-MEL assertions can't be created
        AssertionInputs memory melInputs = _getMelAssertionInputs(
            genesisAssertionHash,
            bytes32(0),
            _craftMelConfig(blockhash(block.number - 1)),
            postGenesisAssertionState,
            firstAssertionState
        );
        vm.prank(validator1);
        vm.expectRevert("CONFIG_HASH_MISMATCH");
        userRollup.stakeOnNewAssertion(melInputs, bytes32(0));

        // The pending post-MEL child of the pre-MEL parent can't be confirmed either, since it needs the
        // parent's pre-MEL config
        vm.prank(validator1);
        vm.expectRevert(bytes(""));
        userRollup.confirmAssertion(
            firstAssertionHash,
            postGenesisAssertionHash,
            firstAssertionState,
            bytes32(0),
            postGenesisConfigData,
            firstAssertionInboxAcc
        );
    }
}
