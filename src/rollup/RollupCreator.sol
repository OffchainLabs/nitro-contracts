// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./BridgeCreator.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./RollupProxy.sol";
import "./IRollupAdmin.sol";

contract RollupCreator is Ownable {
    event RollupCreated(
        address indexed rollupAddress,
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

    BridgeCreator public bridgeCreator;
    IOneStepProofEntry public osp;
    IChallengeManager public challengeManagerTemplate;
    IRollupAdmin public rollupAdminLogic;
    IRollupUser public rollupUserLogic;

    address public validatorUtils;
    address public validatorWalletCreator;

    constructor() Ownable() {}

    function setTemplates(
        BridgeCreator _bridgeCreator,
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
     * @return The address of the newly created rollup
     */
    function createRollup(
        Config memory config,
        address _batchPoster,
        address[] calldata _validators
    ) external returns (address) {
        ProxyAdmin proxyAdmin = new ProxyAdmin();

        // Create the rollup proxy to figure out the address and initialize it later
        RollupProxy rollup = new RollupProxy{salt: keccak256(abi.encode(config))}();

        (
            IBridge bridge,
            ISequencerInbox sequencerInbox,
            IInbox inbox,
            IRollupEventInbox rollupEventInbox,
            IOutbox outbox
        ) = bridgeCreator.createBridge(
                address(proxyAdmin),
                address(rollup),
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
            sequencerInbox,
            bridge,
            osp
        );

        proxyAdmin.transferOwnership(config.owner);

        // initialize the rollup with this contract as owner to set batch poster and validators
        // it will transfer the ownership back to the actual owner later
        address actualOwner = config.owner;
        config.owner = address(this);
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

        // setting batch poster, if the address provided is not zero address
        if (_batchPoster != address(0)) {
            sequencerInbox.setIsBatchPoster(_batchPoster, true);
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
            address(inbox),
            address(outbox),
            address(rollupEventInbox),
            address(challengeManager),
            address(proxyAdmin),
            address(sequencerInbox),
            address(bridge),
            address(validatorUtils),
            address(validatorWalletCreator)
        );
        return address(rollup);
    }
}
