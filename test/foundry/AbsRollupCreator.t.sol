// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "./util/TestUtil.sol";
import "../../src/rollup/IRollupCreator.sol";
import "../../src/rollup/RollupAdminLogic.sol";
import "../../src/rollup/RollupUserLogic.sol";
import "../../src/rollup/ValidatorUtils.sol";
import "../../src/rollup/ValidatorWalletCreator.sol";
import "../../src/challenge/ChallengeManager.sol";
import "../../src/osp/OneStepProver0.sol";
import "../../src/osp/OneStepProverMemory.sol";
import "../../src/osp/OneStepProverMath.sol";
import "../../src/osp/OneStepProverHostIo.sol";
import "../../src/osp/OneStepProofEntry.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract AbsRollupCreatorTest is Test {
    address public rollupOwner = address(4400);
    address public deployer = address(4300);

    function _prepareRollupDeployment(address rollupCreator, Config memory config)
        internal
        returns (
            IOneStepProofEntry ospEntry,
            IChallengeManager challengeManager,
            IRollupAdmin rollupAdminLogic,
            IRollupUser rollupUserLogic
        )
    {
        //// deploy challenge stuff
        ospEntry = new OneStepProofEntry(
            new OneStepProver0(),
            new OneStepProverMemory(),
            new OneStepProverMath(),
            new OneStepProverHostIo()
        );
        challengeManager = new ChallengeManager();

        //// deploy rollup logic
        rollupAdminLogic = IRollupAdmin(new RollupAdminLogic());
        rollupUserLogic = IRollupUser(new RollupUserLogic());

        return (ospEntry, challengeManager, rollupAdminLogic, rollupUserLogic);
    }

    function _getProxyAdmin(address proxy) internal view returns (address) {
        bytes32 adminSlot = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);
        return address(uint160(uint256(vm.load(proxy, adminSlot))));
    }

    function _getPrimary(address proxy) internal view returns (address) {
        bytes32 primarySlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        return address(uint160(uint256(vm.load(proxy, primarySlot))));
    }

    function _getSecondary(address proxy) internal view returns (address) {
        bytes32 secondarySlot = bytes32(
            uint256(keccak256("eip1967.proxy.implementation.secondary")) - 1
        );
        return address(uint160(uint256(vm.load(proxy, secondarySlot))));
    }

    /****
     **** Event declarations
     ***/

    event RollupCreated(
        address indexed rollupAddress,
        address inboxAddress,
        address adminProxy,
        address sequencerInbox,
        address bridge
    );

    event RollupInitialized(bytes32 machineHash, uint256 chainId);
}
