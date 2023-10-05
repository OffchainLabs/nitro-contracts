// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./RollupProxy.sol";
import "./IRollupAdmin.sol";
import "./BridgeCreator.sol";
import "@offchainlabs/upgrade-executor/src/IUpgradeExecutor.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {DeployHelper} from "./DeployHelper.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RollupCreator is Ownable {
    using SafeERC20 for IERC20;

    event RollupCreated(
        address indexed rollupAddress,
        address indexed nativeToken,
        address inboxAddress,
        address outbox,
        address rollupEventInbox,
        address challengeManager,
        address adminProxy,
        address sequencerInbox,
        address bridge,
        address upgradeExecutor,
        address validatorUtils,
        address validatorWalletCreator
    );
    event TemplatesUpdated();

    BridgeCreator public bridgeCreator;
    IOneStepProofEntry public osp;
    IChallengeManager public challengeManagerTemplate;
    IRollupAdmin public rollupAdminLogic;
    IRollupUser public rollupUserLogic;
    IUpgradeExecutor public upgradeExecutorLogic;

    address public validatorUtils;
    address public validatorWalletCreator;

    DeployHelper public l2FactoriesDeployer;

    struct BridgeContracts {
        IBridge bridge;
        ISequencerInbox sequencerInbox;
        IInboxBase inbox;
        IRollupEventInbox rollupEventInbox;
        IOutbox outbox;
    }

    constructor() Ownable() {}

    // creator receives back excess fees (for deploying L2 factories) so it can refund the caller
    receive() external payable {}

    function setTemplates(
        BridgeCreator _bridgeCreator,
        IOneStepProofEntry _osp,
        IChallengeManager _challengeManagerLogic,
        IRollupAdmin _rollupAdminLogic,
        IRollupUser _rollupUserLogic,
        IUpgradeExecutor _upgradeExecutorLogic,
        address _validatorUtils,
        address _validatorWalletCreator,
        DeployHelper _l2FactoriesDeployer
    ) external onlyOwner {
        bridgeCreator = _bridgeCreator;
        osp = _osp;
        challengeManagerTemplate = _challengeManagerLogic;
        rollupAdminLogic = _rollupAdminLogic;
        rollupUserLogic = _rollupUserLogic;
        upgradeExecutorLogic = _upgradeExecutorLogic;
        validatorUtils = _validatorUtils;
        validatorWalletCreator = _validatorWalletCreator;
        l2FactoriesDeployer = _l2FactoriesDeployer;
        emit TemplatesUpdated();
    }

    /**
     * @notice Create a new rollup
     * @dev After this setup:
     * @dev - UpgradeExecutor should be the owner of rollup
     * @dev - UpgradeExecutor should be the owner of proxyAdmin which manages bridge contracts
     * @dev - config.rollupOwner should have executor role on upgradeExecutor
     * @dev - Bridge should have a single inbox and outbox
     * @dev - Validators and batch poster should be set if provided
     * @param config       The configuration for the rollup
     * @param _batchPoster The address of the batch poster, not used when set to zero address
     * @param _validators  The list of validator addresses, not used when set to empty list
     * @param _nativeToken Address of the custom fee token used by rollup. If rollup is ETH-based address(0) should be provided
     * @param _deployFactoriesToL2 Whether to deploy L2 factories using retryable tickets. If true, retryables need to be paid for in native currency.
     *                             Deploying factories via retryable tickets at rollup creation time is the most reliable method to do it since it
     *                             doesn't require paying the L1 gas. If deployment is not done as part of rollup creation TX, there is a risk that
     *                             anyone can try to deploy factories and potentially burn the nonce 0 (ie. due to gas price spike when doing direct
     *                             L2 TX). That would mean we permanently lost capability to deploy deterministic factory at expected address.
     * @param _maxFeePerGasForRetryables price bid for L2 execution.
     * @return The address of the newly created rollup
     */
    function createRollup(
        Config memory config,
        address _batchPoster,
        address[] memory _validators,
        uint256 _maxDataSize,
        address _nativeToken,
        bool _deployFactoriesToL2,
        uint256 _maxFeePerGasForRetryables
    ) public payable returns (address) {
        {
            // Make sure the immutable maxDataSize is as expected
            (, ISequencerInbox ethSequencerInbox, IInboxBase ethInbox, , ) = bridgeCreator
                .ethBasedTemplates();
            require(_maxDataSize == ethSequencerInbox.maxDataSize(), "SI_MAX_DATA_SIZE_MISMATCH");
            require(_maxDataSize == ethInbox.maxDataSize(), "I_MAX_DATA_SIZE_MISMATCH");

            (, ISequencerInbox erc20SequencerInbox, IInboxBase erc20Inbox, , ) = bridgeCreator
                .erc20BasedTemplates();
            require(_maxDataSize == erc20SequencerInbox.maxDataSize(), "SI_MAX_DATA_SIZE_MISMATCH");
            require(_maxDataSize == erc20Inbox.maxDataSize(), "I_MAX_DATA_SIZE_MISMATCH");
        }

        // create proxy admin which will manage bridge contracts
        ProxyAdmin proxyAdmin = new ProxyAdmin();

        // Create the rollup proxy to figure out the address and initialize it later
        RollupProxy rollup = new RollupProxy{salt: keccak256(abi.encode(config))}();

        BridgeContracts memory bridgeContracts;
        (
            bridgeContracts.bridge,
            bridgeContracts.sequencerInbox,
            bridgeContracts.inbox,
            bridgeContracts.rollupEventInbox,
            bridgeContracts.outbox
        ) = bridgeCreator.createBridge(
            address(proxyAdmin),
            address(rollup),
            _nativeToken,
            config.sequencerInboxMaxTimeVariation
        );

        IChallengeManager challengeManager = IChallengeManager(
            address(
                new TransparentUpgradeableProxy(
                    address(challengeManagerTemplate),
                    address(proxyAdmin),
                    ""
                )
            )
        );
        challengeManager.initialize(
            IChallengeResultReceiver(address(rollup)),
            bridgeContracts.sequencerInbox,
            bridgeContracts.bridge,
            osp
        );

        // deploy and init upgrade executor
        address upgradeExecutor = _deployUpgradeExecutor(config.owner, proxyAdmin);

        // upgradeExecutor shall be proxyAdmin's owner
        proxyAdmin.transferOwnership(address(upgradeExecutor));

        // initialize the rollup with this contract as owner to set batch poster and validators
        // it will transfer the ownership to the upgrade executor later
        config.owner = address(this);
        rollup.initializeProxy(
            config,
            ContractDependencies({
                bridge: bridgeContracts.bridge,
                sequencerInbox: bridgeContracts.sequencerInbox,
                inbox: bridgeContracts.inbox,
                outbox: bridgeContracts.outbox,
                rollupEventInbox: bridgeContracts.rollupEventInbox,
                challengeManager: challengeManager,
                rollupAdminLogic: address(rollupAdminLogic),
                rollupUserLogic: rollupUserLogic,
                validatorUtils: validatorUtils,
                validatorWalletCreator: validatorWalletCreator
            })
        );

        // setting batch poster, if the address provided is not zero address
        if (_batchPoster != address(0)) {
            bridgeContracts.sequencerInbox.setIsBatchPoster(_batchPoster, true);
        }

        // Call setValidator on the newly created rollup contract just if validator set is not empty
        if (_validators.length != 0) {
            bool[] memory _vals = new bool[](_validators.length);
            for (uint256 i = 0; i < _validators.length; i++) {
                _vals[i] = true;
            }
            IRollupAdmin(address(rollup)).setValidator(_validators, _vals);
        }

        IRollupAdmin(address(rollup)).setOwner(address(upgradeExecutor));

        if (_deployFactoriesToL2) {
            _deployFactories(
                address(bridgeContracts.inbox),
                _nativeToken,
                _maxFeePerGasForRetryables
            );
        }

        emit RollupCreated(
            address(rollup),
            _nativeToken,
            address(bridgeContracts.inbox),
            address(bridgeContracts.outbox),
            address(bridgeContracts.rollupEventInbox),
            address(challengeManager),
            address(proxyAdmin),
            address(bridgeContracts.sequencerInbox),
            address(bridgeContracts.bridge),
            address(upgradeExecutor),
            address(validatorUtils),
            address(validatorWalletCreator)
        );
        return address(rollup);
    }

    function _deployUpgradeExecutor(address rollupOwner, ProxyAdmin proxyAdmin)
        internal
        returns (address)
    {
        IUpgradeExecutor upgradeExecutor = IUpgradeExecutor(
            address(
                new TransparentUpgradeableProxy(
                    address(upgradeExecutorLogic),
                    address(proxyAdmin),
                    bytes("")
                )
            )
        );
        address[] memory executors = new address[](1);
        executors[0] = rollupOwner;
        upgradeExecutor.initialize(address(upgradeExecutor), executors);

        return address(upgradeExecutor);
    }

    function _deployFactories(
        address _inbox,
        address _nativeToken,
        uint256 _maxFeePerGas
    ) internal {
        if (_nativeToken == address(0)) {
            // we need to fund 4 retryable tickets
            uint256 cost = l2FactoriesDeployer.getDeploymentTotalCost(
                IInboxBase(_inbox),
                _maxFeePerGas
            );

            // do it
            l2FactoriesDeployer.perform{value: cost}(_inbox, _nativeToken, _maxFeePerGas);

            // refund the caller
            (bool sent, ) = msg.sender.call{value: address(this).balance}("");
            require(sent, "Refund failed");
        } else {
            // Transfer fee token amount needed to pay for retryable fees to the inbox.
            uint256 totalFee = l2FactoriesDeployer.getDeploymentTotalCost(
                IInboxBase(_inbox),
                _maxFeePerGas
            );
            IERC20(_nativeToken).safeTransferFrom(msg.sender, _inbox, totalFee);

            // do it
            l2FactoriesDeployer.perform(_inbox, _nativeToken, _maxFeePerGas);
        }
    }
}
