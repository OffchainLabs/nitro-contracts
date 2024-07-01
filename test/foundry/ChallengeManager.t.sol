// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "./util/TestUtil.sol";
import "../../src/challenge/ChallengeManager.sol";
import "../../src/osp/OneStepProofEntry.sol";

contract ChallengeManagerTest is Test {
    IChallengeResultReceiver resultReceiver = IChallengeResultReceiver(address(137));
    ISequencerInbox sequencerInbox = ISequencerInbox(address(138));
    IBridge bridge = IBridge(address(139));
    IOneStepProofEntry osp = IOneStepProofEntry(address(140));
    IOneStepProofEntry newOsp = IOneStepProofEntry(address(141));
    IOneStepProofEntry condOsp = IOneStepProofEntry(address(142));
    address proxyAdmin = address(141);
    ChallengeManager chalmanImpl = new ChallengeManager();

    bytes32 randomRoot = keccak256(abi.encodePacked("randomRoot"));

    function deploy() public returns (ChallengeManager) {
        ChallengeManager chalman = ChallengeManager(
            address(new TransparentUpgradeableProxy(address(chalmanImpl), proxyAdmin, ""))
        );
        chalman.initialize(resultReceiver, sequencerInbox, bridge, osp);
        assertEq(
            address(chalman.resultReceiver()), address(resultReceiver), "Result receiver not set"
        );
        assertEq(
            address(chalman.sequencerInbox()), address(sequencerInbox), "Sequencer inbox not set"
        );
        assertEq(address(chalman.bridge()), address(bridge), "Bridge not set");
        assertEq(address(chalman.osp()), address(osp), "OSP not set");
        return chalman;
    }

    function testCondOsp() public {
        ChallengeManager chalman = deploy();

        /// legacy root and OSP that will be used as conditional
        IOneStepProofEntry legacyOSP = IOneStepProofEntry(
            address(
                new OneStepProofEntry(
                    IOneStepProver(makeAddr("0")),
                    IOneStepProver(makeAddr("mem")),
                    IOneStepProver(makeAddr("math")),
                    IOneStepProver(makeAddr("hostio"))
                )
            )
        );
        bytes32 legacyRoot = keccak256(abi.encodePacked("legacyRoot"));

        // legacy hashes
        bytes32 legacySegment0 = legacyOSP.getStartMachineHash(
            keccak256(abi.encodePacked("globalStateHash[0]")), legacyRoot
        );
        bytes32 legacySegment1 = legacyOSP.getEndMachineHash(
            MachineStatus.FINISHED, keccak256(abi.encodePacked("globalStateHashes[1]"))
        );

        /// new OSP
        IOneStepProofEntry _newOSP = IOneStepProofEntry(
            address(
                new OneStepProofEntry(
                    IOneStepProver(makeAddr("0")),
                    IOneStepProver(makeAddr("mem")),
                    IOneStepProver(makeAddr("math")),
                    IOneStepProver(makeAddr("hostio"))
                )
            )
        );

        // new hashes
        bytes32 newSegment0 = _newOSP.getStartMachineHash(
            keccak256(abi.encodePacked("globalStateHash[0]")), randomRoot
        );
        bytes32 newSegment1 = _newOSP.getEndMachineHash(
            MachineStatus.FINISHED, keccak256(abi.encodePacked("new_globalStateHashes[1]"))
        );

        /// do upgrade
        vm.prank(proxyAdmin);
        TransparentUpgradeableProxy(payable(address(chalman))).upgradeToAndCall(
            address(chalmanImpl),
            abi.encodeWithSelector(
                ChallengeManager.postUpgradeInit.selector, _newOSP, legacyRoot, legacyOSP
            )
        );

        /// check cond osp
        IOneStepProofEntry _condOsp = chalman.getOsp(legacyRoot);
        assertEq(address(_condOsp), address(legacyOSP), "Legacy osp not set");
        assertEq(
            _condOsp.getStartMachineHash(
                keccak256(abi.encodePacked("globalStateHash[0]")), legacyRoot
            ),
            legacySegment0,
            "Unexpected start machine hash"
        );
        assertEq(
            _condOsp.getEndMachineHash(
                MachineStatus.FINISHED, keccak256(abi.encodePacked("globalStateHashes[1]"))
            ),
            legacySegment1,
            "Unexpected end machine hash"
        );

        /// check new osp
        IOneStepProofEntry _newOsp = chalman.getOsp(randomRoot);
        assertEq(address(_newOsp), address(_newOSP), "New osp not set");
        assertEq(
            _newOsp.getStartMachineHash(
                keccak256(abi.encodePacked("globalStateHash[0]")), randomRoot
            ),
            newSegment0,
            "Unexpected start machine hash"
        );
        assertEq(
            _newOsp.getEndMachineHash(
                MachineStatus.FINISHED, keccak256(abi.encodePacked("new_globalStateHashes[1]"))
            ),
            newSegment1,
            "Unexpected end machine hash"
        );

        /// check hashes are different
        assertNotEq(legacySegment0, newSegment0, "Start machine hash should be different");
        assertNotEq(legacySegment1, newSegment1, "End machine hash should be different");
    }

    function testPostUpgradeInit() public {
        ChallengeManager chalman = deploy();

        vm.prank(proxyAdmin);
        TransparentUpgradeableProxy(payable(address(chalman))).upgradeToAndCall(
            address(chalmanImpl),
            abi.encodeWithSelector(
                ChallengeManager.postUpgradeInit.selector, newOsp, randomRoot, condOsp
            )
        );

        assertEq(address(chalman.getOsp(bytes32(0))), address(newOsp), "New osp not set");
        assertEq(address(chalman.getOsp(randomRoot)), address(condOsp), "Cond osp not set");
    }

    function testPostUpgradeInitFailsNotAdmin() public {
        ChallengeManager chalman = deploy();

        vm.expectRevert(abi.encodeWithSelector(NotOwner.selector, address(151), proxyAdmin));
        vm.prank(address(151));
        chalman.postUpgradeInit(newOsp, randomRoot, condOsp);
    }

    function testPostUpgradeInitFailsNotDelCall() public {
        vm.expectRevert(bytes("Function must be called through delegatecall"));
        vm.prank(proxyAdmin);
        chalmanImpl.postUpgradeInit(newOsp, randomRoot, condOsp);
    }
}
