// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/nitro/blob/master/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./IBridgeCreator.sol";
import "./IRollupCreator.sol";
import "./RollupProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract AbsRollupCreator is Ownable, IRollupCreator {
    event RollupCreated(
        address indexed rollupAddress,
        address inboxAddress,
        address adminProxy,
        address sequencerInbox,
        address bridge
    );
    event TemplatesUpdated();

    IBridgeCreator public bridgeCreator;
    IOneStepProofEntry public osp;
    IChallengeManager public challengeManagerTemplate;
    IRollupAdmin public rollupAdminLogic;
    IRollupUser public rollupUserLogic;

    address public validatorUtils;
    address public validatorWalletCreator;

    constructor() Ownable() {}

    function setTemplates(
        IBridgeCreator _bridgeCreator,
        IOneStepProofEntry _osp,
        IChallengeManager _challengeManagerLogic,
        IRollupAdmin _rollupAdminLogic,
        IRollupUser _rollupUserLogic,
        address _validatorUtils,
        address _validatorWalletCreator
    ) external onlyOwner {
        bridgeCreator = _bridgeCreator;
        osp = _osp;
        challengeManagerTemplate = _challengeManagerLogic;
        rollupAdminLogic = _rollupAdminLogic;
        rollupUserLogic = _rollupUserLogic;
        validatorUtils = _validatorUtils;
        validatorWalletCreator = _validatorWalletCreator;
        emit TemplatesUpdated();
    }

    // After this setup:
    // Rollup should be the owner of bridge
    // RollupOwner should be the owner of Rollup's ProxyAdmin
    // RollupOwner should be the owner of Rollup
    // Bridge should have a single inbox and outbox
    function _createRollup(Config memory config, address nativeToken) internal returns (address) {
        ProxyAdmin proxyAdmin = new ProxyAdmin();

        // Create the rollup proxy to figure out the address and initialize it later
        RollupProxy rollup = new RollupProxy{salt: keccak256(abi.encode(config))}();

        (
            IBridge bridge,
            ISequencerInbox sequencerInbox,
            IInbox inbox,
            IRollupEventInbox rollupEventInbox,
            IOutbox outbox
        ) = _createBridge(
                address(proxyAdmin),
                address(rollup),
                config.sequencerInboxMaxTimeVariation,
                nativeToken
            );

        proxyAdmin.transferOwnership(config.owner);

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
            bridge,
            osp
        );

        rollup.initializeProxy(
            config,
            ContractDependencies({
                bridge: bridge,
                sequencerInbox: sequencerInbox,
                inbox: inbox,
                outbox: outbox,
                rollupEventInbox: rollupEventInbox,
                challengeManager: challengeManager,
                rollupAdminLogic: address(rollupAdminLogic),
                rollupUserLogic: rollupUserLogic,
                validatorUtils: validatorUtils,
                validatorWalletCreator: validatorWalletCreator
            })
        );

        emit RollupCreated(
            address(rollup),
            address(inbox),
            address(proxyAdmin),
            address(sequencerInbox),
            address(bridge)
        );
        return address(rollup);
    }

    /**
     * Create bridge using appropriate BridgeCreator.
     */
    function _createBridge(
        address proxyAdmin,
        address rollup,
        ISequencerInbox.MaxTimeVariation memory maxTimeVariation,
        address nativeToken
    )
        internal
        virtual
        returns (
            IBridge,
            SequencerInbox,
            IInbox,
            IRollupEventInbox,
            Outbox
        );
}