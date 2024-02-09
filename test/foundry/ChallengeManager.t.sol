// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "./util/TestUtil.sol";
import "../../src/challenge/ChallengeManager.sol";

contract ChallengeManagerTest is Test {
    IChallengeResultReceiver resultReceiver = IChallengeResultReceiver(address(137));
    ISequencerInbox sequencerInbox = ISequencerInbox(address(138));
    IBridge bridge = IBridge(address(139));
    IOneStepProofEntry osp = IOneStepProofEntry(address(140));
    IOneStepProofEntry newOsp = IOneStepProofEntry(address(141));
    address proxyAdmin = address(141);
    ChallengeManager chalmanImpl = new ChallengeManager();

    function deploy() public returns (ChallengeManager) {
        ChallengeManager chalman = ChallengeManager(
            address(new TransparentUpgradeableProxy(address(chalmanImpl), proxyAdmin, ""))
        );
        chalman.initialize(resultReceiver, sequencerInbox, bridge, osp);
        assertEq(
            address(chalman.resultReceiver()),
            address(resultReceiver),
            "Result receiver not set"
        );
        assertEq(
            address(chalman.sequencerInbox()),
            address(sequencerInbox),
            "Sequencer inbox not set"
        );
        assertEq(address(chalman.bridge()), address(bridge), "Bridge not set");
        assertEq(address(chalman.osp()), address(osp), "OSP not set");
        return chalman;
    }

    function testPostUpgradeInit() public {
        ChallengeManager chalman = deploy();

        vm.prank(proxyAdmin);
        TransparentUpgradeableProxy(payable(address(chalman))).upgradeToAndCall(
            address(chalmanImpl),
            abi.encodeWithSelector(ChallengeManager.postUpgradeInit.selector, newOsp)
        );

        assertEq(address(chalman.osp()), address(newOsp), "New osp not set");
    }

    function testPostUpgradeInitFailsNotAdmin() public {
        ChallengeManager chalman = deploy();

        vm.expectRevert(abi.encodeWithSelector(NotOwner.selector, address(151), proxyAdmin));
        vm.prank(address(151));
        chalman.postUpgradeInit(osp);
    }

    function testPostUpgradeInitFailsNotDelCall() public {
        vm.expectRevert(bytes("Function must be called through delegatecall"));
        vm.prank(proxyAdmin);
        chalmanImpl.postUpgradeInit(osp);
    }
}
