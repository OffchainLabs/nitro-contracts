// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../src/rollup/RollupProxy.sol";

import "../../src/rollup/RollupCore.sol";
import "../../src/rollup/RollupUserLogic.sol";
import "../../src/rollup/RollupAdminLogic.sol";
import "../../src/rollup/RollupCreator.sol";

import "../../src/osp/OneStepProver0.sol";
import "../../src/osp/OneStepProverMemory.sol";
import "../../src/osp/OneStepProverMath.sol";
import "../../src/osp/OneStepProverHostIo.sol";
import "../../src/osp/OneStepProofEntry.sol";
import "../../src/challengeV2/EdgeChallengeManager.sol";
import "./challengeV2/Utils.sol";

import "../../src/libraries/Error.sol";

import "../../src/mocks/TestWETH9.sol";
import "../../src/mocks/UpgradeExecutorMock.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts-upgradeable/utils/Create2Upgradeable.sol";

contract RollupTest is Test {
    using GlobalStateLib for GlobalState;
    using AssertionStateLib for AssertionState;

    address constant owner = address(1337);
    address constant sequencer = address(7331);

    address constant validator1 = address(100001);
    address constant validator2 = address(100002);
    address constant validator3 = address(100003);
    address constant validator1Withdrawal = address(1000010);
    address constant validator2Withdrawal = address(1000020);
    address constant validator3Withdrawal = address(1000030);
    address constant loserStakeEscrow = address(200001);
    address constant anyTrustFastConfirmer = address(300001);

    bytes32 constant WASM_MODULE_ROOT = keccak256("WASM_MODULE_ROOT");
    uint256 constant BASE_STAKE = 10;
    uint256 constant MINI_STAKE_VALUE = 2;
    uint64 constant CONFIRM_PERIOD_BLOCKS = 100;
    uint256 constant MAX_DATA_SIZE = 117964;
    uint64 constant CHALLENGE_GRACE_PERIOD_BLOCKS = 10;

    bytes32 constant GENESIS_NEXT_PARENT_CHAIN_BLOCKHASH = bytes32(0);
    bytes32 constant FIRST_ASSERTION_BLOCKHASH = keccak256("FIRST_ASSERTION_BLOCKHASH");
    bytes32 constant FIRST_ASSERTION_SENDROOT = keccak256("FIRST_ASSERTION_SENDROOT");

    uint256 constant LAYERZERO_BLOCKEDGE_HEIGHT = 2 ** 5;

    IERC20 token;
    RollupProxy rollup;
    RollupUserLogic userRollup;
    RollupAdminLogic adminRollup;
    EdgeChallengeManager challengeManager;
    Random rand = new Random();

    address upgradeExecutorAddr;
    address[] validators;
    bool[] flags;
    uint256 minimumAssertionPeriod;

    // Genesis assertion (should match what's created in RollupAdminLogic.initialize())
    // Start with an empty global state
    GlobalState emptyGlobalState;
    AssertionState genesisAssertionState =
        AssertionState(emptyGlobalState, MachineStatus.FINISHED, bytes32(0));
    bytes32 genesisAssertionHash = RollupLib.assertionHash({
        parentAssertionHash: bytes32(0), afterState: genesisAssertionState, inboxAcc: bytes32(0)
    });
    ConfigData genesisConfigData;

    // First (empty) assertion after genesis (will not consume any batches)
    GlobalState postGenesisGlobalState = emptyGlobalState;
    AssertionState postGenesisAssertionState =
        AssertionState(postGenesisGlobalState, MachineStatus.FINISHED, bytes32(0));
    bytes32 postGenesisAssertionHash = RollupLib.assertionHash({
        parentAssertionHash: genesisAssertionHash,
        afterState: postGenesisAssertionState,
        inboxAcc: bytes32(0)
    });
    ConfigData postGenesisConfigData;

    // First real assertion after genesis
    // Created after genesis and post-genesis assertions (it will consume batches)
    GlobalState firstAssertionGlobalState;
    AssertionState firstAssertionState;

    event RollupCreated(
        address indexed rollupAddress,
        address indexed nativeToken,
        address inboxAddress,
        address outbox,
        address rollupEventInbox,
        address challengeManager,
        address adminProxy,
        address sequencerInbox,
        address bridge,
        address upgradeExecutor,
        address validatorWalletCreator
    );

    event AssertionCreated(
        bytes32 indexed assertionHash,
        bytes32 indexed parentAssertionHash,
        AssertionInputs assertion,
        bytes32 afterInboxBatchAcc,
        uint256 inboxMaxCount,
        bytes32 nextParentChainBlockHash,
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
        OneStepProverHostIo oneStepProverHostIo = new OneStepProverHostIo(address(0), address(0));
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
            confirmPeriodBlocks: uint64(CONFIRM_PERIOD_BLOCKS),
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

        vm.expectEmit(false, false, false, false);
        emit RollupCreated(
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0)
        );

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

        address rollupAddr = rollupCreator.createRollup(param);
        // TODO: fix this
        // bytes32 rollupSalt = keccak256(abi.encode(config, address(0), new address[](0), false, MAX_DATA_SIZE));
        // address expectedRollupAddress = Create2Upgradeable.computeAddress(
        //     rollupSalt, keccak256(type(RollupProxy).creationCode), address(rollupCreator)
        // );
        // assertEq(expectedRollupAddress, rollupAddr, "Unexpected rollup address");

        userRollup = RollupUserLogic(address(rollupAddr));
        adminRollup = RollupAdminLogic(address(rollupAddr));
        challengeManager = EdgeChallengeManager(address(userRollup.challengeManager()));

        assertEq(userRollup.sequencerInbox().maxDataSize(), MAX_DATA_SIZE);
        assertFalse(userRollup.validatorWhitelistDisabled());

        // check upgrade executor owns proxyAdmin
        address upgradeExecutorExpectedAddress = computeCreateAddress(address(rollupCreator), 4);
        upgradeExecutorAddr = userRollup.owner();
        assertEq(upgradeExecutorAddr, upgradeExecutorExpectedAddress, "Invalid proxyAdmin's owner");

        vm.startPrank(upgradeExecutorAddr);
        validators.push(validator1);
        validators.push(validator2);
        validators.push(validator3);
        validators.push(address(this));
        flags.push(true);
        flags.push(true);
        flags.push(true);
        flags.push(true);
        adminRollup.setValidator(address[](validators), flags);
        adminRollup.sequencerInbox().setIsBatchPoster(sequencer, true);
        vm.stopPrank();

        // TODO: determine if challengeManager should be permissionless at the stage
        token.approve(address(challengeManager), type(uint256).max);

        token.transfer(validator1, 1 ether);
        vm.deal(validator1, 1 ether);
        vm.prank(validator1);
        token.approve(address(userRollup), type(uint256).max);
        vm.prank(validator1);
        token.approve(address(challengeManager), type(uint256).max);

        token.transfer(validator2, 1 ether);
        vm.deal(validator2, 1 ether);
        vm.prank(validator2);
        token.approve(address(userRollup), type(uint256).max);
        vm.prank(validator2);
        token.approve(address(challengeManager), type(uint256).max);

        token.transfer(validator3, 1 ether);
        vm.deal(validator3, 1 ether);
        vm.prank(validator3);
        token.approve(address(userRollup), type(uint256).max);
        vm.prank(validator3);
        token.approve(address(challengeManager), type(uint256).max);

        vm.deal(sequencer, 1 ether);

        // Advance `minimumAssertionPeriod` blocks
        minimumAssertionPeriod = userRollup.minimumAssertionPeriod();
        vm.roll(block.number + minimumAssertionPeriod);

        // Create a new batch
        // (in a regular chain, a batch will be posted before creating the postGenesis assertion)
        uint64 inboxCount = uint64(_createNewBatch());
        vm.roll(block.number + 2); // Advance two blocks since the batch must be older than the nextParentChainBlockHash

        // Create the first assertion (consumes no batches)
        genesisConfigData = ConfigData({
            wasmModuleRoot: WASM_MODULE_ROOT,
            requiredStake: BASE_STAKE,
            challengeManager: address(challengeManager),
            confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
            nextInboxPosition: 1, // Initialization batch is posted before creating the genesis assertion
            nextParentChainBlockHash: GENESIS_NEXT_PARENT_CHAIN_BLOCKHASH
        });
        (bytes32 expectedAssertionHash, bytes32 parentAssertionHash) = _createAssertion(
            BeforeStateData({
                sequencerBatchAcc: bytes32(0),
                prevPrevAssertionHash: bytes32(0),
                configData: genesisConfigData
            }),
            genesisAssertionState,
            postGenesisAssertionState,
            bytes32(0)
        );
        assertEq(parentAssertionHash, genesisAssertionHash);
        assertEq(expectedAssertionHash, postGenesisAssertionHash);

        postGenesisConfigData = ConfigData({
            wasmModuleRoot: WASM_MODULE_ROOT,
            requiredStake: BASE_STAKE,
            challengeManager: address(challengeManager),
            confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
            nextInboxPosition: inboxCount,
            nextParentChainBlockHash: blockhash(block.number - 1)
        });

        // Confirm it so new assertions can be created on top of it
        vm.roll(
            userRollup.getAssertion(genesisAssertionHash).firstChildBlock + CONFIRM_PERIOD_BLOCKS
                + 1
        );

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

        // We know what the first assertion's global state should be
        firstAssertionGlobalState.bytes32Vals[0] = FIRST_ASSERTION_BLOCKHASH; // blockhash
        firstAssertionGlobalState.bytes32Vals[1] = FIRST_ASSERTION_SENDROOT; // sendroot
        firstAssertionGlobalState.u64Vals[0] = inboxCount; // inbox count
        firstAssertionGlobalState.u64Vals[1] = 0; // pos in msg

        firstAssertionState =
            AssertionState(firstAssertionGlobalState, MachineStatus.FINISHED, bytes32(0));
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

    function _createAssertionWithValidator(
        BeforeStateData memory parentAssertionStateData,
        AssertionState memory parentAssertionState,
        AssertionState memory assertionState,
        bytes32 inboxAcc,
        address validator,
        address validatorWithdrawal
    ) internal returns (bytes32, bytes32) {
        bytes32 parentAssertionHash = RollupLib.assertionHash(
            parentAssertionStateData.prevPrevAssertionHash,
            parentAssertionState,
            parentAssertionStateData.sequencerBatchAcc
        );

        bytes32 expectedAssertionHash = RollupLib.assertionHash({
            parentAssertionHash: parentAssertionHash, afterState: assertionState, inboxAcc: inboxAcc
        });

        bool validatorIsStaked = userRollup.isStaked(validator);

        vm.prank(validator);
        if (validatorIsStaked) {
            userRollup.stakeOnNewAssertion({
                assertion: AssertionInputs({
                    beforeStateData: parentAssertionStateData,
                    beforeState: parentAssertionState,
                    afterState: assertionState
                }),
                expectedAssertionHash: expectedAssertionHash
            });
        } else {
            userRollup.newStakeOnNewAssertion({
                tokenAmount: BASE_STAKE,
                assertion: AssertionInputs({
                    beforeStateData: parentAssertionStateData,
                    beforeState: parentAssertionState,
                    afterState: assertionState
                }),
                expectedAssertionHash: expectedAssertionHash,
                _withdrawalAddress: validatorWithdrawal
            });
        }

        return (expectedAssertionHash, parentAssertionHash);
    }

    function _createAssertion(
        BeforeStateData memory parentAssertionStateData,
        AssertionState memory parentAssertionState,
        AssertionState memory assertionState,
        bytes32 inboxAcc
    ) internal returns (bytes32, bytes32) {
        return _createAssertionWithValidator(
            parentAssertionStateData,
            parentAssertionState,
            assertionState,
            inboxAcc,
            validator1,
            validator1Withdrawal
        );
    }

    function testGenesisAssertionsConfirmed() external {
        // Genesis assertion should be confirmed
        assertEq(
            userRollup.getAssertion(genesisAssertionHash).status == AssertionStatus.Confirmed, true
        );

        // Post-genesis assertion should be the latest and should be confirmed
        bytes32 latestConfirmed = userRollup.latestConfirmed();
        assertEq(latestConfirmed, postGenesisAssertionHash);
        assertEq(userRollup.getAssertion(latestConfirmed).status == AssertionStatus.Confirmed, true);
    }

    function testSuccessPause() public {
        vm.prank(upgradeExecutorAddr);
        adminRollup.pause();
    }

    function testConfirmAssertionWhenPaused() public {
        (
            bytes32 assertionHash,
            AssertionState memory assertionState,,,
            bytes32 parentAssertionHash
        ) = testSuccessCreateAssertion();

        // Advance confirmation period
        vm.roll(
            userRollup.getAssertion(parentAssertionHash).firstChildBlock + CONFIRM_PERIOD_BLOCKS + 1
        );

        // Inbox accumulator of the assertion being confirmed
        bytes32 inboxAcc =
            userRollup.bridge().sequencerInboxAccs(assertionState.globalState.u64Vals[0] - 1);

        // Pause rollup
        vm.prank(upgradeExecutorAddr);
        adminRollup.pause();

        // Try to confirm assertion
        vm.prank(validator1);
        vm.expectRevert("Pausable: paused");
        userRollup.confirmAssertion(
            assertionHash,
            parentAssertionHash,
            assertionState,
            bytes32(0),
            postGenesisConfigData,
            inboxAcc
        );
    }

    function testSuccessPauseResume() public {
        testSuccessPause();
        vm.prank(upgradeExecutorAddr);
        adminRollup.resume();
    }

    function testSuccessOwner() public {
        assertEq(userRollup.owner(), upgradeExecutorAddr);
    }

    function testSuccessRemoveWhitelistAfterFork() public {
        vm.chainId(313377);
        userRollup.removeWhitelistAfterFork();
    }

    function testRevertRemoveWhitelistAfterFork() public {
        vm.expectRevert("CHAIN_ID_NOT_CHANGED");
        userRollup.removeWhitelistAfterFork();
    }

    function testRevertRemoveWhitelistAfterForkAgain() public {
        testSuccessRemoveWhitelistAfterFork();
        vm.expectRevert("WHITELIST_DISABLED");
        userRollup.removeWhitelistAfterFork();
    }

    // Assumed it's called after the genesis and post-genesis assertions have been created.
    //
    // Returns (expectedAssertionHash, afterState, inboxcount, nextParentChainBlockHash, parentAssertionHash)
    function testSuccessCreateAssertion()
        public
        returns (bytes32, AssertionState memory, uint64, bytes32, bytes32)
    {
        uint64 inboxcount = uint64(_createNewBatch());
        vm.roll(block.number + 1);

        (bytes32 assertionHash, bytes32 parentAssertionHash) = _createAssertion(
            BeforeStateData({
                sequencerBatchAcc: bytes32(0),
                prevPrevAssertionHash: genesisAssertionHash,
                configData: postGenesisConfigData
            }),
            postGenesisAssertionState,
            firstAssertionState,
            userRollup.bridge().sequencerInboxAccs(firstAssertionState.globalState.u64Vals[0] - 1)
        );

        assertEq(parentAssertionHash, postGenesisAssertionHash);

        bytes32 nextParentChainBlockHash = blockhash(block.number - 1);

        return (
            assertionHash,
            firstAssertionState,
            inboxcount,
            nextParentChainBlockHash,
            postGenesisAssertionHash
        );
    }

    function testValidateConfigZeroNextParentChainBlockHash() public view {
        userRollup.validateConfig(genesisAssertionHash, genesisConfigData);
    }

    function testRevertValidateConfigNonZeroNextParentChainBlockHash() public {
        ConfigData memory modifiedGenesisConfigData = genesisConfigData;
        modifiedGenesisConfigData.nextParentChainBlockHash = keccak256("NON_ZERO");
        vm.expectRevert("CONFIG_HASH_MISMATCH");
        userRollup.validateConfig(genesisAssertionHash, modifiedGenesisConfigData);
    }

    function testAssertionCreatedEmitsNextParentChainBlockHash() public {
        bytes32 inboxAcc =
            userRollup.bridge().sequencerInboxAccs(firstAssertionState.globalState.u64Vals[0] - 1);

        vm.expectEmit(true, true, false, true);
        emit AssertionCreated(
            RollupLib.assertionHash(postGenesisAssertionHash, firstAssertionState, inboxAcc),
            postGenesisAssertionHash,
            AssertionInputs({
                beforeStateData: BeforeStateData({
                    sequencerBatchAcc: bytes32(0),
                    prevPrevAssertionHash: genesisAssertionHash,
                    configData: postGenesisConfigData
                }),
                beforeState: postGenesisAssertionState,
                afterState: firstAssertionState
            }),
            inboxAcc,
            2,
            blockhash(block.number - 1),
            WASM_MODULE_ROOT,
            BASE_STAKE,
            address(challengeManager),
            CONFIRM_PERIOD_BLOCKS
        );

        _createAssertion(
            BeforeStateData({
                sequencerBatchAcc: bytes32(0),
                prevPrevAssertionHash: genesisAssertionHash,
                configData: postGenesisConfigData
            }),
            postGenesisAssertionState,
            firstAssertionState,
            userRollup.bridge().sequencerInboxAccs(firstAssertionState.globalState.u64Vals[0] - 1)
        );
    }

    function testSuccessCreateAssertionUsingAddToDeposit() public {
        vm.prank(validator2);
        userRollup.newStake(0, validator2Withdrawal);

        address rando = address(98139098);
        token.transfer(rando, BASE_STAKE);

        vm.startPrank(rando);
        token.approve(address(userRollup), BASE_STAKE);
        userRollup.addToDeposit(validator2, validator2Withdrawal, BASE_STAKE);
        vm.stopPrank();

        _createAssertionWithValidator(
            BeforeStateData({
                sequencerBatchAcc: bytes32(0),
                prevPrevAssertionHash: genesisAssertionHash,
                configData: postGenesisConfigData
            }),
            postGenesisAssertionState,
            firstAssertionState,
            userRollup.bridge().sequencerInboxAccs(firstAssertionState.globalState.u64Vals[0] - 1),
            validator2,
            validator2Withdrawal
        );
    }

    function testPartialDepositCanWithdraw() public {
        IRollupCore.Staker memory emptyStaker;

        vm.prank(validator2);
        userRollup.newStake(10, validator2Withdrawal);

        uint256 snapshot = vm.snapshot();

        vm.prank(validator2);
        userRollup.returnOldDeposit();

        vm.prank(validator2Withdrawal);
        userRollup.withdrawStakerFunds();

        assertEq(token.balanceOf(validator2Withdrawal), 10);
        assertEq(
            keccak256(abi.encode(userRollup.getStaker(validator2))),
            keccak256(abi.encode(emptyStaker))
        );

        vm.revertTo(snapshot);

        vm.startPrank(validator2Withdrawal);
        userRollup.returnOldDepositFor(validator2);
        userRollup.withdrawStakerFunds();
        vm.stopPrank();

        assertEq(token.balanceOf(validator2Withdrawal), 10);
        assertEq(
            keccak256(abi.encode(userRollup.getStaker(validator2))),
            keccak256(abi.encode(emptyStaker))
        );
    }

    function testPartialDepositCannotMakeAssertion() public {
        vm.prank(validator2);
        userRollup.newStake(BASE_STAKE - 1, validator2Withdrawal);

        BeforeStateData memory postGenesisAssertionStateData = BeforeStateData({
            sequencerBatchAcc: bytes32(0),
            prevPrevAssertionHash: genesisAssertionHash,
            configData: postGenesisConfigData
        });

        bytes32 expectedAssertionHash = RollupLib.assertionHash({
            parentAssertionHash: postGenesisAssertionHash,
            afterState: firstAssertionState,
            inboxAcc: userRollup.bridge()
                .sequencerInboxAccs(firstAssertionState.globalState.u64Vals[0] - 1)
        });

        vm.prank(validator2);
        vm.expectRevert("INSUFFICIENT_STAKE");
        userRollup.stakeOnNewAssertion({
            assertion: AssertionInputs({
                beforeStateData: postGenesisAssertionStateData,
                beforeState: postGenesisAssertionState,
                afterState: firstAssertionState
            }),
            expectedAssertionHash: expectedAssertionHash
        });
    }

    function testSuccessGetStaker() public {
        testSuccessCreateAssertion();
        assertEq(userRollup.stakerCount(), 1);
        assertEq(userRollup.getStakerAddress(userRollup.getStaker(validator1).index), validator1);
    }

    function testSuccessCreateErroredAssertions() public {
        AssertionState memory erroredAssertionState = firstAssertionState;
        erroredAssertionState.machineStatus = MachineStatus.ERRORED;
        _createAssertion(
            BeforeStateData({
                sequencerBatchAcc: bytes32(0),
                prevPrevAssertionHash: genesisAssertionHash,
                configData: postGenesisConfigData
            }),
            postGenesisAssertionState,
            erroredAssertionState,
            userRollup.bridge().sequencerInboxAccs(erroredAssertionState.globalState.u64Vals[0] - 1)
        );
    }

    function testRevertIdenticalAssertions() public {
        // Create first assertion
        _createAssertion(
            BeforeStateData({
                sequencerBatchAcc: bytes32(0),
                prevPrevAssertionHash: genesisAssertionHash,
                configData: postGenesisConfigData
            }),
            postGenesisAssertionState,
            firstAssertionState,
            userRollup.bridge().sequencerInboxAccs(firstAssertionState.globalState.u64Vals[0] - 1)
        );

        // Create second, identical, assertion
        BeforeStateData memory postGenesisAssertionStateData = BeforeStateData({
            sequencerBatchAcc: bytes32(0),
            prevPrevAssertionHash: genesisAssertionHash,
            configData: postGenesisConfigData
        });

        bytes32 expectedAssertionHash = RollupLib.assertionHash({
            parentAssertionHash: postGenesisAssertionHash,
            afterState: firstAssertionState,
            inboxAcc: userRollup.bridge()
                .sequencerInboxAccs(firstAssertionState.globalState.u64Vals[0] - 1)
        });

        vm.prank(validator2);
        vm.expectRevert("EXPECTED_ASSERTION_SEEN");
        userRollup.newStakeOnNewAssertion({
            tokenAmount: BASE_STAKE,
            assertion: AssertionInputs({
                beforeStateData: postGenesisAssertionStateData,
                beforeState: postGenesisAssertionState,
                afterState: firstAssertionState
            }),
            expectedAssertionHash: expectedAssertionHash,
            _withdrawalAddress: validator2Withdrawal
        });
    }

    function testRevertInvalidPrev() public {
        (
            bytes32 assertionHash,
            AssertionState memory assertionState,
            uint64 inboxcount,
            bytes32 nextParentChainBlockHash,
            bytes32 parentAssertionHash
        ) = testSuccessCreateAssertion();

        AssertionState memory afterState;
        afterState.machineStatus = MachineStatus.FINISHED;
        afterState.globalState.bytes32Vals[0] = FIRST_ASSERTION_BLOCKHASH; // blockhash
        afterState.globalState.bytes32Vals[1] = FIRST_ASSERTION_SENDROOT; // sendroot
        afterState.globalState.u64Vals[0] = inboxcount; // inbox count
        afterState.globalState.u64Vals[1] = 0; // pos in msg
        bytes32 expectedAssertionHash = RollupLib.assertionHash({
            parentAssertionHash: assertionHash,
            afterState: afterState,
            inboxAcc: userRollup.bridge().sequencerInboxAccs(afterState.globalState.u64Vals[0] - 1)
        });
        bytes32 prevInboxAcc =
            userRollup.bridge().sequencerInboxAccs(assertionState.globalState.u64Vals[0] - 1);

        // set the wrong before state
        assertionState.globalState.bytes32Vals[0] = FIRST_ASSERTION_SENDROOT;

        vm.roll(block.number + minimumAssertionPeriod);
        vm.prank(validator1);
        vm.expectRevert("ASSERTION_NOT_EXIST");
        userRollup.stakeOnNewAssertion({
            assertion: AssertionInputs({
                beforeStateData: BeforeStateData({
                    sequencerBatchAcc: prevInboxAcc,
                    prevPrevAssertionHash: parentAssertionHash,
                    configData: ConfigData({
                        wasmModuleRoot: WASM_MODULE_ROOT,
                        requiredStake: BASE_STAKE,
                        challengeManager: address(challengeManager),
                        confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
                        nextInboxPosition: afterState.globalState.u64Vals[0],
                        nextParentChainBlockHash: nextParentChainBlockHash
                    })
                }),
                beforeState: assertionState,
                afterState: afterState
            }),
            expectedAssertionHash: expectedAssertionHash
        });
    }

    // need to have these in storage due to stack limit
    bytes32[] randomStates1;
    bytes32[] randomStates2;

    function testSuccessCreateSecondChild()
        public
        returns (
            AssertionState memory,
            AssertionState memory,
            AssertionState memory,
            uint256,
            uint256,
            bytes32,
            bytes32,
            bytes32
        )
    {
        uint256 initialInboxCount = userRollup.bridge().sequencerMessageCount();
        uint64 newInboxCount = uint64(_createNewBatch());

        // Assertion created on top of post-genesis assertion
        AssertionState memory beforeState = postGenesisAssertionState;
        AssertionState memory afterState;
        afterState.machineStatus = MachineStatus.FINISHED;
        afterState.globalState.bytes32Vals[0] = FIRST_ASSERTION_BLOCKHASH; // blockhash
        afterState.globalState.bytes32Vals[1] = FIRST_ASSERTION_SENDROOT; // sendroot
        afterState.globalState.u64Vals[0] = uint64(initialInboxCount); // inbox count
        afterState.globalState.u64Vals[1] = 0; // pos in msg

        {
            IOneStepProofEntry osp = userRollup.challengeManager().oneStepProofEntry();
            bytes32 h0 = osp.getMachineHash(beforeState.toExecutionState());
            bytes32 h1 = osp.getMachineHash(afterState.toExecutionState());
            randomStates1 = fillStatesInBetween(h0, h1, LAYERZERO_BLOCKEDGE_HEIGHT + 1);
            afterState.endHistoryRoot = MerkleTreeAccumulatorLib.root(
                ProofUtils.expansionFromLeaves(randomStates1, 0, LAYERZERO_BLOCKEDGE_HEIGHT + 1)
            );
        }

        bytes32 expectedAssertionHash = RollupLib.assertionHash({
            parentAssertionHash: postGenesisAssertionHash,
            afterState: afterState,
            inboxAcc: userRollup.bridge().sequencerInboxAccs(afterState.globalState.u64Vals[0] - 1)
        });

        vm.prank(validator1);
        userRollup.stakeOnNewAssertion({
            assertion: AssertionInputs({
                beforeStateData: BeforeStateData({
                    sequencerBatchAcc: bytes32(0),
                    prevPrevAssertionHash: genesisAssertionHash,
                    configData: postGenesisConfigData
                }),
                beforeState: beforeState,
                afterState: afterState
            }),
            expectedAssertionHash: expectedAssertionHash
        });

        // Second assertion, also created on top of post-genesis assertion
        AssertionState memory afterState2;
        afterState2.machineStatus = MachineStatus.FINISHED;
        afterState2.globalState.bytes32Vals[0] =
            keccak256(abi.encodePacked(FIRST_ASSERTION_BLOCKHASH)); // blockhash
        afterState2.globalState.bytes32Vals[1] =
            keccak256(abi.encodePacked(FIRST_ASSERTION_SENDROOT)); // sendroot
        afterState2.globalState.u64Vals[0] = uint64(initialInboxCount); // inbox count
        afterState2.globalState.u64Vals[1] = 0; // modify the state

        {
            IOneStepProofEntry osp = userRollup.challengeManager().oneStepProofEntry();
            bytes32 h0 = osp.getMachineHash(beforeState.toExecutionState());
            bytes32 h1 = osp.getMachineHash(afterState2.toExecutionState());
            randomStates2 = fillStatesInBetween(h0, h1, LAYERZERO_BLOCKEDGE_HEIGHT + 1);
            afterState2.endHistoryRoot = MerkleTreeAccumulatorLib.root(
                ProofUtils.expansionFromLeaves(randomStates2, 0, LAYERZERO_BLOCKEDGE_HEIGHT + 1)
            );
        }

        bytes32 expectedAssertionHash2 = RollupLib.assertionHash({
            parentAssertionHash: postGenesisAssertionHash,
            afterState: afterState2,
            inboxAcc: userRollup.bridge().sequencerInboxAccs(afterState2.globalState.u64Vals[0] - 1)
        });
        vm.prank(validator2);
        userRollup.newStakeOnNewAssertion({
            tokenAmount: BASE_STAKE,
            assertion: AssertionInputs({
                beforeStateData: BeforeStateData({
                    sequencerBatchAcc: bytes32(0),
                    prevPrevAssertionHash: genesisAssertionHash,
                    configData: postGenesisConfigData
                }),
                beforeState: beforeState,
                afterState: afterState2
            }),
            expectedAssertionHash: expectedAssertionHash2,
            _withdrawalAddress: validator2Withdrawal
        });

        assertEq(userRollup.getAssertion(postGenesisAssertionHash).secondChildBlock, block.number);

        bytes32 nextParentChainBlockHash = blockhash(block.number - 1);

        return (
            beforeState,
            afterState,
            afterState2,
            initialInboxCount,
            newInboxCount,
            expectedAssertionHash,
            expectedAssertionHash2,
            nextParentChainBlockHash
        );
    }

    function testSuccessCreateSecondChildDifferentRoot()
        public
        returns (SuccessCreateChallengeData memory data)
    {
        (
            data.beforeState,
            data.afterState1,
            data.afterState2,
            data.initialInboxCount,
            data.newInboxCount,
            data.assertionHash,
            data.assertionHash2,
            data.nextParentChainBlockHash
        ) = testSuccessCreateSecondChild();
        AssertionState memory afterState3 = data.afterState2;
        afterState3.endHistoryRoot = keccak256(abi.encode(afterState3.endHistoryRoot));

        bytes32 expectedAssertionHash3 = RollupLib.assertionHash({
            parentAssertionHash: postGenesisAssertionHash,
            afterState: afterState3,
            inboxAcc: userRollup.bridge().sequencerInboxAccs(afterState3.globalState.u64Vals[0] - 1)
        });

        vm.prank(validator3);
        userRollup.newStakeOnNewAssertion({
            tokenAmount: BASE_STAKE,
            assertion: AssertionInputs({
                beforeStateData: BeforeStateData({
                    sequencerBatchAcc: bytes32(0),
                    prevPrevAssertionHash: genesisAssertionHash,
                    configData: postGenesisConfigData
                }),
                beforeState: data.beforeState,
                afterState: afterState3
            }),
            expectedAssertionHash: expectedAssertionHash3,
            _withdrawalAddress: validator3Withdrawal
        });
    }

    function testRevertConfirmWrongInput() public {
        (
            bytes32 assertionHash,
            AssertionState memory assertionState,,,
            bytes32 parentAssertionHash
        ) = testSuccessCreateAssertion();
        bytes32 inboxAcc =
            userRollup.bridge().sequencerInboxAccs(assertionState.globalState.u64Vals[0] - 1);

        vm.roll(
            userRollup.getAssertion(parentAssertionHash).firstChildBlock + CONFIRM_PERIOD_BLOCKS + 1
        );
        vm.prank(validator1);
        vm.expectRevert("CONFIRM_DATA");
        userRollup.confirmAssertion(
            assertionHash,
            parentAssertionHash,
            genesisAssertionState, // Purposedly wrong input
            bytes32(0),
            postGenesisConfigData,
            inboxAcc
        );
    }

    function testSuccessConfirmUnchallengedAssertions()
        public
        returns (bytes32, AssertionState memory, uint64, bytes32)
    {
        (
            bytes32 assertionHash,
            AssertionState memory assertionState,
            uint64 inboxcount,
            bytes32 nextParentChainBlockHash,
            bytes32 parentAssertionHash
        ) = testSuccessCreateAssertion();
        bytes32 inboxAcc =
            userRollup.bridge().sequencerInboxAccs(assertionState.globalState.u64Vals[0] - 1);

        vm.roll(
            userRollup.getAssertion(parentAssertionHash).firstChildBlock + CONFIRM_PERIOD_BLOCKS + 1
        );
        vm.prank(validator1);
        userRollup.confirmAssertion(
            assertionHash,
            parentAssertionHash,
            assertionState,
            bytes32(0),
            postGenesisConfigData,
            inboxAcc
        );
        return (assertionHash, assertionState, inboxcount, nextParentChainBlockHash);
    }

    function testSuccessRemoveWhitelistAfterValidatorAfk() public {
        (bytes32 assertionHash,,,) = testSuccessConfirmUnchallengedAssertions();
        vm.roll(
            userRollup.getAssertion(assertionHash).createdAtBlock + userRollup.validatorAfkBlocks()
                + 1
        );
        userRollup.removeWhitelistAfterValidatorAfk();
    }

    function testSuccessSetValidatorAfk(
        uint32 x
    ) public {
        vm.assume(x > 0);
        (bytes32 assertionHash,,,) = testSuccessConfirmUnchallengedAssertions();
        vm.prank(upgradeExecutorAddr);
        adminRollup.setValidatorAfkBlocks(x);
        vm.roll(userRollup.getAssertion(assertionHash).createdAtBlock + x);
        vm.expectRevert("VALIDATOR_NOT_AFK");
        userRollup.removeWhitelistAfterValidatorAfk();
        vm.roll(block.number + 1);
        userRollup.removeWhitelistAfterValidatorAfk();
    }

    function testSuccessValidatorAfkDisable() public {
        (bytes32 assertionHash,,,) = testSuccessConfirmUnchallengedAssertions();
        vm.prank(upgradeExecutorAddr);
        adminRollup.setValidatorAfkBlocks(0); // set 0 to disable
        vm.roll(userRollup.getAssertion(assertionHash).createdAtBlock + 1);
        vm.expectRevert("VALIDATOR_NOT_AFK");
        userRollup.removeWhitelistAfterValidatorAfk();
    }

    function testRevertRemoveWhitelistAfterValidatorAfk() public {
        vm.expectRevert("VALIDATOR_NOT_AFK");
        userRollup.removeWhitelistAfterValidatorAfk();
    }

    function testRevertConfirmSiblingedAssertions() public {
        (, AssertionState memory assertionState,,,, bytes32 assertionHash,,) =
            testSuccessCreateSecondChild();
        bytes32 inboxAcc =
            userRollup.bridge().sequencerInboxAccs(assertionState.globalState.u64Vals[0] - 1);

        vm.roll(
            userRollup.getAssertion(postGenesisAssertionHash).firstChildBlock
                + CONFIRM_PERIOD_BLOCKS + 1
        );
        vm.prank(validator1);
        vm.expectRevert(abi.encodeWithSelector(EdgeNotExists.selector, bytes32(0)));
        userRollup.confirmAssertion(
            assertionHash,
            postGenesisAssertionHash,
            assertionState,
            bytes32(0),
            postGenesisConfigData,
            inboxAcc
        );
    }

    struct SuccessCreateChallengeData {
        AssertionState beforeState;
        uint256 initialInboxCount;
        AssertionState afterState1;
        AssertionState afterState2;
        uint256 newInboxCount;
        bytes32 e1Id;
        bytes32 assertionHash;
        bytes32 assertionHash2;
        bytes32 nextParentChainBlockHash;
    }

    function testSuccessCreateChallenge() public returns (SuccessCreateChallengeData memory data) {
        (
            data.beforeState,
            data.afterState1,
            data.afterState2,
            data.initialInboxCount,
            data.newInboxCount,
            data.assertionHash,
            data.assertionHash2,
            data.nextParentChainBlockHash
        ) = testSuccessCreateSecondChild();

        bytes32 root = MerkleTreeAccumulatorLib.root(
            ProofUtils.expansionFromLeaves(randomStates1, 0, LAYERZERO_BLOCKEDGE_HEIGHT + 1)
        );

        data.e1Id = challengeManager.createLayerZeroEdge(
            CreateEdgeArgs({
                level: 0,
                endHistoryRoot: root,
                endHeight: LAYERZERO_BLOCKEDGE_HEIGHT,
                claimId: data.assertionHash,
                prefixProof: abi.encode(
                    ProofUtils.expansionFromLeaves(randomStates1, 0, 1),
                    ProofUtils.generatePrefixProof(
                        1, ArrayUtilsLib.slice(randomStates1, 1, randomStates1.length)
                    )
                ),
                proof: abi.encode(
                    ProofUtils.generateInclusionProof(
                        ProofUtils.rehashed(randomStates1), randomStates1.length - 1
                    ),
                    AssertionStateData(data.beforeState, genesisAssertionHash, bytes32(0)),
                    AssertionStateData(
                        data.afterState1,
                        postGenesisAssertionHash,
                        userRollup.bridge()
                            .sequencerInboxAccs(data.afterState1.globalState.u64Vals[0] - 1)
                    )
                )
            })
        );
    }

    function testSuccessCreate2Edge() public returns (bytes32, bytes32) {
        SuccessCreateChallengeData memory data = testSuccessCreateChallenge();
        require(data.initialInboxCount == 2, "A");
        require(data.newInboxCount == data.initialInboxCount + 1, "B");

        bytes32 root = MerkleTreeAccumulatorLib.root(
            ProofUtils.expansionFromLeaves(randomStates2, 0, LAYERZERO_BLOCKEDGE_HEIGHT + 1)
        );

        token.transfer(validator1, 1 ether);
        vm.startPrank(validator1);
        bytes32 e2Id = challengeManager.createLayerZeroEdge(
            CreateEdgeArgs({
                level: 0,
                endHistoryRoot: root,
                endHeight: LAYERZERO_BLOCKEDGE_HEIGHT,
                claimId: data.assertionHash2,
                prefixProof: abi.encode(
                    ProofUtils.expansionFromLeaves(randomStates2, 0, 1),
                    ProofUtils.generatePrefixProof(
                        1, ArrayUtilsLib.slice(randomStates2, 1, randomStates2.length)
                    )
                ),
                proof: abi.encode(
                    ProofUtils.generateInclusionProof(
                        ProofUtils.rehashed(randomStates2), randomStates2.length - 1
                    ),
                    AssertionStateData(data.beforeState, genesisAssertionHash, bytes32(0)),
                    AssertionStateData(
                        data.afterState2,
                        postGenesisAssertionHash,
                        userRollup.bridge()
                            .sequencerInboxAccs(data.afterState2.globalState.u64Vals[0] - 1)
                    )
                )
            })
        );
        vm.stopPrank();

        return (data.e1Id, e2Id);
    }

    function fillStatesInBetween(
        bytes32 start,
        bytes32 end,
        uint256 totalCount
    ) internal returns (bytes32[] memory) {
        bytes32[] memory innerStates = rand.hashes(totalCount - 2);

        bytes32[] memory states = new bytes32[](totalCount);
        states[0] = start;
        for (uint256 i = 0; i < innerStates.length; i++) {
            states[i + 1] = innerStates[i];
        }
        states[totalCount - 1] = end;

        return states;
    }

    function testSuccessConfirmEdgeByTime() public returns (bytes32) {
        SuccessCreateChallengeData memory data = testSuccessCreateChallenge();
        bytes32 inboxAcc =
            userRollup.bridge().sequencerInboxAccs(data.afterState1.globalState.u64Vals[0] - 1);

        vm.roll(
            userRollup.getAssertion(postGenesisAssertionHash).firstChildBlock
                + CONFIRM_PERIOD_BLOCKS + 1
        );
        vm.warp(block.timestamp + CONFIRM_PERIOD_BLOCKS * 15);
        userRollup.challengeManager()
            .confirmEdgeByTime(
                data.e1Id, AssertionStateData(data.afterState1, postGenesisAssertionHash, inboxAcc)
            );

        vm.roll(block.number + userRollup.challengeGracePeriodBlocks());
        vm.prank(validator1);
        userRollup.confirmAssertion(
            data.assertionHash,
            postGenesisAssertionHash,
            data.afterState1,
            data.e1Id,
            postGenesisConfigData,
            inboxAcc
        );
        return data.e1Id;
    }

    function testRevertConfirmBeforeAfterPeriodBlocks() public returns (bytes32) {
        SuccessCreateChallengeData memory data = testSuccessCreateChallenge();
        bytes32 inboxAcc =
            userRollup.bridge().sequencerInboxAccs(data.afterState1.globalState.u64Vals[0] - 1);

        vm.roll(
            userRollup.getAssertion(postGenesisAssertionHash).firstChildBlock
                + CONFIRM_PERIOD_BLOCKS + 1
        );
        vm.warp(block.timestamp + CONFIRM_PERIOD_BLOCKS * 15);
        userRollup.challengeManager()
            .confirmEdgeByTime(
                data.e1Id, AssertionStateData(data.afterState1, postGenesisAssertionHash, inboxAcc)
            );

        vm.roll(block.number + userRollup.challengeGracePeriodBlocks() - 1);
        vm.prank(validator1);
        vm.expectRevert("CHALLENGE_GRACE_PERIOD_NOT_PASSED");
        userRollup.confirmAssertion(
            data.assertionHash,
            postGenesisAssertionHash,
            data.afterState1,
            data.e1Id,
            postGenesisConfigData,
            inboxAcc
        );
        return data.e1Id;
    }

    function testRevertWithdrawStake() public {
        testSuccessConfirmEdgeByTime();
        vm.prank(validator1);
        vm.expectRevert("NO_FUNDS_TO_WITHDRAW");
        userRollup.withdrawStakerFunds();
    }

    function testSuccessWithdrawStake() public {
        testSuccessConfirmEdgeByTime();
        vm.prank(validator1);
        userRollup.returnOldDeposit();

        RollupCore.Staker memory emptyStaker;
        assertEq(
            keccak256(abi.encode(emptyStaker)),
            keccak256(abi.encode(userRollup.getStaker(validator1)))
        );

        assertGt(userRollup.withdrawableFunds(validator1Withdrawal), 0);
        assertEq(token.balanceOf(validator1Withdrawal), 0);
        vm.prank(validator1Withdrawal);
        userRollup.withdrawStakerFunds();
        assertEq(token.balanceOf(validator1Withdrawal), BASE_STAKE);
    }

    function testRevertWithdrawActiveStake() public {
        testSuccessConfirmEdgeByTime();
        vm.prank(validator2);
        vm.expectRevert("STAKE_ACTIVE");
        userRollup.returnOldDeposit();
    }

    function testSuccessWithdrawExcessStake() public {
        uint256 prevBal = token.balanceOf(loserStakeEscrow);
        testSuccessCreateSecondChild();
        uint256 afterBal = token.balanceOf(loserStakeEscrow);
        assertEq(afterBal - prevBal, BASE_STAKE, "loser stake not sent to escrow");
    }

    function testRevertAlreadyStaked() public {
        testSuccessCreateAssertion();
        vm.prank(validator1);
        AssertionInputs memory emptyAssertion;
        vm.expectRevert("ALREADY_STAKED");
        userRollup.newStakeOnNewAssertion({
            tokenAmount: BASE_STAKE,
            assertion: emptyAssertion,
            expectedAssertionHash: bytes32(0),
            _withdrawalAddress: validator2Withdrawal
        });
    }

    function testRevertZeroWithdrawalAddress() public {
        testSuccessCreateAssertion();
        vm.prank(validator1);
        AssertionInputs memory emptyAssertion;
        vm.expectRevert("EMPTY_WITHDRAWAL_ADDRESS");
        userRollup.newStakeOnNewAssertion({
            tokenAmount: BASE_STAKE,
            assertion: emptyAssertion,
            expectedAssertionHash: bytes32(0),
            _withdrawalAddress: address(0)
        });
    }

    function testSuccessReduceDeposit() public {
        testSuccessConfirmEdgeByTime();
        vm.prank(validator1);
        userRollup.reduceDeposit(1);
    }

    function testRevertReduceDepositActive() public {
        testSuccessCreateAssertion();
        vm.prank(validator1);
        vm.expectRevert("STAKE_ACTIVE");
        userRollup.reduceDeposit(1);
    }

    function testAddToDepositWithdrawalAddressCheck() public {
        testSuccessConfirmEdgeByTime();
        vm.prank(validator1);
        vm.expectRevert("WRONG_WITHDRAWAL_ADDRESS");
        userRollup.addToDeposit(validator1, validator2Withdrawal, 1);
    }

    function testSuccessAddToDeposit() public {
        testSuccessConfirmEdgeByTime();
        vm.prank(validator1);
        userRollup.addToDeposit(validator1, validator1Withdrawal, 1);
    }

    function testRevertAddToDepositNotValidator() public {
        testSuccessConfirmEdgeByTime();
        vm.prank(sequencer);
        vm.expectRevert("NOT_VALIDATOR");
        userRollup.addToDeposit(address(10043902309), address(92803809), 1);
    }

    function testRevertAddToDepositNotStaker() public {
        testSuccessConfirmEdgeByTime();
        vm.prank(validator1);
        vm.expectRevert("NOT_STAKED");
        userRollup.addToDeposit(address(this), validator2Withdrawal, 1);
    }

    function testSuccessCreateSecondAssertion()
        public
        returns (bytes32, bytes32, AssertionState memory, bytes32)
    {
        (
            bytes32 prevAssertionHash,
            AssertionState memory beforeState,
            uint64 inboxCount,
            bytes32 nextParentChainBlockHash,
            bytes32 prevParentAssertionHash
        ) = testSuccessCreateAssertion();

        AssertionState memory afterState;
        afterState.machineStatus = MachineStatus.FINISHED;
        afterState.globalState.bytes32Vals[0] = FIRST_ASSERTION_BLOCKHASH; // blockhash
        afterState.globalState.bytes32Vals[1] = FIRST_ASSERTION_SENDROOT; // sendroot
        afterState.globalState.u64Vals[0] = inboxCount; // inbox count
        afterState.globalState.u64Vals[1] = 0; // pos in msg

        bytes32 inboxAcc =
            userRollup.bridge().sequencerInboxAccs(afterState.globalState.u64Vals[0] - 1);
        bytes32 expectedAssertionHash = RollupLib.assertionHash({
            parentAssertionHash: prevAssertionHash, afterState: afterState, inboxAcc: inboxAcc
        });
        bytes32 prevInboxAcc =
            userRollup.bridge().sequencerInboxAccs(beforeState.globalState.u64Vals[0] - 1);

        vm.roll(block.number + minimumAssertionPeriod);
        vm.prank(validator1);
        userRollup.stakeOnNewAssertion({
            assertion: AssertionInputs({
                beforeStateData: BeforeStateData({
                    sequencerBatchAcc: prevInboxAcc,
                    prevPrevAssertionHash: prevParentAssertionHash,
                    configData: ConfigData({
                        wasmModuleRoot: WASM_MODULE_ROOT,
                        requiredStake: BASE_STAKE,
                        challengeManager: address(challengeManager),
                        confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
                        nextInboxPosition: afterState.globalState.u64Vals[0],
                        nextParentChainBlockHash: nextParentChainBlockHash
                    })
                }),
                beforeState: beforeState,
                afterState: afterState
            }),
            expectedAssertionHash: expectedAssertionHash
        });
        return (prevAssertionHash, expectedAssertionHash, afterState, inboxAcc);
    }

    function testRevertCreateChildReducedStake() public {
        (
            bytes32 prevAssertionHash,
            AssertionState memory beforeState,
            uint64 inboxCount,
            bytes32 nextParentChainBlockHash
        ) = testSuccessConfirmUnchallengedAssertions();

        vm.prank(validator1);
        userRollup.reduceDeposit(1);

        AssertionState memory afterState;
        afterState.machineStatus = MachineStatus.FINISHED;
        afterState.globalState.bytes32Vals[0] = FIRST_ASSERTION_BLOCKHASH; // blockhash
        afterState.globalState.bytes32Vals[1] = FIRST_ASSERTION_SENDROOT; // sendroot
        afterState.globalState.u64Vals[0] = inboxCount; // inbox count
        afterState.globalState.u64Vals[1] = 0; // pos in msg

        bytes32 inboxAcc =
            userRollup.bridge().sequencerInboxAccs(afterState.globalState.u64Vals[0] - 1);
        bytes32 expectedAssertionHash = RollupLib.assertionHash({
            parentAssertionHash: prevAssertionHash, afterState: afterState, inboxAcc: inboxAcc
        });
        bytes32 prevInboxAcc =
            userRollup.bridge().sequencerInboxAccs(beforeState.globalState.u64Vals[0] - 1);

        vm.roll(block.number + minimumAssertionPeriod);
        vm.prank(validator1);
        vm.expectRevert("INSUFFICIENT_STAKE");
        userRollup.stakeOnNewAssertion({
            assertion: AssertionInputs({
                beforeStateData: BeforeStateData({
                    sequencerBatchAcc: prevInboxAcc,
                    prevPrevAssertionHash: postGenesisAssertionHash,
                    configData: ConfigData({
                        wasmModuleRoot: WASM_MODULE_ROOT,
                        requiredStake: BASE_STAKE,
                        challengeManager: address(challengeManager),
                        confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
                        nextInboxPosition: inboxCount,
                        nextParentChainBlockHash: nextParentChainBlockHash
                    })
                }),
                beforeState: beforeState,
                afterState: afterState
            }),
            expectedAssertionHash: expectedAssertionHash
        });
    }

    function testSuccessFastConfirmNext() public {
        (
            bytes32 assertionHash,
            AssertionState memory assertionState,,,
            bytes32 parentAssertionHash
        ) = testSuccessCreateAssertion();
        bytes32 inboxAcc =
            userRollup.bridge().sequencerInboxAccs(assertionState.globalState.u64Vals[0] - 1);
        assertEq(userRollup.latestConfirmed(), parentAssertionHash);
        vm.prank(anyTrustFastConfirmer);
        userRollup.fastConfirmAssertion(
            assertionHash, parentAssertionHash, assertionState, inboxAcc
        );
        assertEq(userRollup.latestConfirmed(), assertionHash);
    }

    function testSuccessFastConfirmSkipOne() public {
        (
            bytes32 prevHash,
            bytes32 assertionHash,
            AssertionState memory afterState,
            bytes32 inboxAcc
        ) = testSuccessCreateSecondAssertion();
        assertEq(userRollup.latestConfirmed() != prevHash, true);
        vm.prank(anyTrustFastConfirmer);
        userRollup.fastConfirmAssertion(assertionHash, prevHash, afterState, inboxAcc);
        assertEq(userRollup.latestConfirmed(), assertionHash);
    }

    function testRevertFastConfirmNotPending() public {
        (bytes32 assertionHash, AssertionState memory assertionState,,) =
            testSuccessConfirmUnchallengedAssertions();
        bytes32 inboxAcc =
            userRollup.bridge().sequencerInboxAccs(assertionState.globalState.u64Vals[0] - 1);
        vm.expectRevert("NOT_PENDING");
        vm.prank(anyTrustFastConfirmer);
        userRollup.fastConfirmAssertion(
            assertionHash, postGenesisAssertionHash, assertionState, inboxAcc
        );
    }

    function testRevertFastConfirmNotConfirmer() public {
        (
            bytes32 assertionHash,
            AssertionState memory assertionState,,,
            bytes32 parentAssertionHash
        ) = testSuccessCreateAssertion();
        bytes32 inboxAcc =
            userRollup.bridge().sequencerInboxAccs(assertionState.globalState.u64Vals[0] - 1);
        vm.expectRevert("NOT_FAST_CONFIRMER");
        userRollup.fastConfirmAssertion(
            assertionHash, parentAssertionHash, assertionState, inboxAcc
        );
    }

    function _testFastConfirmNewAssertion(
        address by,
        string memory err,
        bool isCreated
    ) internal returns (AssertionInputs memory, bytes32) {
        uint256 initialInboxCount = userRollup.bridge().sequencerMessageCount();
        _createNewBatch();

        // Assertion created on top of post-genesis assertion
        AssertionState memory beforeState = postGenesisAssertionState;
        AssertionState memory afterState;
        afterState.machineStatus = MachineStatus.FINISHED;
        afterState.globalState.bytes32Vals[0] = FIRST_ASSERTION_BLOCKHASH; // blockhash
        afterState.globalState.bytes32Vals[1] = FIRST_ASSERTION_SENDROOT; // sendroot
        afterState.globalState.u64Vals[0] = uint64(initialInboxCount); // inbox count
        afterState.globalState.u64Vals[1] = 0; // pos in msg

        bytes32 expectedAssertionHash = RollupLib.assertionHash({
            parentAssertionHash: postGenesisAssertionHash,
            afterState: afterState,
            inboxAcc: userRollup.bridge().sequencerInboxAccs(afterState.globalState.u64Vals[0] - 1)
        });

        AssertionInputs memory assertion = AssertionInputs({
            beforeStateData: BeforeStateData({
                sequencerBatchAcc: bytes32(0),
                prevPrevAssertionHash: genesisAssertionHash,
                configData: postGenesisConfigData
            }),
            beforeState: beforeState,
            afterState: afterState
        });

        if (isCreated) {
            vm.prank(validator1);
            userRollup.stakeOnNewAssertion({
                assertion: assertion, expectedAssertionHash: expectedAssertionHash
            });
        }

        if (bytes(err).length > 0) {
            vm.expectRevert(bytes(err));
        }
        vm.prank(by);
        userRollup.fastConfirmNewAssertion({
            assertion: assertion, expectedAssertionHash: expectedAssertionHash
        });
        if (bytes(err).length == 0) {
            assertEq(userRollup.latestConfirmed(), expectedAssertionHash);
        }
        return (assertion, expectedAssertionHash);
    }

    function testSuccessFastConfirmNewAssertion() public {
        _testFastConfirmNewAssertion(anyTrustFastConfirmer, "", false);
    }

    function testRevertFastConfirmNewAssertionNotConfirmer() public {
        _testFastConfirmNewAssertion(validator1, "NOT_FAST_CONFIRMER", false);
    }

    function testSuccessFastConfirmNewAssertionPending() public {
        _testFastConfirmNewAssertion(anyTrustFastConfirmer, "", true);
    }

    function testRevertFastConfirmNewAssertionConfirmed() public {
        (AssertionInputs memory assertion, bytes32 expectedAssertionHash) =
            _testFastConfirmNewAssertion(anyTrustFastConfirmer, "", true);
        vm.expectRevert("NOT_PENDING");
        vm.prank(anyTrustFastConfirmer);
        userRollup.fastConfirmNewAssertion({
            assertion: assertion, expectedAssertionHash: expectedAssertionHash
        });
    }

    bytes32 constant _IMPLEMENTATION_PRIMARY_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 constant _IMPLEMENTATION_SECONDARY_SLOT =
        0x2b1dbce74324248c222f0ec2d5ed7bd323cfc425b336f0253c5ccfda7265546d;

    // should only allow admin to upgrade primary logic
    function testRevertUpgradeNotAdmin() public {
        RollupAdminLogic newAdminLogicImpl = new RollupAdminLogic();
        vm.expectRevert();
        adminRollup.upgradeTo(address(newAdminLogicImpl));
    }

    function testRevertUpgradeNotUUPS() public {
        vm.prank(upgradeExecutorAddr);
        vm.expectRevert();
        adminRollup.upgradeTo(address(rollup));
    }

    function testRevertUpgradePrimaryAsSecondary() public {
        RollupAdminLogic newAdminLogicImpl = new RollupAdminLogic();
        vm.prank(upgradeExecutorAddr);
        vm.expectRevert("ERC1967Upgrade: unsupported secondary proxiableUUID");
        adminRollup.upgradeSecondaryTo(address(newAdminLogicImpl));
    }

    function testRevertUpgradeSecondaryAsPrimary() public {
        RollupUserLogic newUserLogicImpl = new RollupUserLogic();
        vm.prank(upgradeExecutorAddr);
        vm.expectRevert("ERC1967Upgrade: unsupported proxiableUUID");
        adminRollup.upgradeTo(address(newUserLogicImpl));
    }

    function testSuccessUpgradePrimary() public {
        address ori_secondary_impl =
            address(uint160(uint256(vm.load(address(userRollup), _IMPLEMENTATION_SECONDARY_SLOT))));

        RollupAdminLogic newAdminLogicImpl = new RollupAdminLogic();
        vm.prank(upgradeExecutorAddr);
        adminRollup.upgradeTo(address(newAdminLogicImpl));

        address new_primary_impl =
            address(uint160(uint256(vm.load(address(userRollup), _IMPLEMENTATION_PRIMARY_SLOT))));
        address new_secondary_impl =
            address(uint160(uint256(vm.load(address(userRollup), _IMPLEMENTATION_SECONDARY_SLOT))));

        assertEq(address(newAdminLogicImpl), new_primary_impl);
        assertEq(ori_secondary_impl, new_secondary_impl);
    }

    function testSuccessUpgradePrimaryAndCall() public {
        address ori_secondary_impl =
            address(uint160(uint256(vm.load(address(userRollup), _IMPLEMENTATION_SECONDARY_SLOT))));

        RollupAdminLogic newAdminLogicImpl = new RollupAdminLogic();
        vm.prank(upgradeExecutorAddr);
        adminRollup.upgradeToAndCall(
            address(newAdminLogicImpl), abi.encodeCall(adminRollup.pause, ())
        );
        assertEq(adminRollup.paused(), true);

        address new_primary_impl =
            address(uint160(uint256(vm.load(address(userRollup), _IMPLEMENTATION_PRIMARY_SLOT))));
        address new_secondary_impl =
            address(uint160(uint256(vm.load(address(userRollup), _IMPLEMENTATION_SECONDARY_SLOT))));

        assertEq(address(newAdminLogicImpl), new_primary_impl);
        assertEq(ori_secondary_impl, new_secondary_impl);
    }

    function testSuccessUpgradeSecondary() public {
        address ori_primary_impl =
            address(uint160(uint256(vm.load(address(userRollup), _IMPLEMENTATION_PRIMARY_SLOT))));

        RollupUserLogic newUserLogicImpl = new RollupUserLogic();
        vm.prank(upgradeExecutorAddr);
        adminRollup.upgradeSecondaryTo(address(newUserLogicImpl));

        address new_primary_impl =
            address(uint160(uint256(vm.load(address(userRollup), _IMPLEMENTATION_PRIMARY_SLOT))));
        address new_secondary_impl =
            address(uint160(uint256(vm.load(address(userRollup), _IMPLEMENTATION_SECONDARY_SLOT))));

        assertEq(ori_primary_impl, new_primary_impl);
        assertEq(address(newUserLogicImpl), new_secondary_impl);
    }

    function testRevertInitAdminLogicDirectly() public {
        RollupAdminLogic newAdminLogicImpl = new RollupAdminLogic();
        Config memory c;
        ContractDependencies memory cd;
        vm.expectRevert("Function must be called through delegatecall");
        newAdminLogicImpl.initialize(c, cd);
    }

    function testRevertInitUserLogicDirectly() public {
        RollupUserLogic newUserLogicImpl = new RollupUserLogic();
        vm.expectRevert("Function must be called through delegatecall");
        newUserLogicImpl.initialize(address(token));
    }

    function testRevertInitTwice() public {
        Config memory c;
        ContractDependencies memory cd;
        vm.prank(upgradeExecutorAddr);
        vm.expectRevert("Initializable: contract is already initialized");
        adminRollup.initialize(c, cd);
    }

    function testRevertChainIDFork() public {
        ISequencerInbox sequencerInbox = userRollup.sequencerInbox();
        vm.expectRevert(NotForked.selector);
        sequencerInbox.removeDelayAfterFork();
    }

    function testRevertNotBatchPoster() public {
        ISequencerInbox sequencerInbox = userRollup.sequencerInbox();
        vm.expectRevert(NotBatchPoster.selector);
        sequencerInbox.addSequencerL2Batch(0, "0x", 0, IGasRefunder(address(0)), 0, 0);
    }

    function testSuccessSetChallengeManager() public {
        vm.prank(upgradeExecutorAddr);
        adminRollup.setChallengeManager(address(0xdeadbeef));
        assertEq(address(userRollup.challengeManager()), address(0xdeadbeef));
    }

    function testRevertSetChallengeManager() public {
        vm.expectRevert();
        adminRollup.setChallengeManager(address(0xdeadbeef));
    }

    function testAssertionStateHash() public {
        AssertionState memory astate = AssertionState(
            GlobalState(
                [rand.hash(), rand.hash()],
                [uint64(uint256(rand.hash())), uint64(uint256(rand.hash()))]
            ),
            MachineStatus.FINISHED,
            bytes32(0)
        );
        bytes32 expectedHash = keccak256(abi.encode(astate));
        assertEq(astate.hash(), expectedHash, "Unexpected hash");
    }

    function testAssertionHash() public {
        bytes32 parentHash = rand.hash();
        AssertionState memory astate = AssertionState(
            GlobalState(
                [rand.hash(), rand.hash()],
                [uint64(uint256(rand.hash())), uint64(uint256(rand.hash()))]
            ),
            MachineStatus.FINISHED,
            bytes32(0)
        );
        bytes32 inboxAcc = rand.hash();
        bytes32 expectedHash = keccak256(abi.encodePacked(parentHash, astate.hash(), inboxAcc));
        assertEq(
            RollupLib.assertionHash(parentHash, astate, inboxAcc), expectedHash, "Unexpected hash"
        );
    }

    function testConfigHash() public {
        bytes32 _wasmModuleRoot = rand.hash();
        uint256 _requiredStake = uint256(rand.hash());
        address _challengeManager = rand.addr();
        uint64 _confirmPeriodBlocks = uint64(uint256(rand.hash()));
        uint64 _nextInboxPosition = uint64(uint256(rand.hash()));
        bytes32 _nextParentChainBlockHash = rand.hash();

        assertEq(
            RollupLib.configHash(
                _wasmModuleRoot,
                _requiredStake,
                _challengeManager,
                _confirmPeriodBlocks,
                _nextInboxPosition,
                bytes32(0)
            ),
            keccak256(
                abi.encodePacked(
                    _wasmModuleRoot,
                    _requiredStake,
                    _challengeManager,
                    _confirmPeriodBlocks,
                    _nextInboxPosition
                )
            ),
            "Unexpected hash with zero nextParentChainBlockHash"
        );
        assertEq(
            RollupLib.configHash(
                _wasmModuleRoot,
                _requiredStake,
                _challengeManager,
                _confirmPeriodBlocks,
                _nextInboxPosition,
                _nextParentChainBlockHash
            ),
            keccak256(
                abi.encodePacked(
                    _wasmModuleRoot,
                    _requiredStake,
                    _challengeManager,
                    _confirmPeriodBlocks,
                    _nextInboxPosition,
                    _nextParentChainBlockHash
                )
            ),
            "Unexpected hash with non-zero nextParentChainBlockHash"
        );
    }

    function testIncreaseBaseStake() public {
        assertEq(adminRollup.baseStake(), BASE_STAKE, "Invalid before base stake");

        vm.expectRevert();
        adminRollup.increaseBaseStake(BASE_STAKE + 1);

        vm.expectRevert("BASE_STAKE_NOT_INCREASED");
        vm.prank(upgradeExecutorAddr);
        adminRollup.increaseBaseStake(BASE_STAKE - 1);

        vm.expectRevert("BASE_STAKE_NOT_INCREASED");
        vm.prank(upgradeExecutorAddr);
        adminRollup.increaseBaseStake(BASE_STAKE);

        vm.prank(upgradeExecutorAddr);
        adminRollup.increaseBaseStake(BASE_STAKE + 1);
        assertEq(adminRollup.baseStake(), BASE_STAKE + 1, "Invalid after increase base stake");
    }

    // This test is run after post-genesis assertion is created
    function testDecreaseBaseStake() public {
        assertEq(adminRollup.baseStake(), BASE_STAKE, "Invalid before base stake");

        vm.expectRevert();
        adminRollup.decreaseBaseStake(
            BASE_STAKE - 1,
            postGenesisConfigData.nextInboxPosition,
            postGenesisConfigData.nextParentChainBlockHash
        );

        vm.expectRevert("BASE_STAKE_NOT_DECREASED");
        vm.prank(upgradeExecutorAddr);
        adminRollup.decreaseBaseStake(
            BASE_STAKE + 1,
            postGenesisConfigData.nextInboxPosition,
            postGenesisConfigData.nextParentChainBlockHash
        );

        vm.expectRevert("BASE_STAKE_NOT_DECREASED");
        vm.prank(upgradeExecutorAddr);
        adminRollup.decreaseBaseStake(
            BASE_STAKE,
            postGenesisConfigData.nextInboxPosition,
            postGenesisConfigData.nextParentChainBlockHash
        );

        vm.startPrank(upgradeExecutorAddr);
        adminRollup.setValidatorWhitelistDisabled(true);
        vm.expectRevert("DECREASE_ONLY_FOR_PERMISSIONED_CHAINS");
        adminRollup.decreaseBaseStake(
            BASE_STAKE - 1,
            postGenesisConfigData.nextInboxPosition,
            postGenesisConfigData.nextParentChainBlockHash
        );
        adminRollup.setValidatorWhitelistDisabled(false);
        vm.stopPrank();

        vm.expectRevert("PENDING_ASSERTION_NOT_UPDATED");
        vm.prank(upgradeExecutorAddr);
        adminRollup.decreaseBaseStake(
            BASE_STAKE - 1,
            postGenesisConfigData.nextInboxPosition,
            postGenesisConfigData.nextParentChainBlockHash
        );

        (
            bytes32 assertionHash,
            AssertionState memory assertionState,
            uint64 nextInboxPosition,
            bytes32 nextParentChainBlockHash,
            bytes32 parentAssertionHash
        ) = testSuccessCreateAssertion();
        vm.prank(upgradeExecutorAddr);
        vm.expectRevert("EXPIRED_CONFIG_HASH");
        adminRollup.decreaseBaseStake(
            BASE_STAKE - 1,
            postGenesisConfigData.nextInboxPosition,
            postGenesisConfigData.nextParentChainBlockHash
        );

        vm.prank(upgradeExecutorAddr);
        adminRollup.decreaseBaseStake(BASE_STAKE - 1, nextInboxPosition, nextParentChainBlockHash);

        _createNewBatch();
        AssertionState memory afterState;
        afterState.machineStatus = MachineStatus.FINISHED;
        afterState.globalState.bytes32Vals[0] = FIRST_ASSERTION_BLOCKHASH; // blockhash
        afterState.globalState.bytes32Vals[1] = FIRST_ASSERTION_SENDROOT; // sendroot
        afterState.globalState.u64Vals[0] = nextInboxPosition; // inbox count
        afterState.globalState.u64Vals[1] = 0; // pos in msg

        bytes32 expectedAssertionHash = RollupLib.assertionHash({
            parentAssertionHash: assertionHash,
            afterState: afterState,
            inboxAcc: userRollup.bridge().sequencerInboxAccs(afterState.globalState.u64Vals[0] - 1)
        });

        bytes32 beforeInboxAcc =
            userRollup.bridge().sequencerInboxAccs(assertionState.globalState.u64Vals[0] - 1);

        // test that we can create a new assertion after stake reduction
        vm.roll(block.number + minimumAssertionPeriod);
        vm.prank(validator2);
        userRollup.newStakeOnNewAssertion({
            tokenAmount: BASE_STAKE - 1,
            assertion: AssertionInputs({
                beforeStateData: BeforeStateData({
                    sequencerBatchAcc: beforeInboxAcc,
                    prevPrevAssertionHash: parentAssertionHash,
                    configData: ConfigData({
                        wasmModuleRoot: WASM_MODULE_ROOT,
                        requiredStake: BASE_STAKE - 1,
                        challengeManager: address(challengeManager),
                        confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
                        nextInboxPosition: nextInboxPosition,
                        nextParentChainBlockHash: nextParentChainBlockHash
                    })
                }),
                beforeState: assertionState,
                afterState: afterState
            }),
            expectedAssertionHash: expectedAssertionHash,
            _withdrawalAddress: validator1Withdrawal
        });

        createStakeTooLowAssertion();
    }

    function createStakeTooLowAssertion() public {
        // trying to create an assertion with the post-genesis as parent will fail with stake too low
        AssertionState memory afterState;
        afterState.machineStatus = MachineStatus.FINISHED;
        afterState.globalState.bytes32Vals[0] =
            keccak256(abi.encodePacked(FIRST_ASSERTION_BLOCKHASH)); // blockhash
        afterState.globalState.bytes32Vals[1] = FIRST_ASSERTION_SENDROOT; // sendroot
        afterState.globalState.u64Vals[0] = postGenesisConfigData.nextInboxPosition; // inbox count
        afterState.globalState.u64Vals[1] = 0; // pos in msg

        bytes32 expectedAssertionHash = RollupLib.assertionHash({
            parentAssertionHash: postGenesisAssertionHash,
            afterState: afterState,
            inboxAcc: userRollup.bridge().sequencerInboxAccs(afterState.globalState.u64Vals[0] - 1)
        });

        vm.expectRevert("STAKE_TOO_LOW");
        vm.prank(validator3);
        userRollup.newStakeOnNewAssertion({
            tokenAmount: BASE_STAKE,
            assertion: AssertionInputs({
                beforeStateData: BeforeStateData({
                    sequencerBatchAcc: bytes32(0),
                    prevPrevAssertionHash: genesisAssertionHash,
                    configData: postGenesisConfigData
                }),
                beforeState: postGenesisAssertionState,
                afterState: afterState
            }),
            expectedAssertionHash: expectedAssertionHash,
            _withdrawalAddress: validator3Withdrawal
        });
    }

    function testCannotDecreaseBaseStakeWithForkedAssertionTree() public {
        assertEq(adminRollup.baseStake(), BASE_STAKE, "Invalid before base stake");

        SuccessCreateChallengeData memory data = testSuccessCreateChallenge();

        userRollup.getAssertion(data.assertionHash);
        vm.expectRevert("TOO_MANY_PENDING_STAKERS");
        vm.prank(upgradeExecutorAddr);
        adminRollup.decreaseBaseStake(
            BASE_STAKE - 1, uint64(data.newInboxCount), data.nextParentChainBlockHash
        );
    }
}
