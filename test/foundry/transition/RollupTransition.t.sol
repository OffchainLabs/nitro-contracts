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
///         Tests then give the confirmed post-genesis assertion a pre-MEL config hash and use it
///         as the legacy parent.
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

    // Empty assertion on top of genesis, confirmed in setUp. This is a MEL assertion
    // that is transformed into a pre-MEL assertion in test functions.
    AssertionState postGenesisAssertionState =
        AssertionState(emptyGlobalState, MachineStatus.FINISHED, bytes32(0));
    bytes32 postGenesisAssertionHash =
        RollupLib.assertionHash(genesisAssertionHash, postGenesisAssertionState, bytes32(0));
    ConfigData postGenesisConfigData;

    // Consumes the batch posted in setUp (the creator posts an initialization batch before it)
    AssertionState firstAssertionState;
    uint64 firstInboxCount;

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
            genesisInboxCount: 0,
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

        _fundValidator(validator1);
        _fundValidator(validator2);
        vm.deal(sequencer, 1 ether);

        // Advance `minimumAssertionPeriod` blocks
        minimumAssertionPeriod = userRollup.minimumAssertionPeriod();
        vm.roll(block.number + minimumAssertionPeriod);

        // Create a new batch
        // (in a regular chain, a batch will be posted before creating the postGenesis assertion)
        firstInboxCount = uint64(_createNewBatch());
        vm.roll(block.number + 2);

        // Create the first assertion (consumes no batches)
        // This will now be a post-MEL assertion, but it's transformed into a pre-MEL assertion
        // in the test functions
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

        postGenesisConfigData = ConfigData({
            wasmModuleRoot: WASM_MODULE_ROOT,
            requiredStake: BASE_STAKE,
            challengeManager: address(challengeManager),
            confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
            targetParentChainBlockHash: blockhash(block.number - 1)
        });

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

        // Advance `minimumAssertionPeriod` blocks again
        vm.roll(block.number + minimumAssertionPeriod);

        // Change the Rollup implementations to the transitional contracts
        address transitionalAdminImpl = address(new RollupAdminLogicTransitionalTestHelper());
        address transitionalUserImpl = address(new RollupUserLogicTransitional());
        vm.startPrank(upgradeExecutorAddr);
        adminRollup.upgradeTo(transitionalAdminImpl);
        adminRollup.upgradeSecondaryTo(transitionalUserImpl);
        vm.stopPrank();

        firstAssertionState = _assertionState(firstInboxCount, 0, MachineStatus.FINISHED, "first");
    }

    function _fundValidator(
        address validator
    ) internal {
        token.transfer(validator, 1 ether);
        vm.prank(validator);
        token.approve(rollup, type(uint256).max);
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

    function _legacyConfig(
        uint64 nextInboxPosition
    ) internal view returns (LegacyConfigData memory) {
        return LegacyConfigData({
            wasmModuleRoot: WASM_MODULE_ROOT,
            requiredStake: BASE_STAKE,
            challengeManager: address(challengeManager),
            confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
            nextInboxPosition: nextInboxPosition
        });
    }

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

    function _melInputs(
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

    function _legacyInputs(
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

    /// @dev Inputs for a child of the post-genesis assertion
    function _melInputs(
        ConfigData memory config,
        AssertionState memory afterState
    ) internal view returns (AssertionInputs memory) {
        return
            _melInputs(
                genesisAssertionHash, bytes32(0), config, postGenesisAssertionState, afterState
            );
    }

    /// @dev Inputs for a child of the post-genesis assertion
    function _legacyInputs(
        LegacyConfigData memory config,
        AssertionState memory afterState
    ) internal view returns (LegacyAssertionInputs memory) {
        return _legacyInputs(
            genesisAssertionHash, bytes32(0), config, postGenesisAssertionState, afterState
        );
    }

    function _assertionState(
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

    function _childHash(
        bytes32 parentAssertionHash,
        AssertionState memory afterState
    ) internal view returns (bytes32) {
        return RollupLib.assertionHash(parentAssertionHash, afterState, _inboxAcc(afterState));
    }

    /// @dev Creates a child of the legacy-shaped post-genesis assertion through the legacy entrypoint
    function _stakeLegacy(
        address validator,
        LegacyConfigData memory config,
        AssertionState memory afterState
    ) internal returns (bytes32 assertionHash) {
        assertionHash = _childHash(postGenesisAssertionHash, afterState);
        LegacyAssertionInputs memory inputs = _legacyInputs(config, afterState);
        bool isStaked = userRollup.isStaked(validator);
        vm.prank(validator);
        if (isStaked) {
            userRollup.stakeOnNewAssertion(inputs, assertionHash);
        } else {
            userRollup.newStakeOnNewAssertion(
                config.requiredStake, inputs, assertionHash, validator
            );
        }
    }

    /// @dev A MEL child made pending, then re-shaped as if it had been created before the upgrade
    function _createPendingLegacyAssertion(
        LegacyConfigData memory config
    ) internal returns (bytes32 childHash, bytes32 childPin) {
        childHash = _childHash(postGenesisAssertionHash, firstAssertionState);
        AssertionInputs memory inputs = _melInputs(postGenesisConfigData, firstAssertionState);
        vm.prank(validator1);
        userRollup.stakeOnNewAssertion(inputs, childHash);
        childPin = blockhash(block.number - 1);
        _plantLegacyConfig(childHash, config);
    }

    // ---------------------------------------------------------------- upgrade lifecycle

    function testUpgradeKeepsStateAndStockEntrypoints() public {
        assertEq(userRollup.latestConfirmed(), postGenesisAssertionHash);
        assertEq(userRollup.amountStaked(validator1), BASE_STAKE);

        bytes32 childHash = _childHash(postGenesisAssertionHash, firstAssertionState);
        AssertionInputs memory inputs = _melInputs(postGenesisConfigData, firstAssertionState);
        vm.prank(validator1);
        userRollup.stakeOnNewAssertion(inputs, childHash);
        assertEq(userRollup.latestStakedAssertion(validator1), childHash);
    }

    function testUpgradeToFinalImplsDropsLegacyEntrypoints() public {
        address finalAdminImpl = address(new RollupAdminLogic());
        address finalUserImpl = address(new RollupUserLogic());
        vm.startPrank(upgradeExecutorAddr);
        adminRollup.upgradeTo(finalAdminImpl);
        adminRollup.upgradeSecondaryTo(finalUserImpl);
        vm.stopPrank();

        LegacyAssertionInputs memory legacyInputs =
            _legacyInputs(_legacyConfig(firstInboxCount), firstAssertionState);
        vm.prank(validator1);
        vm.expectRevert();
        userRollup.stakeOnNewAssertion(legacyInputs, bytes32(0));

        bytes32 childHash = _childHash(postGenesisAssertionHash, firstAssertionState);
        AssertionInputs memory inputs = _melInputs(postGenesisConfigData, firstAssertionState);
        vm.prank(validator1);
        userRollup.stakeOnNewAssertion(inputs, childHash);
        assertEq(userRollup.latestStakedAssertion(validator1), childHash);
    }

    /// @dev The pre-MEL challenge manager calls validateConfig with the legacy struct
    function testLegacyValidateConfigSelectorServedThroughProxy() public {
        LegacyConfigData memory config = _legacyConfig(firstInboxCount);
        bytes memory data =
            abi.encodeWithSelector(bytes4(0x04972af9), postGenesisAssertionHash, config);

        (bool ok, bytes memory ret) = rollup.staticcall(data);
        assertFalse(ok);
        assertEq(ret, abi.encodeWithSignature("Error(string)", "CONFIG_HASH_MISMATCH"));

        _plantLegacyConfig(postGenesisAssertionHash, config);
        (ok,) = rollup.staticcall(data);
        assertTrue(ok);
    }

    // ---------------------------------------------------------------- legacy parent to MEL child

    function testSuccessCreateChildOfLegacyParent() public {
        LegacyConfigData memory config = _legacyConfig(firstInboxCount);
        _plantLegacyConfig(postGenesisAssertionHash, config);
        LegacyAssertionInputs memory inputs = _legacyInputs(config, firstAssertionState);
        bytes32 inboxAcc = _inboxAcc(firstAssertionState);
        bytes32 childHash =
            RollupLib.assertionHash(postGenesisAssertionHash, firstAssertionState, inboxAcc);
        bytes32 pin = blockhash(block.number - 1);

        vm.expectEmit(true, true, false, true, rollup);
        emit AssertionCreated(
            childHash,
            postGenesisAssertionHash,
            inputs,
            inboxAcc,
            pin,
            WASM_MODULE_ROOT,
            BASE_STAKE,
            address(challengeManager),
            CONFIRM_PERIOD_BLOCKS
        );
        vm.prank(validator1);
        userRollup.stakeOnNewAssertion(inputs, childHash);

        // the child is already MEL-shaped
        assertEq(
            userRollup.getAssertion(childHash).configHash,
            RollupLib.configHash(
                WASM_MODULE_ROOT, BASE_STAKE, address(challengeManager), CONFIRM_PERIOD_BLOCKS, pin
            )
        );
        assertEq(userRollup.latestStakedAssertion(validator1), childHash);
    }

    function testConfigShapesDoNotCross() public {
        LegacyAssertionInputs memory legacyInputs =
            _legacyInputs(_legacyConfig(firstInboxCount), firstAssertionState);
        vm.prank(validator1);
        vm.expectRevert("CONFIG_HASH_MISMATCH");
        userRollup.stakeOnNewAssertion(legacyInputs, bytes32(0));

        _plantLegacyConfig(postGenesisAssertionHash, _legacyConfig(firstInboxCount));
        AssertionInputs memory melInputs = _melInputs(postGenesisConfigData, firstAssertionState);
        vm.prank(validator1);
        vm.expectRevert("CONFIG_HASH_MISMATCH");
        userRollup.stakeOnNewAssertion(melInputs, bytes32(0));
    }

    /// @dev Legacy-boundary case: the first post-MEL assertion may process nothing
    function testSuccessEmptyChildOfLegacyParent() public {
        LegacyConfigData memory config = _legacyConfig(firstInboxCount);
        _plantLegacyConfig(postGenesisAssertionHash, config);
        bytes32 childHash = _stakeLegacy(validator1, config, postGenesisAssertionState);
        assertEq(uint8(userRollup.getAssertion(childHash).status), uint8(AssertionStatus.Pending));
    }

    /// @dev The stake amount comes from the legacy config, not from the rollup's current base stake
    function testSecondLegacyChildSendsLegacyRequiredStakeToEscrow() public {
        LegacyConfigData memory config = _legacyConfig(firstInboxCount);
        config.requiredStake = BASE_STAKE - 1;
        _plantLegacyConfig(postGenesisAssertionHash, config);
        _stakeLegacy(validator1, config, firstAssertionState);

        uint256 escrowBefore = token.balanceOf(loserStakeEscrow);
        _stakeLegacy(
            validator2,
            config,
            _assertionState(firstInboxCount, 0, MachineStatus.FINISHED, "sibling")
        );
        assertEq(token.balanceOf(loserStakeEscrow) - escrowBefore, BASE_STAKE - 1);
    }

    function testHandoffLegacyParentToMelGrandchild() public {
        LegacyConfigData memory config = _legacyConfig(firstInboxCount);
        _plantLegacyConfig(postGenesisAssertionHash, config);
        bytes32 childHash = _stakeLegacy(validator1, config, firstAssertionState);
        bytes32 childPin = blockhash(block.number - 1);
        bytes32 childInboxAcc = _inboxAcc(firstAssertionState);

        uint64 newInboxCount = uint64(_createNewBatch());
        vm.roll(block.number + minimumAssertionPeriod);
        AssertionState memory grandchildState =
            _assertionState(newInboxCount, 0, MachineStatus.FINISHED, "grandchild");
        bytes32 grandchildHash = _childHash(childHash, grandchildState);
        AssertionInputs memory inputs = _melInputs(
            postGenesisAssertionHash,
            childInboxAcc,
            ConfigData({
                wasmModuleRoot: WASM_MODULE_ROOT,
                requiredStake: BASE_STAKE,
                challengeManager: address(challengeManager),
                confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
                targetParentChainBlockHash: childPin
            }),
            firstAssertionState,
            grandchildState
        );

        vm.prank(validator1);
        userRollup.stakeOnNewAssertion(inputs, grandchildHash);
        assertEq(userRollup.latestStakedAssertion(validator1), grandchildHash);
    }

    // ---------------------------------------------------------------- pending legacy assertion at upgrade time

    function testSuccessLegacyChildOfPendingLegacyAssertion() public {
        LegacyConfigData memory config = _legacyConfig(firstInboxCount);
        (bytes32 childHash,) = _createPendingLegacyAssertion(config);
        vm.roll(block.number + minimumAssertionPeriod);

        AssertionState memory grandchildState =
            _assertionState(firstInboxCount, 0, MachineStatus.FINISHED, "grandchild");
        LegacyAssertionInputs memory inputs = _legacyInputs(
            postGenesisAssertionHash,
            _inboxAcc(firstAssertionState),
            config,
            firstAssertionState,
            grandchildState
        );
        bytes32 grandchildHash = _childHash(childHash, grandchildState);

        vm.prank(validator1);
        userRollup.stakeOnNewAssertion(inputs, grandchildHash);
        assertEq(userRollup.latestStakedAssertion(validator1), grandchildHash);
    }

    function testRevertDecreaseBaseStakeWhilePendingAssertionIsLegacyShaped() public {
        (, bytes32 childPin) = _createPendingLegacyAssertion(_legacyConfig(firstInboxCount));
        vm.prank(upgradeExecutorAddr);
        vm.expectRevert("EXPIRED_CONFIG_HASH");
        adminRollup.decreaseBaseStake(BASE_STAKE - 1, childPin);
    }

    // ---------------------------------------------------------------- confirmation under a legacy parent

    function testConfirmLegacyChildUsesLegacyConfirmPeriod() public {
        LegacyConfigData memory config = _legacyConfig(firstInboxCount);
        config.confirmPeriodBlocks = CONFIRM_PERIOD_BLOCKS * 2;
        _plantLegacyConfig(postGenesisAssertionHash, config);
        bytes32 childHash = _stakeLegacy(validator1, config, firstAssertionState);
        bytes32 inboxAcc = _inboxAcc(firstAssertionState);
        uint64 createdAtBlock = userRollup.getAssertion(childHash).createdAtBlock;

        vm.roll(createdAtBlock + CONFIRM_PERIOD_BLOCKS);
        vm.prank(validator1);
        vm.expectRevert("BEFORE_DEADLINE");
        userRollup.confirmAssertion(
            childHash, postGenesisAssertionHash, firstAssertionState, bytes32(0), config, inboxAcc
        );

        vm.roll(createdAtBlock + CONFIRM_PERIOD_BLOCKS * 2);
        vm.prank(validator1);
        userRollup.confirmAssertion(
            childHash, postGenesisAssertionHash, firstAssertionState, bytes32(0), config, inboxAcc
        );
        assertEq(userRollup.latestConfirmed(), childHash);
    }

    function testConfirmChallengedLegacyChildReadsLegacyChallengeManager() public {
        address legacyChallengeManager = address(0xCAFE);
        LegacyConfigData memory config = _legacyConfig(firstInboxCount);
        config.challengeManager = legacyChallengeManager;
        _plantLegacyConfig(postGenesisAssertionHash, config);
        bytes32 childHash = _stakeLegacy(validator1, config, firstAssertionState);
        _stakeLegacy(
            validator2,
            config,
            _assertionState(firstInboxCount, 0, MachineStatus.FINISHED, "sibling")
        );
        bytes32 inboxAcc = _inboxAcc(firstAssertionState);
        vm.roll(block.number + CONFIRM_PERIOD_BLOCKS + 1);

        // Only the legacy manager knows the winning edge; the rollup's current manager would revert
        bytes32 winningEdgeId = keccak256("winning edge");
        ChallengeEdge memory edge;
        edge.claimId = childHash;
        edge.status = EdgeStatus.Confirmed;
        edge.confirmedAtBlock = uint64(block.number);
        vm.etch(legacyChallengeManager, hex"00");
        vm.mockCall(
            legacyChallengeManager,
            abi.encodeWithSelector(IEdgeChallengeManager.getEdge.selector, winningEdgeId),
            abi.encode(edge)
        );
        vm.roll(block.number + CHALLENGE_GRACE_PERIOD_BLOCKS);

        vm.prank(validator1);
        userRollup.confirmAssertion(
            childHash,
            postGenesisAssertionHash,
            firstAssertionState,
            winningEdgeId,
            config,
            inboxAcc
        );
        assertEq(userRollup.latestConfirmed(), childHash);
    }

    function testSuccessFastConfirmNewLegacyAssertion() public {
        LegacyConfigData memory config = _legacyConfig(firstInboxCount);
        _plantLegacyConfig(postGenesisAssertionHash, config);
        LegacyAssertionInputs memory inputs = _legacyInputs(config, firstAssertionState);
        bytes32 childHash = _childHash(postGenesisAssertionHash, firstAssertionState);

        vm.prank(anyTrustFastConfirmer);
        userRollup.fastConfirmNewAssertion(inputs, childHash);
        assertEq(userRollup.latestConfirmed(), childHash);
    }

    function testSuccessForceCreateAndConfirmLegacyAssertion() public {
        LegacyConfigData memory config = _legacyConfig(firstInboxCount);
        _plantLegacyConfig(postGenesisAssertionHash, config);
        LegacyAssertionInputs memory inputs = _legacyInputs(config, firstAssertionState);
        bytes32 inboxAcc = _inboxAcc(firstAssertionState);
        bytes32 childHash =
            RollupLib.assertionHash(postGenesisAssertionHash, firstAssertionState, inboxAcc);

        vm.startPrank(upgradeExecutorAddr);
        adminRollup.pause();
        adminRollup.forceCreateAssertion(postGenesisAssertionHash, inputs, childHash);
        adminRollup.forceConfirmAssertion(
            childHash, postGenesisAssertionHash, firstAssertionState, inboxAcc
        );
        vm.stopPrank();
        assertEq(userRollup.latestConfirmed(), childHash);
    }
}
