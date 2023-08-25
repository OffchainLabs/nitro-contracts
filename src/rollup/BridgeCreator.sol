// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "../bridge/Bridge.sol";
import "../bridge/SequencerInbox.sol";
import "../bridge/ISequencerInbox.sol";
import "../bridge/Inbox.sol";
import "../bridge/Outbox.sol";
import "./RollupEventInbox.sol";
import "../bridge/ERC20Bridge.sol";
import "../bridge/ERC20Inbox.sol";
import "../rollup/ERC20RollupEventInbox.sol";
import "../bridge/ERC20Outbox.sol";

import "../bridge/IBridge.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract BridgeCreator is Ownable {
    ContractTemplates public ethBasedTemplates;
    ContractERC20Templates public erc20BasedTemplates;

    event TemplatesUpdated();
    event ERC20TemplatesUpdated();

    struct ContractTemplates {
        Bridge bridge;
        SequencerInbox sequencerInbox;
        Inbox inbox;
        RollupEventInbox rollupEventInbox;
        Outbox outbox;
    }

    struct ContractERC20Templates {
        ERC20Bridge bridge;
        SequencerInbox sequencerInbox;
        ERC20Inbox inbox;
        ERC20RollupEventInbox rollupEventInbox;
        ERC20Outbox outbox;
    }

    struct CreateBridgeFrame {
        ProxyAdmin admin;
        IBridge bridge;
        SequencerInbox sequencerInbox;
        IInboxBase inbox;
        IRollupEventInbox rollupEventInbox;
        Outbox outbox;
    }

    constructor() Ownable() {
        SequencerInbox seqInbox = new SequencerInbox();

        ethBasedTemplates.bridge = new Bridge();
        ethBasedTemplates.sequencerInbox = seqInbox;
        ethBasedTemplates.inbox = new Inbox();
        ethBasedTemplates.rollupEventInbox = new RollupEventInbox();
        ethBasedTemplates.outbox = new Outbox();

        erc20BasedTemplates.bridge = new ERC20Bridge();
        erc20BasedTemplates.sequencerInbox = seqInbox;
        erc20BasedTemplates.inbox = new ERC20Inbox();
        erc20BasedTemplates.rollupEventInbox = new ERC20RollupEventInbox();
        erc20BasedTemplates.outbox = new ERC20Outbox();
    }

    function updateTemplates(ContractTemplates calldata _newTemplates) external onlyOwner {
        ethBasedTemplates = _newTemplates;
        emit TemplatesUpdated();
    }

    function updateERC20Templates(ContractERC20Templates calldata _newTemplates)
        external
        onlyOwner
    {
        erc20BasedTemplates = _newTemplates;
        emit ERC20TemplatesUpdated();
    }

    function createBridge(
        address adminProxy,
        address rollup,
        address nativeToken,
        ISequencerInbox.MaxTimeVariation memory maxTimeVariation
    )
        external
        returns (
            IBridge,
            SequencerInbox,
            IInboxBase,
            IRollupEventInbox,
            Outbox
        )
    {
        CreateBridgeFrame memory frame;

        // create ETH-based bridge if address zero is provided for native token, otherwise create ERC20-based bridge
        if (nativeToken == address(0)) {
            frame.bridge = Bridge(
                address(
                    new TransparentUpgradeableProxy(
                        address(ethBasedTemplates.bridge),
                        adminProxy,
                        ""
                    )
                )
            );
            frame.sequencerInbox = SequencerInbox(
                address(
                    new TransparentUpgradeableProxy(
                        address(ethBasedTemplates.sequencerInbox),
                        adminProxy,
                        ""
                    )
                )
            );
            frame.inbox = Inbox(
                address(
                    new TransparentUpgradeableProxy(
                        address(ethBasedTemplates.inbox),
                        adminProxy,
                        ""
                    )
                )
            );
            frame.rollupEventInbox = RollupEventInbox(
                address(
                    new TransparentUpgradeableProxy(
                        address(ethBasedTemplates.rollupEventInbox),
                        adminProxy,
                        ""
                    )
                )
            );
            frame.outbox = Outbox(
                address(
                    new TransparentUpgradeableProxy(
                        address(ethBasedTemplates.outbox),
                        adminProxy,
                        ""
                    )
                )
            );
        } else {
            frame.bridge = Bridge(
                address(
                    new TransparentUpgradeableProxy(
                        address(erc20BasedTemplates.bridge),
                        adminProxy,
                        ""
                    )
                )
            );
            frame.sequencerInbox = SequencerInbox(
                address(
                    new TransparentUpgradeableProxy(
                        address(erc20BasedTemplates.sequencerInbox),
                        adminProxy,
                        ""
                    )
                )
            );
            frame.inbox = Inbox(
                address(
                    new TransparentUpgradeableProxy(
                        address(erc20BasedTemplates.inbox),
                        adminProxy,
                        ""
                    )
                )
            );
            frame.rollupEventInbox = RollupEventInbox(
                address(
                    new TransparentUpgradeableProxy(
                        address(erc20BasedTemplates.rollupEventInbox),
                        adminProxy,
                        ""
                    )
                )
            );
            frame.outbox = Outbox(
                address(
                    new TransparentUpgradeableProxy(
                        address(erc20BasedTemplates.outbox),
                        adminProxy,
                        ""
                    )
                )
            );
        }

        // init contracts
        if (nativeToken == address(0)) {
            IEthBridge(address(frame.bridge)).initialize(IOwnable(rollup));
        } else {
            IERC20Bridge(address(frame.bridge)).initialize(IOwnable(rollup), nativeToken);
        }
        frame.sequencerInbox.initialize(IBridge(frame.bridge), maxTimeVariation);
        frame.inbox.initialize(IBridge(frame.bridge), ISequencerInbox(frame.sequencerInbox));
        frame.rollupEventInbox.initialize(IBridge(frame.bridge));
        frame.outbox.initialize(IBridge(frame.bridge));

        return (
            frame.bridge,
            frame.sequencerInbox,
            frame.inbox,
            frame.rollupEventInbox,
            frame.outbox
        );
    }
}
