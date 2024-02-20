// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Script.sol";
import {SequencerInbox} from "../../../src/bridge/SequencerInbox.sol";
import {IReader4844} from "../../../src/libraries/IReader4844.sol";
import {OneStepProver0} from "../../../src/osp/OneStepProver0.sol";
import {OneStepProverMemory} from "../../../src/osp/OneStepProverMemory.sol";
import {OneStepProverMath} from "../../../src/osp/OneStepProverMath.sol";
import {OneStepProverHostIo} from "../../../src/osp/OneStepProverHostIo.sol";
import {OneStepProofEntry} from "../../../src/osp/OneStepProofEntry.sol";
import {ChallengeManager} from "../../../src/challenge/ChallengeManager.sol";

contract DeployScript is Script {
    function run() public {
        bytes memory reader4844Bytecode = _getReader4844Bytecode();

        string memory file = _readFile();
        console.log(file);

        // read deployment parameters from JSON config
        uint256 maxDataSize = vm.parseJsonUint(file, ".maxDataSize");
        bool hostChainIsArbitrum = vm.parseJsonBool(file, ".hostChainIsArbitrum");

        vm.startBroadcast();

        // deploy reader4844 if deploying to non-arbitrum chain
        address reader4844Address = address(0);
        if (!hostChainIsArbitrum) {
            assembly {
                reader4844Address :=
                    create(0, add(reader4844Bytecode, 0x20), mload(reader4844Bytecode))
            }
            require(reader4844Address != address(0), "Reader4844 could not be deployed");
        }

        // deploy SequencerInbox templates for eth and fee token based chains
        SequencerInbox ethSeqInbox =
            new SequencerInbox(maxDataSize, IReader4844(reader4844Address), false);
        SequencerInbox feeTokenSeqInbox =
            new SequencerInbox(maxDataSize, IReader4844(reader4844Address), true);

        // deploy OSP templates
        OneStepProver0 osp0 = new OneStepProver0();
        OneStepProverMemory ospMemory = new OneStepProverMemory();
        OneStepProverMath ospMath = new OneStepProverMath();
        OneStepProverHostIo ospHostIo = new OneStepProverHostIo();
        OneStepProofEntry ospEntry = new OneStepProofEntry(osp0, ospMemory, ospMath, ospHostIo);

        // deploy new challenge manager templates
        ChallengeManager challengeManager = new ChallengeManager();

        vm.stopBroadcast();
    }

    function _getReader4844Bytecode() internal returns (bytes memory bytecode) {
        string memory readerBytecodeFile =
            string(abi.encodePacked(vm.projectRoot(), "/out/yul/Reader4844.yul/Reader4844.json"));

        string[] memory inputs = new string[](4);
        inputs[0] = "jq";
        inputs[1] = "-r";
        inputs[2] = ".bytecode.object";
        inputs[3] = readerBytecodeFile;

        bytecode = vm.ffi(inputs);
    }

    function _readFile() internal returns (string memory) {
        string memory path = string(
            abi.encodePacked(
                vm.projectRoot(),
                "/scripts/foundry/upgrade-1.2.1/inputs/",
                vm.toString(block.chainid),
                "/params.json"
            )
        );
        return vm.readFile(path);
    }
}
