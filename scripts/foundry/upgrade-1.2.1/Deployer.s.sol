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

/**
 * @title DeployScript
 * @notice This script will deploy blob reader (if supported), SequencerInbox, OSP and ChallengeManager templates,
 *          and finally update templates in BridgeCreator, or generate calldata for gnosis safe
 */
contract DeployScript is Script {
    function run() public {
        // read deployment parameters from JSON config
        (
            uint256 maxDataSize,
            bool hostChainIsArbitrum,
            address rollupCreator,
            bool creatorOwnerIsMultisig
        ) = _getDeploymentConfigParams();

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

        if (creatorOwnerIsMultisig) {
            _generateUpdateTemplatesCalldata(rollupCreator, ethSeqInbox, erc20SeqInbox);
        } else {
            _updateTemplatesInBridgeCreator(rollupCreator, ethSeqInbox, erc20SeqInbox);
        }

        vm.stopBroadcast();
    }

    /**
     * @notice Update eth and erc20 templates in BridgeCreator
     */
    function _updateTemplatesInBridgeCreator(
        address rollupCreatorAddress,
        SequencerInbox newEthSeqInbox,
        SequencerInbox newErc20SeqInbox
    ) internal {
        BridgeCreator bridgeCreator = RollupCreator(payable(rollupCreatorAddress)).bridgeCreator();

        // update eth templates in BridgeCreator
        (IBridge bridge,, IInboxBase inbox, IRollupEventInbox rollupEventInbox, IOutbox outbox) =
            bridgeCreator.ethBasedTemplates();
        bridgeCreator.updateTemplates(
            BridgeCreator.BridgeContracts(
                bridge, ISequencerInbox(address(newEthSeqInbox)), inbox, rollupEventInbox, outbox
            )
        );

        // update erc20 templates in BridgeCreator
        (
            IBridge erc20Bridge,
            ,
            IInboxBase erc20Inbox,
            IRollupEventInbox erc20RollupEventInbox,
            IOutbox erc20Outbox
        ) = bridgeCreator.erc20BasedTemplates();
        bridgeCreator.updateERC20Templates(
            BridgeCreator.BridgeContracts(
                erc20Bridge,
                ISequencerInbox(address(newErc20SeqInbox)),
                erc20Inbox,
                erc20RollupEventInbox,
                erc20Outbox
            )
        );

        // verify
        (, ISequencerInbox _ethSeqInbox,,,) = bridgeCreator.ethBasedTemplates();
        (, ISequencerInbox _erc20SeqInbox,,,) = bridgeCreator.erc20BasedTemplates();
        require(
            address(_ethSeqInbox) == address(newEthSeqInbox)
                && address(_erc20SeqInbox) == address(newErc20SeqInbox),
            "Templates not updated"
        );
    }

    /**
     * @notice Generate calldata for updating eth and erc20 templates in BridgeCreator, then write
     *         it to JSON file at ${root}/scripts/foundry/upgrade-1.2.1/output/${chainId}.json
     */
    function _generateUpdateTemplatesCalldata(
        address rollupCreatorAddress,
        SequencerInbox ethSeqInbox,
        SequencerInbox erc20SeqInbox
    ) internal {
        BridgeCreator bridgeCreator = RollupCreator(payable(rollupCreatorAddress)).bridgeCreator();
        bytes memory updateTemplatesCalldata;
        bytes memory updateErc20TemplatesCalldata;

        {
            // generate calldata for updating eth templates
            (IBridge bridge,, IInboxBase inbox, IRollupEventInbox rollupEventInbox, IOutbox outbox)
            = bridgeCreator.ethBasedTemplates();
            updateTemplatesCalldata = abi.encodeWithSelector(
                BridgeCreator.updateTemplates.selector,
                BridgeCreator.BridgeContracts(
                    bridge, ISequencerInbox(address(ethSeqInbox)), inbox, rollupEventInbox, outbox
                )
            );

            // generate calldata for updating erc20 templates
            (
                IBridge erc20Bridge,
                ,
                IInboxBase erc20Inbox,
                IRollupEventInbox erc20RollupEventInbox,
                IOutbox erc20Outbox
            ) = bridgeCreator.erc20BasedTemplates();
            updateErc20TemplatesCalldata = abi.encodeWithSelector(
                BridgeCreator.updateERC20Templates.selector,
                BridgeCreator.BridgeContracts(
                    erc20Bridge,
                    ISequencerInbox(address(erc20SeqInbox)),
                    erc20Inbox,
                    erc20RollupEventInbox,
                    erc20Outbox
                )
            );
        }

        // construct JSON and write to file
        string memory rootObj = "root";
        vm.serializeString(rootObj, "chainId", vm.toString(block.chainid));
        vm.serializeString(rootObj, "to", vm.toString(address(bridgeCreator)));
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

    /**
     * @notice Read Reader4844 bytecode from JSON file at ${root}/out/yul/Reader4844.yul/Reader4844.json
     */
    function _getReader4844Bytecode() internal returns (bytes memory) {
        string memory readerBytecodeFilePath =
            string(abi.encodePacked(vm.projectRoot(), "/out/yul/Reader4844.yul/Reader4844.json"));
        string memory json = vm.readFile(readerBytecodeFilePath);
        return vm.parseJsonBytes(json, ".bytecode.object");
    }

    /**
     * @notice Read deployment parameters from JSON config file at ${root}/scripts/foundry/upgrade-1.2.1/config/${chainId}.json
     */
    function _getDeploymentConfigParams() internal returns (uint256, bool, address, bool) {
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
        bool creatorOwnerIsMultisig = vm.parseJsonBool(json, ".creatorOwnerIsMultisig");

        // sanity check
        require(
            maxDataSize == 117_964 || maxDataSize == 104_857, "Invalid maxDataSize in config file"
        );
        require(
            rollupCreator != address(0)
                && address(RollupCreator(payable(rollupCreator)).bridgeCreator()) != address(0),
            "Invalid rollupCreator in config file"
        );

        return (maxDataSize, hostChainIsArbitrum, rollupCreator, creatorOwnerIsMultisig);
    }
}
