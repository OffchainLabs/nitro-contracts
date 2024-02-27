// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "../bridge/Bridge.sol";
import "../bridge/Inbox.sol";
import "../bridge/Outbox.sol";
import "./RollupEventInbox.sol";
import "../bridge/ERC20Bridge.sol";
import "../bridge/ERC20Inbox.sol";
import "../rollup/ERC20RollupEventInbox.sol";
import "../bridge/ERC20Outbox.sol";
import "./ISequencerInboxCreator.sol";
import "../bridge/DelayBuffer.sol";
import "../bridge/IBridge.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract BridgeCreator is Ownable {
    BridgeTemplates public ethBasedTemplates;
    BridgeTemplates public erc20BasedTemplates;
    ISequencerInboxCreator public sequencerInboxCreator;

    event TemplatesUpdated();
    event ERC20TemplatesUpdated();
    event SequencerInboxCreatorUpdated();

    struct BridgeTemplates {
        IBridge bridge;
        IInboxBase inbox;
        IRollupEventInbox rollupEventInbox;
        IOutbox outbox;
    }

    struct BridgeContracts {
        IBridge bridge;
        ISequencerInbox sequencerInbox;
        IInboxBase inbox;
        IRollupEventInbox rollupEventInbox;
        IOutbox outbox;
    }

    constructor(
        BridgeTemplates memory _ethBasedTemplates,
        BridgeTemplates memory _erc20BasedTemplates,
        ISequencerInboxCreator _sequencerInboxCreator
    ) Ownable() {
        ethBasedTemplates = _ethBasedTemplates;
        erc20BasedTemplates = _erc20BasedTemplates;
        sequencerInboxCreator = _sequencerInboxCreator;
    }

    function updateSequencerInboxCreator(ISequencerInboxCreator _sequencerInboxCreator)
        external
        onlyOwner
    {
        sequencerInboxCreator = _sequencerInboxCreator;
        emit SequencerInboxCreatorUpdated();
    }

    function updateTemplates(BridgeTemplates calldata _newTemplates) external onlyOwner {
        ethBasedTemplates = _newTemplates;
        emit TemplatesUpdated();
    }

    function updateERC20Templates(BridgeTemplates calldata _newTemplates) external onlyOwner {
        erc20BasedTemplates = _newTemplates;
        emit ERC20TemplatesUpdated();
    }

    function _createBridge(address adminProxy, BridgeTemplates storage templates)
        internal
        returns (BridgeContracts memory)
    {
        BridgeContracts memory frame;
        frame.bridge = IBridge(
            address(new TransparentUpgradeableProxy(address(templates.bridge), adminProxy, ""))
        );
        frame.inbox = IInboxBase(
            address(new TransparentUpgradeableProxy(address(templates.inbox), adminProxy, ""))
        );
        frame.rollupEventInbox = IRollupEventInbox(
            address(
                new TransparentUpgradeableProxy(address(templates.rollupEventInbox), adminProxy, "")
            )
        );
        frame.outbox = IOutbox(
            address(new TransparentUpgradeableProxy(address(templates.outbox), adminProxy, ""))
        );
        return frame;
    }

    function createBridge(
        address adminProxy,
        address rollup,
        address nativeToken,
        ISequencerInbox.MaxTimeVariation calldata maxTimeVariation,
        IDelayBufferable.ReplenishRate memory replenishRate,
        IDelayBufferable.Config memory config,
        uint256 maxDataSize
    ) external returns (BridgeContracts memory) {
        bool isUsingFeeToken = nativeToken != address(0);
        // create ETH-based bridge if address zero is provided for native token, otherwise create ERC20-based bridge
        BridgeContracts memory frame = _createBridge(
            adminProxy,
            isUsingFeeToken ? erc20BasedTemplates : ethBasedTemplates
        );

        // init contracts
        if (isUsingFeeToken) {
            IERC20Bridge(address(frame.bridge)).initialize(IOwnable(rollup), nativeToken);
        } else {
            IEthBridge(address(frame.bridge)).initialize(IOwnable(rollup));
        }

        frame.sequencerInbox = sequencerInboxCreator.createSequencerInbox(
            IBridge(frame.bridge),
            maxTimeVariation,
            replenishRate,
            config,
            maxDataSize,
            isUsingFeeToken
        );
        frame.inbox.initialize(frame.bridge, frame.sequencerInbox);
        frame.rollupEventInbox.initialize(frame.bridge);
        frame.outbox.initialize(frame.bridge);

        return frame;
    }
}
