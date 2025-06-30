// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import {ImplementationsRegistry} from "./ImplementationsRegistry.sol";
import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {IInbox} from "../bridge/IInbox.sol";
import {SequencerInbox} from "../bridge/SequencerInbox.sol";
import {IOutbox} from "../bridge/IOutbox.sol";
import {RollupAdminLogic} from "../rollup/RollupAdminLogic.sol";
import {IRollupCore} from "../rollup/IRollupCore.sol";
import {
    IEdgeChallengeManager, EdgeChallengeManager
} from "../challengeV2/EdgeChallengeManager.sol";
import {IOneStepProofEntry} from "../osp/IOneStepProofEntry.sol";

abstract contract BaseNitroContractsUpgradeAction {
    ImplementationsRegistry public immutable prevImplementationsRegistry;
    ImplementationsRegistry public immutable nextImplementationsRegistry;

    event ContractUpgraded(string contractName, address oldImpl, address newImpl);
    event ChallengeManagerDeployed(
        address oldChallengeManager,
        address oldChallengeManagerImpl,
        address newChallengeManager,
        address newChallengeManagerImpl,
        address oldOspEntry,
        address newOspEntry
    );

    constructor(
        ImplementationsRegistry _prevImplementationsRegistry,
        ImplementationsRegistry _nextImplementationsRegistry
    ) {
        prevImplementationsRegistry = _prevImplementationsRegistry;
        nextImplementationsRegistry = _nextImplementationsRegistry;
    }

    function _upgradeAllProxies(address proxyAdmin, address inbox) internal {
        ProxyAdmin admin = ProxyAdmin(proxyAdmin);
        SequencerInbox sequencerInbox = SequencerInbox(address(IInbox(inbox).sequencerInbox()));
        bool isUsingFeeToken = sequencerInbox.isUsingFeeToken();

        // Inbox
        _upgradeOne(
            admin,
            inbox,
            isUsingFeeToken ? "ERC20Inbox" : "Inbox",
            abi.encode(IInbox(inbox).maxDataSize())
        );

        // SequencerInbox
        _upgradeOne(
            admin,
            address(sequencerInbox),
            "SequencerInbox",
            abi.encode(
                sequencerInbox.maxDataSize(),
                sequencerInbox.reader4844(),
                isUsingFeeToken,
                sequencerInbox.isDelayBufferable()
            )
        );

        // Bridge
        _upgradeOne(
            admin,
            address(IInbox(inbox).bridge()),
            isUsingFeeToken ? "ERC20Bridge" : "Bridge",
            abi.encode(inbox)
        );

        // Outbox
        _upgradeOne(
            admin,
            IInbox(inbox).bridge().activeOutbox(),
            isUsingFeeToken ? "ERC20Outbox" : "Outbox",
            ""
        );

        // RollupAdminLogic & RollupUserLogic
        // since the rollup is a double logic proxy, we have special logic to upgrade it
        address rollup = IOutbox(IInbox(inbox).bridge().activeOutbox()).rollup();
        _upgradeRollupAdmmin(rollup);
        _upgradeRollupUser(rollup);

        // REI
        address rei = address(IRollupCore(rollup).rollupEventInbox());
        _upgradeOne(admin, rei, "RollupEventInbox", "");

        // OSP & EdgeChallengeManager
        // the standard path to upgrade the EdgeChallengeManager and OSP contracts is to
        // deploy a new challenge manager with the OSP's and set it on the rollup
        _deployChallengeManager(
            admin, EdgeChallengeManager(address(IRollupCore(rollup).challengeManager()))
        );

        // ValidatorWalletCreator
        // currently there is no way to set the creator on the rollup
        // todo: put this in nitro config or something

        // UpgradeExecutor
        _upgradeOne(admin, address(this), "UpgradeExecutor", "");
    }

    function _getOspEntry(
        bool next
    ) private view returns (IOneStepProofEntry) {
        ImplementationsRegistry registry =
            next ? nextImplementationsRegistry : prevImplementationsRegistry;
        return IOneStepProofEntry(
            registry.getAddressWithArgs(
                "OneStepProofEntry",
                keccak256(
                    abi.encode(
                        registry.getAddressWithArgs("OneStepProver0", ""),
                        registry.getAddressWithArgs("OneStepProverMemory", ""),
                        registry.getAddressWithArgs("OneStepProverMath", ""),
                        registry.getAddressWithArgs("OneStepProverHostIo", "")
                    )
                )
            )
        );
    }

    function _deployChallengeManager(
        ProxyAdmin proxyAdmin,
        EdgeChallengeManager oldChallengeManager
    ) private {
        address prevImpl =
            prevImplementationsRegistry.getAddressWithArgs("RollupAdminLogic", keccak256(""));
        address nextImpl =
            nextImplementationsRegistry.getAddressWithArgs("RollupAdminLogic", keccak256(""));
        IOneStepProofEntry prevOsp = _getOspEntry(false);
        IOneStepProofEntry nextOsp = _getOspEntry(true);

        if (
            proxyAdmin.getProxyImplementation(
                TransparentUpgradeableProxy(payable(address(oldChallengeManager)))
            ) != prevImpl
        ) {
            revert("Old challenge manager implementation mismatch");
        }

        if (oldChallengeManager.oneStepProofEntry() != prevOsp) {
            revert("Old challenge manager OSP entry mismatch");
        }

        if (prevImpl == nextImpl && prevOsp == nextOsp) {
            // no need to deploy a new challenge manager
            return;
        }

        uint256 numBigStepLevels = oldChallengeManager.NUM_BIGSTEP_LEVEL();
        uint256[] memory stakeAmounts = new uint256[](numBigStepLevels + 2);
        for (uint256 i = 0; i < numBigStepLevels + 2; i++) {
            stakeAmounts[i] = oldChallengeManager.stakeAmounts(i);
        }

        address newChallengeManager = address(
            new TransparentUpgradeableProxy(
                nextImpl,
                address(proxyAdmin),
                abi.encodeCall(
                    IEdgeChallengeManager.initialize,
                    (
                        oldChallengeManager.assertionChain(), // IAssertionChain _assertionChain,
                        oldChallengeManager.challengePeriodBlocks(), // uint64 _challengePeriodBlocks,
                        nextOsp, // IOneStepProofEntry _oneStepProofEntry,
                        oldChallengeManager.LAYERZERO_BLOCKEDGE_HEIGHT(), // uint256 layerZeroBlockEdgeHeight,
                        oldChallengeManager.LAYERZERO_BIGSTEPEDGE_HEIGHT(), // uint256 layerZeroBigStepEdgeHeight,
                        oldChallengeManager.LAYERZERO_SMALLSTEPEDGE_HEIGHT(), // uint256 layerZeroSmallStepEdgeHeight,
                        oldChallengeManager.stakeToken(), // IERC20 _stakeToken,
                        oldChallengeManager.excessStakeReceiver(), // address _excessStakeReceiver,
                        oldChallengeManager.NUM_BIGSTEP_LEVEL(), // uint8 _numBigStepLevel,
                        stakeAmounts // uint256[] calldata _stakeAmounts
                    )
                )
            )
        );

        emit ChallengeManagerDeployed(
            address(oldChallengeManager),
            prevImpl,
            newChallengeManager,
            nextImpl,
            address(prevOsp),
            address(nextOsp)
        );
    }

    function _upgradeRollupAdmmin(
        address rollup
    ) private {
        address prevImpl =
            prevImplementationsRegistry.getAddressWithArgs("RollupAdminLogic", keccak256(""));
        address nextImpl =
            nextImplementationsRegistry.getAddressWithArgs("RollupAdminLogic", keccak256(""));
        if (RollupAdminLogic(rollup).getPrimaryImplementation() != prevImpl) {
            revert("RollupAdminLogic implementation mismatch"); // todo custom error
        }
        if (prevImpl != nextImpl) {
            RollupAdminLogic(rollup).upgradeTo(nextImpl);
            emit ContractUpgraded("RollupAdmin", prevImpl, nextImpl);
        }
    }

    function _upgradeRollupUser(
        address rollup
    ) private {
        address prevImpl =
            prevImplementationsRegistry.getAddressWithArgs("RollupUserLogic", keccak256(""));
        address nextImpl =
            nextImplementationsRegistry.getAddressWithArgs("RollupUserLogic", keccak256(""));
        if (RollupAdminLogic(rollup).getSecondaryImplementation() != prevImpl) {
            revert("RollupUserLogic implementation mismatch"); // todo custom error
        }
        if (prevImpl != nextImpl) {
            RollupAdminLogic(rollup).upgradeTo(nextImpl);
            emit ContractUpgraded("RollupAdmin", prevImpl, nextImpl);
        }
    }

    function _upgradeOne(
        ProxyAdmin admin,
        address proxy,
        string memory name,
        bytes memory args
    ) private {
        bytes32 argsHash = keccak256(args);
        address prevImpl = prevImplementationsRegistry.getAddressWithArgs(name, argsHash);
        address nextImpl = nextImplementationsRegistry.getAddressWithArgs(name, argsHash);
        if (admin.getProxyImplementation(TransparentUpgradeableProxy(payable(proxy))) != prevImpl) {
            revert("Implementation mismatch"); // todo custom error
        }
        if (prevImpl != nextImpl) {
            admin.upgrade(TransparentUpgradeableProxy(payable(proxy)), nextImpl);
            emit ContractUpgraded(name, prevImpl, nextImpl);
        }
    }
}
