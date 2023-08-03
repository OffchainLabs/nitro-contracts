// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./RollupProxy.sol";
import "./IRollupAdmin.sol";
import "./BridgeCreator.sol";
import "./ERC20BridgeCreator.sol";
import "../libraries/UpgradeExecutor.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract RollupCreator is Ownable {
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
        address validatorUtils,
        address validatorWalletCreator
    );
    event TemplatesUpdated();

    BridgeCreator public ethBridgeCreator;
    ERC20BridgeCreator public erc20BridgeCreator;
    IOneStepProofEntry public osp;
    IChallengeManager public challengeManagerTemplate;
    IRollupAdmin public rollupAdminLogic;
    IRollupUser public rollupUserLogic;
    UpgradeExecutor public upgradeExecutorLogic;

    address public validatorUtils;
    address public validatorWalletCreator;

    struct BridgeContracts {
        IBridge bridge;
        ISequencerInbox sequencerInbox;
        IInbox inbox;
        IRollupEventInbox rollupEventInbox;
        IOutbox outbox;
    }

    constructor() Ownable() {}

    function setTemplates(
        BridgeCreator _ethBridgeCreator,
        ERC20BridgeCreator _erc20BridgeCreator,
        IOneStepProofEntry _osp,
        IChallengeManager _challengeManagerLogic,
        IRollupAdmin _rollupAdminLogic,
        IRollupUser _rollupUserLogic,
        UpgradeExecutor _upgradeExecutorLogic,
        address _validatorUtils,
        address _validatorWalletCreator
    ) external onlyOwner {
        ethBridgeCreator = _ethBridgeCreator;
        erc20BridgeCreator = _erc20BridgeCreator;
        osp = _osp;
        challengeManagerTemplate = _challengeManagerLogic;
        rollupAdminLogic = _rollupAdminLogic;
        rollupUserLogic = _rollupUserLogic;
        upgradeExecutorLogic = _upgradeExecutorLogic;
        validatorUtils = _validatorUtils;
        validatorWalletCreator = _validatorWalletCreator;
        emit TemplatesUpdated();
    }

    /**
     * @notice Create a new rollup
     * @dev After this setup:
     * @dev - Rollup should be the owner of bridge
     * @dev - RollupOwner should be the owner of Rollup's ProxyAdmin
     * @dev - RollupOwner should be the owner of Rollup
     * @dev - Bridge should have a single inbox and outbox
     * @dev - Validators and batch poster should be set if provided
     * @param config       The configuration for the rollup
     * @param _batchPoster The address of the batch poster, not used when set to zero address
     * @param _validators  The list of validator addresses, not used when set to empty list
     * @param _nativeToken Address of the custom fee token used by rollup. If rollup is ETH-based address(0) should be provided
     * @return The address of the newly created rollup
     */
    function createRollup(
        Config memory config,
        address _batchPoster,
        address[] calldata _validators,
        address _nativeToken
    ) external returns (address) {
        ProxyAdmin proxyAdmin = new ProxyAdmin();

        // deploy and init upgrade executor
        UpgradeExecutor upgradeExecutor = UpgradeExecutor(
            address(
                new TransparentUpgradeableProxy(
                    address(upgradeExecutorLogic),
                    address(proxyAdmin),
                    bytes("")
                )
            )
        );
        address[] memory executors = new address[](1);
        executors[0] = config.owner;
        upgradeExecutor.initialize(address(upgradeExecutor), executors);

        // Create the rollup proxy to figure out the address and initialize it later
        RollupProxy rollup = new RollupProxy{salt: keccak256(abi.encode(config))}();

        BridgeContracts memory bridgeContracts;
        if (_nativeToken == address(0)) {
            // create ETH-based rollup if address zero is provided for native token
            (
                bridgeContracts.bridge,
                bridgeContracts.sequencerInbox,
                bridgeContracts.inbox,
                bridgeContracts.rollupEventInbox,
                bridgeContracts.outbox
            ) = ethBridgeCreator.createBridge(
                address(proxyAdmin),
                address(rollup),
                config.sequencerInboxMaxTimeVariation
            );
        } else {
            // otherwise create ERC20-based rollup with custom fee token
            (
                bridgeContracts.bridge,
                bridgeContracts.sequencerInbox,
                bridgeContracts.inbox,
                bridgeContracts.rollupEventInbox,
                bridgeContracts.outbox
            ) = erc20BridgeCreator.createBridge(
                address(proxyAdmin),
                address(rollup),
                _nativeToken,
                config.sequencerInboxMaxTimeVariation
            );
        }

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

        proxyAdmin.transferOwnership(address(upgradeExecutor));

        // initialize the rollup with this contract as owner to set batch poster and validators
        // it will transfer the ownership back to the actual owner later
        address actualOwner = config.owner;
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

        IRollupAdmin(address(rollup)).setOwner(actualOwner);

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
            address(validatorUtils),
            address(validatorWalletCreator)
        );
        return address(rollup);
    }
}
