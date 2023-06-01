// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./AbsRollupCreator.t.sol";
import "../../src/rollup/BridgeCreator.sol";
import "../../src/rollup/RollupCreator.sol";

contract RollupCreatorTest is AbsRollupCreatorTest {
    function setUp() public {}

    /* solhint-disable func-name-mixedcase */

    function test_createRollup() public {
        vm.startPrank(deployer);

        RollupCreator rollupCreator = new RollupCreator();

        // deployment params
        bytes32 wasmModuleRoot = keccak256("wasm");
        uint256 chainId = 1337;
        ISequencerInbox.MaxTimeVariation memory timeVars = ISequencerInbox.MaxTimeVariation(
            ((60 * 60 * 24) / 15),
            12,
            60 * 60 * 24,
            60 * 60
        );
        Config memory config = Config({
            confirmPeriodBlocks: 20,
            extraChallengeTimeBlocks: 200,
            stakeToken: address(0),
            baseStake: 1000,
            wasmModuleRoot: keccak256("0"),
            owner: rollupOwner,
            loserStakeEscrow: address(200),
            chainId: chainId,
            chainConfig: "abc",
            genesisBlockNum: 15000000,
            sequencerInboxMaxTimeVariation: timeVars
        });

        (
            IOneStepProofEntry ospEntry,
            IChallengeManager challengeManager,
            IRollupAdmin rollupAdmin,
            IRollupUser rollupUser
        ) = _prepareRollupDeployment(address(rollupCreator), config);
        //// deployBridgeCreator
        IBridgeCreator bridgeCreator = new BridgeCreator();

        //// deploy creator and set logic
        rollupCreator.setTemplates(
            bridgeCreator,
            ospEntry,
            challengeManager,
            rollupAdmin,
            rollupUser,
            address(new ValidatorUtils()),
            address(new ValidatorWalletCreator())
        );

        /// deploy rollup
        address rollupAddress = rollupCreator.createRollup(config);

        vm.stopPrank();

        /// common checks

        /// rollup creator
        assertEq(IOwnable(address(rollupCreator)).owner(), deployer, "Invalid rollupCreator owner");

        /// rollup proxy
        assertEq(IOwnable(rollupAddress).owner(), rollupOwner, "Invalid rollup owner");
        assertEq(_getProxyAdmin(rollupAddress), rollupOwner, "Invalid rollup's proxyAdmin owner");
        assertEq(_getPrimary(rollupAddress), address(rollupAdmin), "Invalid proxy primary impl");
        assertEq(_getSecondary(rollupAddress), address(rollupUser), "Invalid proxy secondary impl");

        /// rollup check
        RollupCore rollup = RollupCore(rollupAddress);
        assertTrue(address(rollup.sequencerInbox()) != address(0), "Invalid seqInbox");
        assertTrue(address(rollup.bridge()) != address(0), "Invalid bridge");
        assertTrue(address(rollup.inbox()) != address(0), "Invalid inbox");
        assertTrue(address(rollup.outbox()) != address(0), "Invalid outbox");
        assertTrue(address(rollup.rollupEventInbox()) != address(0), "Invalid rollupEventInbox");
        assertTrue(address(rollup.challengeManager()) != address(0), "Invalid challengeManager");
    }
}
