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
import "./IRollupCreator.sol";

contract RollupCreator is Ownable, IRollupCreator {
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
     * @param rollupParams The parameters for the rollup deployment. It consists of:
     *          - config        The configuration for the rollup
     *          - batchPoster   The address of the batch poster, not used when set to zero address
     *          - validators    The list of validator addresses, not used when set to empty list
     *          - nativeToken   Address of the custom fee token used by rollup. If rollup is ETH-based address(0) should be provided
     *          - deployFactoriesToL2 Whether to deploy L2 factories using retryable tickets. If true, retryables need to be paid for in native currency.
     *                          Deploying factories via retryable tickets at rollup creation time is the most reliable method to do it since it
     *                          doesn't require paying the L1 gas. If deployment is not done as part of rollup creation TX, there is a risk that
     *                          anyone can try to deploy factories and potentially burn the nonce 0 (ie. due to gas price spike when doing direct
     *                          L2 TX). That would mean we permanently lost capability to deploy deterministic factory at expected address.
     *          - maxFeePerGasForRetryables price bid for L2 execution.
     *          - dataHashReader The address of the data hash reader used to read blob hashes
     * @param nonce The nonce to use for the rollup deployment
     * @param sequencerInbox The address of the sequencer inbox
     * @return The address of the newly created rollup
     */
    function createRollup(
        RollupParams memory rollupParams,
        uint256 nonce,
        ISequencerInbox sequencerInbox
    ) public payable returns (address) {
        // Make sure the immutable maxDataSize is as expected
        (, IInboxBase ethInbox, , ) = bridgeCreator.ethBasedTemplates();
        require(rollupParams.maxDataSize == ethInbox.maxDataSize(), "I_MAX_DATA_SIZE_MISMATCH");

        (, IInboxBase erc20Inbox, , ) = bridgeCreator.erc20BasedTemplates();
        require(rollupParams.maxDataSize == erc20Inbox.maxDataSize(), "I_MAX_DATA_SIZE_MISMATCH");

        bytes32 _salt = salt(rollupParams, nonce);

        // create proxy admin which will manage bridge contracts
        ProxyAdmin proxyAdmin = new ProxyAdmin{salt: _salt}();

        // Create the rollup proxy to figure out the address and initialize it later
        RollupProxy rollup = new RollupProxy{salt: _salt}();

        BridgeCreator.BridgeContracts memory bridgeContracts = bridgeCreator.createBridge(
            _salt,
            sequencerInbox,
            address(proxyAdmin),
            address(rollup),
            rollupParams.nativeToken
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
            sequencerInbox,
            bridgeContracts.bridge,
            osp
        );

        // deploy and init upgrade executor
        address upgradeExecutor = _deployUpgradeExecutor(rollupParams.config.owner, proxyAdmin);

        // upgradeExecutor shall be proxyAdmin's owner
        proxyAdmin.transferOwnership(address(upgradeExecutor));

        // initialize the rollup with this contract as owner to set batch poster and validators
        // it will transfer the ownership to the upgrade executor later
        rollupParams.config.owner = address(this);
        rollup.initializeProxy(
            rollupParams.config,
            ContractDependencies({
                bridge: bridgeContracts.bridge,
                sequencerInbox: sequencerInbox,
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

        // Setting batch posters and batch poster manager
        for (uint256 i = 0; i < rollupParams.batchPosters.length; i++) {
            sequencerInbox.setIsBatchPoster(rollupParams.batchPosters[i], true);
        }
        if (rollupParams.batchPosterManager != address(0)) {
            sequencerInbox.setBatchPosterManager(rollupParams.batchPosterManager);
        }

        // Call setValidator on the newly created rollup contract just if validator set is not empty
        if (rollupParams.validators.length != 0) {
            bool[] memory _vals = new bool[](rollupParams.validators.length);
            for (uint256 i = 0; i < rollupParams.validators.length; i++) {
                _vals[i] = true;
            }
            IRollupAdmin(address(rollup)).setValidator(rollupParams.validators, _vals);
        }

        IRollupAdmin(address(rollup)).setOwner(address(upgradeExecutor));

        if (rollupParams.deployFactoriesToL2) {
            _deployFactories(
                address(bridgeContracts.inbox),
                rollupParams.nativeToken,
                rollupParams.maxFeePerGasForRetryables
            );
        }

        address sequencerInbox_ = address(sequencerInbox);

        emit RollupCreated(
            address(rollup),
            rollupParams.nativeToken,
            address(bridgeContracts.inbox),
            address(bridgeContracts.outbox),
            address(bridgeContracts.rollupEventInbox),
            address(challengeManager),
            address(proxyAdmin),
            address(sequencerInbox_),
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

    function computeProxyAdminAddress(RollupParams calldata rollupParams, uint256 nonce)
        external
        view
        returns (address)
    {
        return
            computeCreate2Address(
                address(this),
                salt(rollupParams, nonce),
                type(ProxyAdmin).creationCode,
                ""
            );
    }

    function computeRollupProxyAddress(RollupParams calldata rollupParams, uint256 nonce)
        external
        view
        returns (address)
    {
        return
            computeCreate2Address(
                address(this),
                salt(rollupParams, nonce),
                type(RollupProxy).creationCode,
                ""
            );
    }

    function salt(RollupParams memory rollupParams, uint256 nonce) internal pure returns (bytes32) {
        return keccak256(abi.encode(rollupParams, nonce));
    }

    function computeCreate2Address(
        address deployer,
        bytes32 _salt,
        bytes memory creationCode,
        bytes memory args
    ) internal pure returns (address) {
        return
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                bytes1(0xff),
                                deployer,
                                _salt,
                                keccak256(abi.encodePacked(creationCode, args))
                            )
                        )
                    )
                )
            );
    }
}
