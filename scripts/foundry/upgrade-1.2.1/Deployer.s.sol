// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Script.sol";
import {SequencerInbox} from "../../../src/bridge/SequencerInbox.sol";
import {IReader4844} from "../../../src/libraries/IReader4844.sol";

contract DeployScript is Script {
    function run() public {
        bytes memory reader4844Bytecode = _getReader4844Bytecode();

        vm.startBroadcast();

        // deploy reader4844
        address reader4844Address;
        assembly {
            reader4844Address := create(0, add(reader4844Bytecode, 0x20), mload(reader4844Bytecode))
        }
        require(reader4844Address != address(0), "Reader4844 could not be deployed");

        // deploy SequencerInbox templates for eth and fee token based chains
        SequencerInbox ethSeqInbox =
            new SequencerInbox(104_857, IReader4844(reader4844Address), false);
        SequencerInbox feeTokenSeqInbox =
            new SequencerInbox(104_857, IReader4844(reader4844Address), true);

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
}
