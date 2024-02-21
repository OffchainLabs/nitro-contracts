// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {ISequencerInbox, SequencerInbox} from "../../../src/bridge/SequencerInbox.sol";
import {IReader4844} from "../../../src/libraries/IReader4844.sol";
import {OneStepProver0} from "../../../src/osp/OneStepProver0.sol";
import {OneStepProverMemory} from "../../../src/osp/OneStepProverMemory.sol";
import {OneStepProverMath} from "../../../src/osp/OneStepProverMath.sol";
import {OneStepProverHostIo} from "../../../src/osp/OneStepProverHostIo.sol";
import {OneStepProofEntry} from "../../../src/osp/OneStepProofEntry.sol";
import {ChallengeManager} from "../../../src/challenge/ChallengeManager.sol";
import "../../../src/rollup/RollupCreator.sol";
import {BridgeCreator} from "../../../src/rollup/BridgeCreator.sol";

contract DeployScript is Script {
    function run() public {
        // read deployment parameters from JSON config
        (uint256 maxDataSize, bool hostChainIsArbitrum, address rollupCreator) =
            _getDeploymentConfigParams();

        vm.startBroadcast();

        // deploy reader4844 if deploying to non-arbitrum chain
        address reader4844Address = address(0);
        if (!hostChainIsArbitrum) {
            bytes memory reader4844Bytecode = _getReader4844Bytecode();
            assembly {
                reader4844Address :=
                    create(0, add(reader4844Bytecode, 0x20), mload(reader4844Bytecode))
            }
            require(reader4844Address != address(0), "Reader4844 could not be deployed");
        }

        // deploy SequencerInbox templates for eth and fee token based chains
        SequencerInbox ethSeqInbox =
            new SequencerInbox(maxDataSize, IReader4844(reader4844Address), false);
        SequencerInbox erc20SeqInbox =
            new SequencerInbox(maxDataSize, IReader4844(reader4844Address), true);

        // deploy OSP templates
        OneStepProver0 osp0 = new OneStepProver0();
        OneStepProverMemory ospMemory = new OneStepProverMemory();
        OneStepProverMath ospMath = new OneStepProverMath();
        OneStepProverHostIo ospHostIo = new OneStepProverHostIo();
        new OneStepProofEntry(osp0, ospMemory, ospMath, ospHostIo);

        // deploy new challenge manager templates
        new ChallengeManager();

        // _updateTemplatesInBridgeCreator(rollupCreator, ethSeqInbox, erc20SeqInbox);

        _generateUpdateTemplatesCalldata(rollupCreator, ethSeqInbox, erc20SeqInbox);

        vm.stopBroadcast();
    }

    function _updateTemplatesInBridgeCreator(
        address rollupCreatorAddress,
        SequencerInbox ethSeqInbox,
        SequencerInbox erc20SeqInbox
    ) internal {
        // update eth templates in BridgeCreator
        BridgeCreator bridgeCreator = RollupCreator(payable(rollupCreatorAddress)).bridgeCreator();
        (IBridge bridge,, IInboxBase inbox, IRollupEventInbox rollupEventInbox, IOutbox outbox) =
            bridgeCreator.ethBasedTemplates();
        (
            IBridge erc20Bridge,
            ,
            IInboxBase erc20Inbox,
            IRollupEventInbox erc20RollupEventInbox,
            IOutbox erc20Outbox
        ) = bridgeCreator.erc20BasedTemplates();

        bridgeCreator.updateTemplates(
            BridgeCreator.BridgeContracts(
                bridge, ISequencerInbox(address(ethSeqInbox)), inbox, rollupEventInbox, outbox
            )
        );
        bridgeCreator.updateERC20Templates(
            BridgeCreator.BridgeContracts(
                erc20Bridge,
                ISequencerInbox(address(erc20SeqInbox)),
                erc20Inbox,
                erc20RollupEventInbox,
                erc20Outbox
            )
        );
    }

    function _generateUpdateTemplatesCalldata(
        address rollupCreatorAddress,
        SequencerInbox ethSeqInbox,
        SequencerInbox erc20SeqInbox
    ) internal {
        string memory rootObj = "root";

        BridgeCreator bridgeCreator = RollupCreator(payable(rollupCreatorAddress)).bridgeCreator();

        (IBridge bridge,, IInboxBase inbox, IRollupEventInbox rollupEventInbox, IOutbox outbox) =
            bridgeCreator.ethBasedTemplates();
        bytes memory updateTemplatesCalldata = abi.encodeWithSelector(
            BridgeCreator.updateTemplates.selector,
            BridgeCreator.BridgeContracts(
                bridge, ISequencerInbox(address(ethSeqInbox)), inbox, rollupEventInbox, outbox
            )
        );

        (
            IBridge erc20Bridge,
            ,
            IInboxBase erc20Inbox,
            IRollupEventInbox erc20RollupEventInbox,
            IOutbox erc20Outbox
        ) = bridgeCreator.erc20BasedTemplates();
        bytes memory updateErc20TemplatesCalldata = abi.encodeWithSelector(
            BridgeCreator.updateERC20Templates.selector,
            BridgeCreator.BridgeContracts(
                erc20Bridge,
                ISequencerInbox(address(erc20SeqInbox)),
                erc20Inbox,
                erc20RollupEventInbox,
                erc20Outbox
            )
        );

        vm.serializeString(rootObj, "updateTemplatesCalldata", vm.toString(updateTemplatesCalldata));
        string memory finalJson = vm.serializeString(
            rootObj, "updateErc20TemplatesCalldata", vm.toString(updateErc20TemplatesCalldata)
        );
        vm.writeJson(
            finalJson,
            string(
                abi.encodePacked(
                    vm.projectRoot(),
                    "/scripts/foundry/upgrade-1.2.1/output/",
                    vm.toString(block.chainid),
                    ".json"
                )
            )
        );
    }

    function _getReader4844Bytecode() internal returns (bytes memory) {
        string memory readerBytecodeFilePath =
            string(abi.encodePacked(vm.projectRoot(), "/out/yul/Reader4844.yul/Reader4844.json"));
        string memory json = vm.readFile(readerBytecodeFilePath);
        return vm.parseJsonBytes(json, ".bytecode.object");
    }

    function _getDeploymentConfigParams() internal returns (uint256, bool, address) {
        // read deployment parameters from JSON config
        string memory configFilePath = string(
            abi.encodePacked(
                vm.projectRoot(),
                "/scripts/foundry/upgrade-1.2.1/config/",
                vm.toString(block.chainid),
                ".json"
            )
        );
        string memory json = vm.readFile(configFilePath);

        // decode params
        uint256 maxDataSize = vm.parseJsonUint(json, ".maxDataSize");
        bool hostChainIsArbitrum = vm.parseJsonBool(json, ".hostChainIsArbitrum");
        address rollupCreator = vm.parseJsonAddress(json, ".rollupCreator");

        // sanity check
        require(
            maxDataSize == 117_964 || maxDataSize == 104_857, "Invalid maxDataSize in config file"
        );
        require(
            rollupCreator != address(0)
                && address(RollupCreator(payable(rollupCreator)).bridgeCreator()) != address(0),
            "Invalid rollupCreator in config file"
        );

        return (maxDataSize, hostChainIsArbitrum, rollupCreator);
    }
}
