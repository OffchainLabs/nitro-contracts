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
import {IAssertionChain} from "../challengeV2/IAssertionChain.sol";
import {
    IEdgeChallengeManager, EdgeChallengeManager
} from "../challengeV2/EdgeChallengeManager.sol";
import {IOneStepProofEntry} from "../osp/IOneStepProofEntry.sol";

/// @notice Base contract for Nitro contracts upgrade actions.
/// This contract provides a _upgradeAllContract function that upgrades all the
/// Nitro contracts to the next implementations. It will only perform the upgrade if the implementation address is different.
/// Uses the ImplementationsRegistry to get the implementation addresses for the current and next version.
abstract contract BaseNitroContractsUpgradeAction {
    ImplementationsRegistry public immutable prevImplementationsRegistry;
    ImplementationsRegistry public immutable nextImplementationsRegistry;

    event ContractUpgraded(string contractName, address oldImpl, address newImpl);
    event ChallengeManagerDeployed(
        address oldChallengeManager,
        address newChallengeManager,
        address newChallengeManagerImpl,
        address newOspEntry
    );

    constructor(
        ImplementationsRegistry _prevImplementationsRegistry,
        ImplementationsRegistry _nextImplementationsRegistry
    ) {
        prevImplementationsRegistry = _prevImplementationsRegistry;
        nextImplementationsRegistry = _nextImplementationsRegistry;
    }

    function _upgradeAllContracts(address proxyAdmin, address inbox) internal {
        ProxyAdmin admin = ProxyAdmin(proxyAdmin);
        SequencerInbox sequencerInbox = SequencerInbox(address(IInbox(inbox).sequencerInbox()));
        bool isUsingFeeToken = sequencerInbox.isUsingFeeToken();

        // Inbox
        _upgrade(
            admin,
            inbox,
            isUsingFeeToken ? "ERC20Inbox" : "Inbox",
            abi.encode(IInbox(inbox).maxDataSize())
        );

        // SequencerInbox
        _upgrade(
            admin,
            _sequencerInbox(inbox),
            "SequencerInbox",
            abi.encode(
                sequencerInbox.maxDataSize(),
                sequencerInbox.reader4844(),
                isUsingFeeToken,
                sequencerInbox.isDelayBufferable()
            )
        );

        // Bridge
        _upgrade(
            admin, _bridge(inbox), isUsingFeeToken ? "ERC20Bridge" : "Bridge", abi.encode(inbox)
        );

        // Outbox
        _upgrade(admin, _outbox(inbox), isUsingFeeToken ? "ERC20Outbox" : "Outbox", "");

        // RollupAdminLogic & RollupUserLogic
        // since the rollup is a double logic proxy, we have special logic to upgrade it
        address rollup = _rollup(inbox);
        _upgradeRollupAdmmin(rollup);
        _upgradeRollupUser(rollup);

        // REI
        address rei = _rollupEventInbox(inbox);
        _upgrade(admin, rei, "RollupEventInbox", "");

        // OSP & EdgeChallengeManager
        // the standard path to upgrade the EdgeChallengeManager and OSP contracts is to
        // deploy a new challenge manager with the OSP's and set it on the rollup
        _deployAndSetChallengeManager(admin, EdgeChallengeManager(_challengeManager(inbox)));

        // ValidatorWalletCreator
        // currently there is no way to set the creator on the rollup
        // todo: put this in nitro config or something

        // UpgradeExecutor
        _upgrade(admin, address(this), "UpgradeExecutor", "");
    }

    function _sequencerInbox(
        address inbox
    ) internal view returns (address) {
        return address(IInbox(inbox).sequencerInbox());
    }

    function _bridge(
        address inbox
    ) internal view returns (address) {
        return address(IInbox(inbox).bridge());
    }

    function _outbox(
        address inbox
    ) internal view returns (address) {
        return IInbox(inbox).bridge().activeOutbox();
    }

    function _rollup(
        address inbox
    ) internal view returns (address) {
        return IOutbox(_outbox(inbox)).rollup();
    }

    function _rollupEventInbox(
        address inbox
    ) internal view returns (address) {
        return address(IRollupCore(_rollup(inbox)).rollupEventInbox());
    }

    function _challengeManager(
        address inbox
    ) internal view returns (address) {
        return address(IRollupCore(_rollup(inbox)).challengeManager());
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

    function _deployAndSetChallengeManager(
        ProxyAdmin proxyAdmin,
        EdgeChallengeManager oldChallengeManager
    ) private {
        address nextImpl =
            nextImplementationsRegistry.getAddressWithArgs("RollupAdminLogic", keccak256(""));
        IOneStepProofEntry nextOsp = _getOspEntry(true);

        {
            IOneStepProofEntry prevOsp = _getOspEntry(false);
            address prevImpl =
                prevImplementationsRegistry.getAddressWithArgs("RollupAdminLogic", keccak256(""));
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
        }

        uint256[] memory stakeAmounts;
        address assertionChain = address(oldChallengeManager.assertionChain());
        {
            uint256 numBigStepLevels = oldChallengeManager.NUM_BIGSTEP_LEVEL();
            stakeAmounts = new uint256[](numBigStepLevels + 2);
            for (uint256 i = 0; i < numBigStepLevels + 2; i++) {
                stakeAmounts[i] = oldChallengeManager.stakeAmounts(i);
            }
        }
        address newChallengeManager = address(
            new TransparentUpgradeableProxy(
                nextImpl,
                address(proxyAdmin),
                abi.encodeCall(
                    IEdgeChallengeManager.initialize,
                    (
                        IAssertionChain(assertionChain), // IAssertionChain _assertionChain,
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

        RollupAdminLogic(assertionChain).setChallengeManager(newChallengeManager);

        emit ChallengeManagerDeployed(
            address(oldChallengeManager), newChallengeManager, nextImpl, address(nextOsp)
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

    function _upgrade(
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
