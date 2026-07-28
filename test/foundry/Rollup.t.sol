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
import "./../challengeV2/Utils.sol";

import "../../src/libraries/Error.sol";

import "../../src/mocks/TestWETH9.sol";
import "../../src/mocks/UpgradeExecutorMock.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts-upgradeable/utils/Create2Upgradeable.sol";

contract RollupTest is Test {
    using GlobalStateLib for GlobalState;
    using AssertionStateLib for AssertionState;
    using MELStateLib for MELState;

    struct SuccessCreateChallengeData {
        AssertionState beforeState;
        bytes32 beforeStateParentChainBlockHash;
        AssertionState afterState1;
        AssertionState afterState2;
        MELState afterMELState;
        bytes32 afterStateParentChainBlockHash;
        bytes32 edge1Id;
        bytes32 assertionHash1;
        bytes32 assertionHash2;
        bytes32 nextParentChainBlockHash;
    }

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

    uint64 constant INITIAL_MSG_COUNT = 1;
    bytes32 constant FIRST_ASSERTION_BLOCKHASH = keccak256("FIRST_ASSERTION_BLOCKHASH");
    bytes32 constant FIRST_ASSERTION_SENDROOT = keccak256("FIRST_ASSERTION_SENDROOT");
    bytes32 constant FIRST_ASSERTION_PARENT_CHAIN_BLOCKHASH =
        keccak256("FIRST_ASSERTION_PARENT_CHAIN_BLOCKHASH");

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

    GlobalState emptyGlobalState;
    AssertionState emptyAssertionState =
        AssertionState(emptyGlobalState, MachineStatus.FINISHED, bytes32(0));
    bytes32 genesisHash =
        RollupLib.assertionHash({parentAssertionHash: bytes32(0), afterState: emptyAssertionState});
    AssertionState firstState;
    MELState firstMELState;
    uint64 firstAssertionParentChainBlockNumber;
    bytes32 firstAssertionParentChainBlockHash;

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

    IReader4844 dummyReader4844 = IReader4844(address(137));
    BridgeCreator.BridgeTemplates ethBasedTemplates = BridgeCreator.BridgeTemplates({
        bridge: new Bridge(),
        sequencerInbox: new SequencerInbox(MAX_DATA_SIZE, dummyReader4844, false, false),
        delayBufferableSequencerInbox: new SequencerInbox(MAX_DATA_SIZE, dummyReader4844, false, true),
        inbox: new Inbox(MAX_DATA_SIZE),
        rollupEventInbox: new RollupEventInbox(),
        outbox: new Outbox()
    });
    BridgeCreator.BridgeTemplates erc20BasedTemplates = BridgeCreator.BridgeTemplates({
        bridge: new ERC20Bridge(),
        sequencerInbox: new SequencerInbox(MAX_DATA_SIZE, dummyReader4844, true, false),
        delayBufferableSequencerInbox: new SequencerInbox(MAX_DATA_SIZE, dummyReader4844, true, true),
        inbox: new ERC20Inbox(MAX_DATA_SIZE),
        rollupEventInbox: new ERC20RollupEventInbox(),
        outbox: new ERC20Outbox()
    });

    // need to have these in storage due to stack limit
    bytes32[] randomStates1;
    bytes32[] randomStates2;

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

        // Genesis assertion state, confirmed on rollup creation
        AssertionState memory genesisAssertionState = emptyAssertionState;
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

        // store the parent chain block information to be used in the next assertion
        // (must be consistent with the the implementation of `initialize` in RollupAdminLogic)
        firstAssertionParentChainBlockNumber = uint64(block.number - 1);
        firstAssertionParentChainBlockHash = blockhash(block.number - 1);

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

        // First assertion to create after the genesis assertion
        (firstState, firstMELState) = _mockAssertionState();

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

        vm.roll(block.number + 75);
    }

    function _mockAssertionState() internal view returns (AssertionState memory, MELState memory) {
        MELState memory melState;
        melState.version = 0;
        melState.parentChainId = uint64(block.chainid);
        melState.parentChainBlockNumber = firstAssertionParentChainBlockNumber;
        melState.batchPostingTargetAddress = address(0);
        melState.delayedMessagePostingTargetAddress = address(0);
        melState.parentChainBlockHash = firstAssertionParentChainBlockHash;
        melState.parentChainPreviousBlockHash = bytes32(0);
        melState.batchCount = 1;
        melState.msgCount = INITIAL_MSG_COUNT;
        melState.localMsgAccumulator = bytes32(0);
        melState.delayedMessagesRead = INITIAL_MSG_COUNT;
        melState.delayedMessagesSeen = INITIAL_MSG_COUNT;
        melState.delayedMessageInboxAcc = bytes32(0);
        melState.delayedMessageOutboxAcc = bytes32(0);

        AssertionState memory assertionState;
        assertionState.machineStatus = MachineStatus.FINISHED;
        assertionState.globalState.bytes32Vals[0] = FIRST_ASSERTION_BLOCKHASH; // Blockhash
        assertionState.globalState.bytes32Vals[1] = FIRST_ASSERTION_SENDROOT; // Sendroot
        assertionState.globalState.bytes32Vals[2] = melState.hash(); // MELState hash
        assertionState.globalState.bytes32Vals[3] = bytes32(0); // MEL NextMsgHash
        assertionState.globalState.u64Vals[0] = 0; // InboxPosition (deprecated)
        assertionState.globalState.u64Vals[1] = 0; // PositionInMessage (deprecated)
        assertionState.globalState.u64Vals[2] = INITIAL_MSG_COUNT; // MsgCount
        assertionState.globalState.u64Vals[3] = INITIAL_MSG_COUNT; // ExecutedMsgCount

        return (assertionState, melState);
    }

    function _fillStatesInBetween(
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

    function testGenesisAssertionConfirmed() external {
        bytes32 latestConfirmed = userRollup.latestConfirmed();
        assertEq(latestConfirmed, genesisHash);
        assertEq(userRollup.getAssertion(latestConfirmed).status == AssertionStatus.Confirmed, true);
    }

    function testSuccessPause() public {
        vm.prank(upgradeExecutorAddr);
        adminRollup.pause();
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

    /**
     * Creates a new assertion on top of the genesis assertion
     *
     * Should return:
     * - the expected assertion hash
     * - the assertion state
     * - the MEL state
     * - the target parent chain block hash to be used in the next assertion
     *
     * @dev To be used after `setUp()`
     * @dev Test used in multiple other tests
     */
    function testSuccessCreateAssertion()
        public
        returns (bytes32, AssertionState memory, MELState memory, bytes32)
    {
        AssertionState memory beforeState;
        beforeState.machineStatus = MachineStatus.FINISHED;
        AssertionState memory afterState = firstState;
        MELState memory afterMELState = firstMELState;

        bytes32 expectedAssertionHash =
            RollupLib.assertionHash({parentAssertionHash: genesisHash, afterState: afterState});

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
                beforeState: beforeState,
                afterState: afterState,
                afterMELState: afterMELState
            }),
            expectedAssertionHash: expectedAssertionHash,
            _withdrawalAddress: validator1Withdrawal
        });

        bytes32 nextParentChainBlockHash = blockhash(block.number - 1);

        return (expectedAssertionHash, afterState, afterMELState, nextParentChainBlockHash);
    }

    function testSuccessCreateAssertionUsingAddToDeposit() public {
        AssertionState memory beforeState;
        beforeState.machineStatus = MachineStatus.FINISHED;
        AssertionState memory afterState = firstState;
        MELState memory afterMELState = firstMELState;

        bytes32 expectedAssertionHash =
            RollupLib.assertionHash({parentAssertionHash: genesisHash, afterState: afterState});

        vm.prank(validator1);
        userRollup.newStake(0, validator1Withdrawal);

        address rando = address(98139098);
        token.transfer(rando, BASE_STAKE);

        vm.startPrank(rando);
        token.approve(address(userRollup), BASE_STAKE);
        userRollup.addToDeposit(validator1, validator1Withdrawal, BASE_STAKE);
        vm.stopPrank();

        vm.prank(validator1);
        userRollup.stakeOnNewAssertion({
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
                beforeState: beforeState,
                afterState: afterState,
                afterMELState: afterMELState
            }),
            expectedAssertionHash: expectedAssertionHash
        });
    }

    function testPartialDepositCanWithdraw() public {
        IRollupCore.Staker memory emptyStaker;

        vm.prank(validator1);
        userRollup.newStake(10, validator1Withdrawal);

        uint256 snapshot = vm.snapshot();

        vm.prank(validator1);
        userRollup.returnOldDeposit();

        vm.prank(validator1Withdrawal);
        userRollup.withdrawStakerFunds();

        assertEq(token.balanceOf(validator1Withdrawal), 10);
        assertEq(
            keccak256(abi.encode(userRollup.getStaker(validator1))),
            keccak256(abi.encode(emptyStaker))
        );

        vm.revertTo(snapshot);

        vm.startPrank(validator1Withdrawal);
        userRollup.returnOldDepositFor(validator1);
        userRollup.withdrawStakerFunds();
        vm.stopPrank();

        assertEq(token.balanceOf(validator1Withdrawal), 10);
        assertEq(
            keccak256(abi.encode(userRollup.getStaker(validator1))),
            keccak256(abi.encode(emptyStaker))
        );
    }

    function testPartialDepositCannotMakeAssertion() public {
        AssertionState memory beforeState;
        beforeState.machineStatus = MachineStatus.FINISHED;
        AssertionState memory afterState = firstState;
        MELState memory afterMELState = firstMELState;

        bytes32 expectedAssertionHash =
            RollupLib.assertionHash({parentAssertionHash: genesisHash, afterState: afterState});

        vm.prank(validator1);
        userRollup.newStake(BASE_STAKE - 1, validator1Withdrawal);

        vm.prank(validator1);
        vm.expectRevert("INSUFFICIENT_STAKE");
        userRollup.stakeOnNewAssertion({
            assertion: AssertionInputs({
                beforeStateData: BeforeStateData({
                    prevPrevAssertionHash: bytes32(0),
                    configData: ConfigData({
                        wasmModuleRoot: WASM_MODULE_ROOT,
                        requiredStake: BASE_STAKE,
                        challengeManager: address(challengeManager),
                        confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
                        nextParentChainBlockHash: blockhash(block.number - 1)
                    })
                }),
                beforeState: beforeState,
                afterState: afterState,
                afterMELState: afterMELState
            }),
            expectedAssertionHash: expectedAssertionHash
        });
    }

    function testSuccessGetStaker() public {
        assertEq(userRollup.stakerCount(), 0);
        testSuccessCreateAssertion();
        assertEq(userRollup.stakerCount(), 1);
        assertEq(userRollup.getStakerAddress(userRollup.getStaker(validator1).index), validator1);
    }

    function testSuccessCreateErroredAssertions() public {
        AssertionState memory beforeState;
        beforeState.machineStatus = MachineStatus.FINISHED;
        AssertionState memory afterState = firstState;
        afterState.machineStatus = MachineStatus.ERRORED;
        MELState memory afterMELState = firstMELState;

        bytes32 expectedAssertionHash =
            RollupLib.assertionHash({parentAssertionHash: genesisHash, afterState: afterState});

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
                beforeState: beforeState,
                afterState: afterState,
                afterMELState: afterMELState
            }),
            expectedAssertionHash: expectedAssertionHash,
            _withdrawalAddress: validator1Withdrawal
        });
    }

    function testRevertIdenticalAssertions() public {
        AssertionState memory beforeState;
        beforeState.machineStatus = MachineStatus.FINISHED;
        AssertionState memory afterState = firstState;
        MELState memory afterMELState = firstMELState;

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
                beforeState: beforeState,
                afterState: afterState,
                afterMELState: afterMELState
            }),
            expectedAssertionHash: bytes32(0),
            _withdrawalAddress: validator1Withdrawal
        });

        vm.prank(validator2);
        vm.expectRevert("ASSERTION_SEEN");
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
                beforeState: beforeState,
                afterState: afterState,
                afterMELState: afterMELState
            }),
            expectedAssertionHash: bytes32(0),
            _withdrawalAddress: validator2Withdrawal
        });
    }

    function testRevertInvalidPrev() public {
        (bytes32 assertionHash, AssertionState memory beforeState, MELState memory beforeMELState,)
        = testSuccessCreateAssertion();

        // Add 1 more message
        MELState memory afterMELState = beforeMELState;
        afterMELState.msgCount += 1;

        AssertionState memory afterState;
        afterState.machineStatus = MachineStatus.FINISHED;
        afterState.globalState.u64Vals[2] += 1; // increase MsgCount
        afterState.globalState.u64Vals[3] += 1; // increase ExecutedMsgCount
        afterState.globalState.bytes32Vals[2] = afterMELState.hash(); // MEL State hash
        bytes32 expectedAssertionHash =
            RollupLib.assertionHash({parentAssertionHash: assertionHash, afterState: afterState});

        // set the wrong blockhash on beforeState
        beforeState.globalState.bytes32Vals[0] = FIRST_ASSERTION_SENDROOT;

        vm.roll(block.number + 75);
        vm.prank(validator1);
        vm.expectRevert("ASSERTION_NOT_EXIST");
        userRollup.stakeOnNewAssertion({
            assertion: AssertionInputs({
                beforeStateData: BeforeStateData({
                    prevPrevAssertionHash: genesisHash,
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
                afterMELState: afterMELState
            }),
            expectedAssertionHash: expectedAssertionHash
        });
    }

    /**
     * Creates a competing assertion on top of the genesis assertion, with a different state than the first assertion
     *
     * Should return:
     * - the previous assertion state (same for both assertions)
     * - the parent chain block hash last processed in the beforeState assertion (bytes32(0))
     * - the first assertion state
     * - the second assertion state
     * - the MEL state
     * - the parent chain block hash last processed in the afterState assertion (firstAssertionParentChainBlockHash)
     * - the edge id of the created challenge
     * - the expected assertion hash for the first assertion
     * - the expected assertion hash for the second assertion
     * - the target parent chain block hash to be used in the next assertion
     *
     * @dev To be used after `setUp()`
     * @dev Test used in multiple other tests
     */
    function testSuccessCreateSecondChild()
        public
        returns (SuccessCreateChallengeData memory data)
    {
        data.beforeState.machineStatus = MachineStatus.FINISHED;
        data.afterState1 = firstState;
        data.afterMELState = firstMELState;
        data.beforeStateParentChainBlockHash = bytes32(0);
        data.afterStateParentChainBlockHash = firstAssertionParentChainBlockHash;

        {
            IOneStepProofEntry osp = userRollup.challengeManager().oneStepProofEntry();
            bytes32 h0 = osp.getMachineHash(data.beforeState.toExecutionState());
            bytes32 h1 = osp.getMachineHash(data.afterState1.toExecutionState());
            randomStates1 = _fillStatesInBetween(h0, h1, LAYERZERO_BLOCKEDGE_HEIGHT + 1);
            data.afterState1.endHistoryRoot = MerkleTreeAccumulatorLib.root(
                ProofUtils.expansionFromLeaves(randomStates1, 0, LAYERZERO_BLOCKEDGE_HEIGHT + 1)
            );
        }

        data.assertionHash1 = RollupLib.assertionHash({
            parentAssertionHash: genesisHash,
            afterState: data.afterState1
        });

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
                beforeState: data.beforeState,
                afterState: data.afterState1,
                afterMELState: data.afterMELState
            }),
            expectedAssertionHash: data.assertionHash1,
            _withdrawalAddress: validator1Withdrawal
        });

        data.afterState2 = firstState;
        data.afterState2.globalState.bytes32Vals[0] =
            keccak256(abi.encodePacked(FIRST_ASSERTION_BLOCKHASH)); // blockhash
        data.afterState2.globalState.bytes32Vals[1] =
            keccak256(abi.encodePacked(FIRST_ASSERTION_SENDROOT)); // sendroot

        {
            IOneStepProofEntry osp = userRollup.challengeManager().oneStepProofEntry();
            bytes32 h0 = osp.getMachineHash(data.beforeState.toExecutionState());
            bytes32 h1 = osp.getMachineHash(data.afterState2.toExecutionState());
            randomStates2 = _fillStatesInBetween(h0, h1, LAYERZERO_BLOCKEDGE_HEIGHT + 1);
            data.afterState2.endHistoryRoot = MerkleTreeAccumulatorLib.root(
                ProofUtils.expansionFromLeaves(randomStates2, 0, LAYERZERO_BLOCKEDGE_HEIGHT + 1)
            );
        }

        data.assertionHash2 = RollupLib.assertionHash({
            parentAssertionHash: genesisHash,
            afterState: data.afterState2
        });
        vm.prank(validator2);
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
                beforeState: data.beforeState,
                afterState: data.afterState2,
                afterMELState: data.afterMELState
            }),
            expectedAssertionHash: data.assertionHash2,
            _withdrawalAddress: validator2Withdrawal
        });

        assertEq(userRollup.getAssertion(genesisHash).secondChildBlock, block.number);

        data.nextParentChainBlockHash = blockhash(block.number - 1);
    }

    function testSuccessCreateSecondChildDifferentRoot() public {
        SuccessCreateChallengeData memory data = testSuccessCreateSecondChild();
        AssertionState memory afterState3 = data.afterState2;
        afterState3.endHistoryRoot = keccak256(abi.encode(afterState3.endHistoryRoot));

        bytes32 expectedAssertionHash3 =
            RollupLib.assertionHash({parentAssertionHash: genesisHash, afterState: afterState3});
        vm.prank(validator3);
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
                beforeState: data.beforeState,
                afterState: afterState3,
                afterMELState: data.afterMELState
            }),
            expectedAssertionHash: expectedAssertionHash3,
            _withdrawalAddress: validator3Withdrawal
        });
    }

    function testConfirmAssertionWhenPaused() public {
        (bytes32 assertionHash, AssertionState memory afterState,,) = testSuccessCreateAssertion();
        vm.roll(userRollup.getAssertion(genesisHash).firstChildBlock + CONFIRM_PERIOD_BLOCKS + 1);
        vm.prank(upgradeExecutorAddr);
        adminRollup.pause();
        vm.prank(validator1);
        vm.expectRevert("Pausable: paused");
        userRollup.confirmAssertion(
            assertionHash,
            genesisHash,
            afterState,
            bytes32(0),
            ConfigData({
                wasmModuleRoot: WASM_MODULE_ROOT,
                requiredStake: BASE_STAKE,
                challengeManager: address(challengeManager),
                confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
                nextParentChainBlockHash: blockhash(block.number - 1)
            })
        );
    }

    function testRevertConfirmWrongInput() public {
        (bytes32 assertionHash,,,) = testSuccessCreateAssertion();
        vm.roll(userRollup.getAssertion(genesisHash).firstChildBlock + CONFIRM_PERIOD_BLOCKS + 1);
        vm.prank(validator1);
        vm.expectRevert("CONFIRM_DATA");
        userRollup.confirmAssertion(
            assertionHash,
            genesisHash,
            emptyAssertionState, // Wrong assertion state
            bytes32(0),
            ConfigData({
                wasmModuleRoot: WASM_MODULE_ROOT,
                requiredStake: BASE_STAKE,
                challengeManager: address(challengeManager),
                confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
                nextParentChainBlockHash: firstAssertionParentChainBlockHash
            })
        );
    }

    /**
     * Confirms a new assertion created with `testSuccessCreateAssertion` on top of the genesis assertion
     *
     * Should return:
     * - the assertion hash
     * - the assertion state
     * - the MEL state
     * - the target parent chain block hash to be used in the next assertion
     *
     * @dev To be used after `testSuccessCreateAssertion()`
     * @dev Test used in multiple other tests
     */
    function testSuccessConfirmUnchallengedAssertions()
        public
        returns (bytes32, AssertionState memory, MELState memory, bytes32)
    {
        (
            bytes32 assertionHash,
            AssertionState memory assertionState,
            MELState memory melState,
            bytes32 nextParentChainBlockHash
        ) = testSuccessCreateAssertion();
        vm.roll(userRollup.getAssertion(genesisHash).firstChildBlock + CONFIRM_PERIOD_BLOCKS + 1);
        vm.prank(validator1);
        userRollup.confirmAssertion(
            assertionHash,
            genesisHash,
            firstState,
            bytes32(0),
            ConfigData({
                wasmModuleRoot: WASM_MODULE_ROOT,
                requiredStake: BASE_STAKE,
                challengeManager: address(challengeManager),
                confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
                nextParentChainBlockHash: firstAssertionParentChainBlockHash
            })
        );
        return (assertionHash, assertionState, melState, nextParentChainBlockHash);
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
        SuccessCreateChallengeData memory data = testSuccessCreateSecondChild();
        vm.roll(userRollup.getAssertion(genesisHash).firstChildBlock + CONFIRM_PERIOD_BLOCKS + 1);
        vm.prank(validator1);

        vm.expectRevert(abi.encodeWithSelector(EdgeNotExists.selector, bytes32(0)));
        userRollup.confirmAssertion(
            data.assertionHash1,
            genesisHash,
            firstState,
            bytes32(0),
            ConfigData({
                wasmModuleRoot: WASM_MODULE_ROOT,
                requiredStake: BASE_STAKE,
                challengeManager: address(challengeManager),
                confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
                nextParentChainBlockHash: firstAssertionParentChainBlockHash
            })
        );
    }

    /**
     * Creates a challenge between 2 assertions created with `testSuccessCreateAssertion` and `testSuccessCreateSecondChild` on top of the genesis assertion
     *
     * Should return:
     * - the previous assertion state (same for both assertions)
     * - the parent chain block hash last processed in the beforeState assertion (bytes32(0))
     * - the first assertion state
     * - the second assertion state
     * - the MEL state
     * - the parent chain block hash last processed in the afterState assertion (firstAssertionParentChainBlockHash)
     * - the edge id of the created challenge
     * - the expected assertion hash for the first assertion
     * - the expected assertion hash for the second assertion
     * - the target parent chain block hash to be used in the next assertion
     *
     * @dev To be used after `testSuccessCreateSecondChild()`
     * @dev Test used in multiple other tests
     */
    function testSuccessCreateChallenge() public returns (SuccessCreateChallengeData memory data) {
        data = testSuccessCreateSecondChild();

        // randomStates1 is filled in `testSuccessCreateSecondChild` (corresponds to the states of afterState1)
        bytes32 root = MerkleTreeAccumulatorLib.root(
            ProofUtils.expansionFromLeaves(randomStates1, 0, LAYERZERO_BLOCKEDGE_HEIGHT + 1)
        );

        data.edge1Id = challengeManager.createLayerZeroEdge(
            CreateEdgeArgs({
                level: 0,
                endHistoryRoot: root,
                endHeight: LAYERZERO_BLOCKEDGE_HEIGHT,
                claimId: data.assertionHash1,
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
                    AssertionStateData(data.beforeState, bytes32(0)),
                    AssertionStateData(data.afterState1, genesisHash)
                )
            })
        );
    }

    function testSuccessCreate2Edge() public returns (bytes32, bytes32) {
        SuccessCreateChallengeData memory data = testSuccessCreateChallenge();
        require(data.beforeStateParentChainBlockHash == bytes32(0), "A");
        require(data.afterStateParentChainBlockHash == firstAssertionParentChainBlockHash, "B");

        // randomStates2 is filled in `testSuccessCreateSecondChild` (corresponds to the states of afterState2)
        bytes32 root = MerkleTreeAccumulatorLib.root(
            ProofUtils.expansionFromLeaves(randomStates2, 0, LAYERZERO_BLOCKEDGE_HEIGHT + 1)
        );

        token.transfer(validator1, 1 ether);
        vm.startPrank(validator1);
        bytes32 edge2Id = challengeManager.createLayerZeroEdge(
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
                    AssertionStateData(data.beforeState, bytes32(0)),
                    AssertionStateData(data.afterState2, genesisHash)
                )
            })
        );
        vm.stopPrank();

        return (data.edge1Id, edge2Id);
    }

    /**
     * Confirms a challenged assertion by time. The challenge is created with `testSuccessCreateChallenge`
     *
     * Should return:
     * - the winning assertion hash
     *
     * @dev To be used after `testSuccessCreateChallenge()`
     * @dev Test used in multiple other tests
     */
    function testSuccessConfirmEdgeByTime() public returns (bytes32) {
        SuccessCreateChallengeData memory data = testSuccessCreateChallenge();

        vm.roll(userRollup.getAssertion(genesisHash).firstChildBlock + CONFIRM_PERIOD_BLOCKS + 1);
        vm.warp(block.timestamp + CONFIRM_PERIOD_BLOCKS * 15);
        userRollup.challengeManager().confirmEdgeByTime(
            data.edge1Id, AssertionStateData(data.afterState1, genesisHash)
        );
        vm.roll(block.number + userRollup.challengeGracePeriodBlocks());
        vm.prank(validator1);
        userRollup.confirmAssertion(
            data.assertionHash1,
            genesisHash,
            data.afterState1,
            data.edge1Id,
            ConfigData({
                wasmModuleRoot: WASM_MODULE_ROOT,
                requiredStake: BASE_STAKE,
                challengeManager: address(challengeManager),
                confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
                nextParentChainBlockHash: data.afterStateParentChainBlockHash
            })
        );
        return data.edge1Id;
    }

    function testRevertConfirmBeforeAfterPeriodBlocks() public returns (bytes32) {
        SuccessCreateChallengeData memory data = testSuccessCreateChallenge();

        vm.roll(userRollup.getAssertion(genesisHash).firstChildBlock + CONFIRM_PERIOD_BLOCKS + 1);
        vm.warp(block.timestamp + CONFIRM_PERIOD_BLOCKS * 15);
        userRollup.challengeManager().confirmEdgeByTime(
            data.edge1Id, AssertionStateData(data.afterState1, genesisHash)
        );
        vm.roll(block.number + userRollup.challengeGracePeriodBlocks() - 1);
        vm.prank(validator1);
        vm.expectRevert("CHALLENGE_GRACE_PERIOD_NOT_PASSED");
        userRollup.confirmAssertion(
            data.assertionHash1,
            genesisHash,
            data.afterState1,
            data.edge1Id,
            ConfigData({
                wasmModuleRoot: WASM_MODULE_ROOT,
                requiredStake: BASE_STAKE,
                challengeManager: address(challengeManager),
                confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
                nextParentChainBlockHash: data.afterStateParentChainBlockHash
            })
        );
        return data.edge1Id;
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

    /**
     * Creates a second assertion on top of the one created with `testSuccessCreateAssertion`
     *
     * Should return:
     * - the previous assertion hash
     * - the expected assertion hash
     * - the assertion state
     * - the MEL state
     * - the target parent chain block hash to be used in the next assertion
     *
     * @dev To be used after `testSuccessCreateAssertion()`
     * @dev Test used in multiple other tests
     */
    function testSuccessCreateSecondAssertion()
        public
        returns (bytes32, bytes32, AssertionState memory, MELState memory, bytes32)
    {
        (
            bytes32 beforeAssertionHash,
            AssertionState memory beforeState,
            MELState memory beforeMELState,
            bytes32 nextParentChainBlockHash
        ) = testSuccessCreateAssertion();

        MELState memory afterMELState = beforeMELState;
        // Add one message and update nextParentChainBlockHash
        // (the other values in MEL state are not relevant in the Rollup contracts)
        afterMELState.msgCount += 1;
        afterMELState.parentChainBlockHash = nextParentChainBlockHash;

        AssertionState memory afterState;
        afterState.machineStatus = MachineStatus.FINISHED;
        afterState.globalState.u64Vals[2] = beforeState.globalState.u64Vals[2] + 1; // increase MsgCount
        afterState.globalState.u64Vals[3] = beforeState.globalState.u64Vals[3] + 1; // increase ExecutedMsgCount
        afterState.globalState.bytes32Vals[2] = afterMELState.hash(); // update MEL State hash
        bytes32 expectedAssertionHash = RollupLib.assertionHash({
            parentAssertionHash: beforeAssertionHash,
            afterState: afterState
        });

        vm.roll(block.number + 75);
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
            expectedAssertionHash: expectedAssertionHash
        });

        bytes32 nextParentChainBlockHash2 = blockhash(block.number - 1);

        return (
            beforeAssertionHash,
            expectedAssertionHash,
            afterState,
            afterMELState,
            nextParentChainBlockHash2
        );
    }

    function testRevertCreateChildReducedStake() public {
        (
            bytes32 beforeAssertionHash,
            AssertionState memory beforeState,
            MELState memory beforeMELState,
            bytes32 nextParentChainBlockHash
        ) = testSuccessConfirmUnchallengedAssertions();

        vm.prank(validator1);
        userRollup.reduceDeposit(1);

        MELState memory afterMELState = beforeMELState;
        // Add one message and update nextParentChainBlockHash
        // (the other values in MEL state are not relevant in the Rollup contracts)
        afterMELState.msgCount += 1;
        afterMELState.parentChainBlockHash = nextParentChainBlockHash;

        AssertionState memory afterState;
        afterState.machineStatus = MachineStatus.FINISHED;
        afterState.globalState.u64Vals[2] = beforeState.globalState.u64Vals[2] + 1; // increase MsgCount
        afterState.globalState.u64Vals[3] = beforeState.globalState.u64Vals[3] + 1; // increase ExecutedMsgCount
        afterState.globalState.bytes32Vals[2] = afterMELState.hash(); // update MEL State hash
        bytes32 expectedAssertionHash = RollupLib.assertionHash({
            parentAssertionHash: beforeAssertionHash,
            afterState: afterState
        });

        vm.roll(block.number + 75);
        vm.prank(validator1);
        vm.expectRevert("INSUFFICIENT_STAKE");
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
            expectedAssertionHash: expectedAssertionHash
        });
    }

    function testSuccessFastConfirmNext() public {
        (bytes32 assertionHash, AssertionState memory afterState,,) = testSuccessCreateAssertion();
        assertEq(userRollup.latestConfirmed(), genesisHash);
        vm.prank(anyTrustFastConfirmer);
        userRollup.fastConfirmAssertion(assertionHash, genesisHash, afterState);
        assertEq(userRollup.latestConfirmed(), assertionHash);
    }

    function testSuccessFastConfirmSkipOne() public {
        (bytes32 beforeAssertionHash, bytes32 assertionHash, AssertionState memory afterState,,) =
            testSuccessCreateSecondAssertion();
        assertEq(userRollup.latestConfirmed() != beforeAssertionHash, true);
        vm.prank(anyTrustFastConfirmer);
        userRollup.fastConfirmAssertion(assertionHash, beforeAssertionHash, afterState);
        assertEq(userRollup.latestConfirmed(), assertionHash);
    }

    function testRevertFastConfirmNotPending() public {
        (bytes32 assertionHash, AssertionState memory afterState,,) =
            testSuccessConfirmUnchallengedAssertions();
        vm.expectRevert("NOT_PENDING");
        vm.prank(anyTrustFastConfirmer);
        userRollup.fastConfirmAssertion(assertionHash, genesisHash, afterState);
    }

    function testRevertFastConfirmNotConfirmer() public {
        (bytes32 assertionHash, AssertionState memory afterState,,) = testSuccessCreateAssertion();
        vm.expectRevert("NOT_FAST_CONFIRMER");
        userRollup.fastConfirmAssertion(assertionHash, genesisHash, afterState);
    }

    /**
     * Helper function to fast confirm an assertion with `fastConfirmNewAssertion`, and optionally create it beforehand
     *
     * Should return:
     * - the assertion inputs
     * - the expected assertion hash
     *
     * @dev To be used after `setUp()`
     * @dev Helper used in multiple other tests
     *
     * @param fastConfirmer the address used to call `fastConfirmNewAssertion`
     * @param expectedErrorMsg the expected error message for the call to `fastConfirmNewAssertion` (empty string if the call is expected to succeed)
     * @param createAssertion whether to create the assertion before calling `fastConfirmNewAssertion` (if false, the assertion will not be created, and the call to `fastConfirmNewAssertion` is expected to revert with "ASSERTION_NOT_FOUND")
     */
    function _testFastConfirmNewAssertion(
        address fastConfirmer,
        string memory expectedErrorMsg,
        bool createAssertion
    ) internal returns (AssertionInputs memory, bytes32) {
        AssertionState memory beforeState;
        beforeState.machineStatus = MachineStatus.FINISHED;
        AssertionState memory afterState = firstState;
        MELState memory afterMELState = firstMELState;

        bytes32 expectedAssertionHash =
            RollupLib.assertionHash({parentAssertionHash: genesisHash, afterState: afterState});

        AssertionInputs memory assertion = AssertionInputs({
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
            afterMELState: afterMELState
        });

        if (createAssertion) {
            vm.prank(validator1);
            userRollup.newStakeOnNewAssertion({
                tokenAmount: BASE_STAKE,
                assertion: assertion,
                expectedAssertionHash: expectedAssertionHash,
                _withdrawalAddress: validator1Withdrawal
            });
        }

        if (bytes(expectedErrorMsg).length > 0) {
            vm.expectRevert(bytes(expectedErrorMsg));
        }
        vm.prank(fastConfirmer);
        userRollup.fastConfirmNewAssertion({
            assertion: assertion,
            expectedAssertionHash: expectedAssertionHash
        });
        if (bytes(expectedErrorMsg).length == 0) {
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
            assertion: assertion,
            expectedAssertionHash: expectedAssertionHash
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
                [rand.hash(), rand.hash(), rand.hash(), rand.hash()],
                [0, 0, uint64(uint256(rand.hash())), uint64(uint256(rand.hash()))]
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
                [rand.hash(), rand.hash(), rand.hash(), rand.hash()],
                [0, 0, uint64(uint256(rand.hash())), uint64(uint256(rand.hash()))]
            ),
            MachineStatus.FINISHED,
            bytes32(0)
        );
        bytes32 expectedHash = keccak256(abi.encodePacked(parentHash, astate.hash()));
        assertEq(RollupLib.assertionHash(parentHash, astate), expectedHash, "Unexpected hash");
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

    function testDecreaseBaseStake() public {
        assertEq(adminRollup.baseStake(), BASE_STAKE, "Invalid before base stake");

        vm.expectRevert();
        adminRollup.decreaseBaseStake(BASE_STAKE - 1, 0);

        vm.expectRevert("BASE_STAKE_NOT_DECREASED");
        vm.prank(upgradeExecutorAddr);
        adminRollup.decreaseBaseStake(BASE_STAKE + 1, 0);

        vm.expectRevert("BASE_STAKE_NOT_DECREASED");
        vm.prank(upgradeExecutorAddr);
        adminRollup.decreaseBaseStake(BASE_STAKE, 0);

        vm.startPrank(upgradeExecutorAddr);
        adminRollup.setValidatorWhitelistDisabled(true);
        vm.expectRevert("DECREASE_ONLY_FOR_PERMISSIONED_CHAINS");
        adminRollup.decreaseBaseStake(BASE_STAKE - 1, 0);
        adminRollup.setValidatorWhitelistDisabled(false);
        vm.stopPrank();

        vm.expectRevert("PENDING_ASSERTION_NOT_UPDATED");
        vm.prank(upgradeExecutorAddr);
        adminRollup.decreaseBaseStake(BASE_STAKE - 1, 0);

        (
            bytes32 beforeAssertionHash,
            AssertionState memory beforeState,
            MELState memory beforeMELState,
            bytes32 nextParentChainBlockHash
        ) = testSuccessCreateAssertion();
        vm.prank(upgradeExecutorAddr);
        vm.expectRevert("EXPIRED_CONFIG_HASH");
        adminRollup.decreaseBaseStake(BASE_STAKE - 1, 0);

        vm.prank(upgradeExecutorAddr);
        adminRollup.decreaseBaseStake(BASE_STAKE - 1, nextParentChainBlockHash);

        MELState memory afterMELState = beforeMELState;
        // Add one message and update nextParentChainBlockHash
        // (the other values in MEL state are not relevant in the Rollup contracts)
        afterMELState.msgCount += 1;
        afterMELState.parentChainBlockHash = nextParentChainBlockHash;

        AssertionState memory afterState;
        afterState.machineStatus = MachineStatus.FINISHED;
        afterState.globalState.u64Vals[2] = beforeState.globalState.u64Vals[2] + 1; // increase MsgCount
        afterState.globalState.u64Vals[3] = beforeState.globalState.u64Vals[3] + 1; // increase ExecutedMsgCount
        afterState.globalState.bytes32Vals[2] = afterMELState.hash(); // update MEL State hash
        bytes32 expectedAssertionHash = RollupLib.assertionHash({
            parentAssertionHash: beforeAssertionHash,
            afterState: afterState
        });

        vm.roll(block.number + userRollup.minimumAssertionPeriod());

        // test that we can create a new assertion after stake reduction
        vm.prank(validator2);
        userRollup.newStakeOnNewAssertion({
            tokenAmount: BASE_STAKE - 1,
            assertion: AssertionInputs({
                beforeStateData: BeforeStateData({
                    prevPrevAssertionHash: genesisHash,
                    configData: ConfigData({
                        wasmModuleRoot: WASM_MODULE_ROOT,
                        requiredStake: BASE_STAKE - 1,
                        challengeManager: address(challengeManager),
                        confirmPeriodBlocks: CONFIRM_PERIOD_BLOCKS,
                        nextParentChainBlockHash: nextParentChainBlockHash
                    })
                }),
                beforeState: beforeState,
                afterState: afterState,
                afterMELState: afterMELState
            }),
            expectedAssertionHash: expectedAssertionHash,
            _withdrawalAddress: validator1Withdrawal
        });

        createStakeTooLowAssertion();
    }

    function createStakeTooLowAssertion() public {
        // trying to create an assertion with the genesis as parent will fail with stake too low
        AssertionState memory beforeState;
        beforeState.machineStatus = MachineStatus.FINISHED;
        AssertionState memory afterState = firstState;
        afterState.globalState.bytes32Vals[0] =
            keccak256(abi.encodePacked(FIRST_ASSERTION_BLOCKHASH)); // blockhash
        MELState memory afterMELState = firstMELState;

        bytes32 expectedAssertionHash =
            RollupLib.assertionHash({parentAssertionHash: genesisHash, afterState: afterState});

        vm.expectRevert("STAKE_TOO_LOW");
        vm.prank(validator3);
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
                beforeState: beforeState,
                afterState: afterState,
                afterMELState: afterMELState
            }),
            expectedAssertionHash: expectedAssertionHash,
            _withdrawalAddress: validator3Withdrawal
        });
    }

    function testCannotDecreaseBaseStakeWithForkedAssertionTree() public {
        assertEq(adminRollup.baseStake(), BASE_STAKE, "Invalid before base stake");

        SuccessCreateChallengeData memory data = testSuccessCreateChallenge();

        userRollup.getAssertion(data.assertionHash1);
        vm.expectRevert("TOO_MANY_PENDING_STAKERS");
        vm.prank(upgradeExecutorAddr);
        adminRollup.decreaseBaseStake(BASE_STAKE - 1, data.nextParentChainBlockHash);
    }
}
