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
import "../bridge/IDelayBufferable.sol";
import "../bridge/IBridge.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "./IRollupCreator.sol";

contract BridgeCreator is Ownable {
    BridgeTemplates public ethBasedTemplates;
    BridgeTemplates public erc20BasedTemplates;
    address public rollupCreator;

    event TemplatesUpdated();
    event ERC20TemplatesUpdated();
    event RollupCreatorCreatorUpdated();

    struct BridgeTemplates {
        IBridge bridge;
        IInboxBase inbox;
        IRollupEventInbox rollupEventInbox;
        IOutbox outbox;
    }

    struct BridgeContracts {
        IBridge bridge;
        IInboxBase inbox;
        IRollupEventInbox rollupEventInbox;
        IOutbox outbox;
    }

    constructor(
        BridgeTemplates memory _ethBasedTemplates,
        BridgeTemplates memory _erc20BasedTemplates,
        address _rollupCreator
    ) Ownable() {
        ethBasedTemplates = _ethBasedTemplates;
        erc20BasedTemplates = _erc20BasedTemplates;
        rollupCreator = _rollupCreator;
    }

    function updateRollupCreator(address _rollupCreator) external onlyOwner {
        rollupCreator = _rollupCreator;
        emit RollupCreatorCreatorUpdated();
    }

    function updateTemplates(BridgeTemplates calldata _newTemplates) external onlyOwner {
        ethBasedTemplates = _newTemplates;
        emit TemplatesUpdated();
    }

    function updateERC20Templates(BridgeTemplates calldata _newTemplates) external onlyOwner {
        erc20BasedTemplates = _newTemplates;
        emit ERC20TemplatesUpdated();
    }

    function _createBridge(
        bytes32 _salt,
        address adminProxy,
        BridgeTemplates storage templates
    ) internal returns (BridgeContracts memory) {
        BridgeContracts memory frame;
        frame.bridge = IBridge(
            address(
                new TransparentUpgradeableProxy{salt: _salt}(
                    address(templates.bridge),
                    adminProxy,
                    ""
                )
            )
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
        bytes32 _salt,
        ISequencerInbox sequencerInbox,
        address adminProxy,
        address rollup,
        address nativeToken
    ) external returns (BridgeContracts memory) {
        bool isUsingFeeToken = nativeToken != address(0);
        // create ETH-based bridge if address zero is provided for native token, otherwise create ERC20-based bridge
        BridgeContracts memory frame = _createBridge(
            _salt,
            adminProxy,
            isUsingFeeToken ? erc20BasedTemplates : ethBasedTemplates
        );

        // init contracts
        if (isUsingFeeToken) {
            IERC20Bridge(address(frame.bridge)).initialize(IOwnable(rollup), nativeToken);
        } else {
            IEthBridge(address(frame.bridge)).initialize(IOwnable(rollup));
        }

        frame.inbox.initialize(frame.bridge, sequencerInbox);
        frame.rollupEventInbox.initialize(frame.bridge);
        frame.outbox.initialize(frame.bridge);

        return frame;
    }

    function computeBridgeAddresss(IRollupCreator.RollupParams memory rollupParams, uint256 nonce)
        public
        view
        returns (address)
    {
        bytes32 _salt = salt(rollupParams, nonce);
        address proxyAdmin = computeCreate2Address(
            rollupCreator,
            _salt,
            type(ProxyAdmin).creationCode,
            ""
        );
        bool isUsingFeeToken = rollupParams.nativeToken != address(0);
        return computeBridgeAddress(isUsingFeeToken, proxyAdmin, _salt);
    }

    function computeBridgeAddress(
        bool isUsingFeeToken,
        address proxyAdmin,
        bytes32 _salt
    ) public view returns (address) {
        BridgeTemplates memory templates = isUsingFeeToken
            ? erc20BasedTemplates
            : ethBasedTemplates;
        return
            computeCreate2Address(
                address(this),
                _salt,
                type(TransparentUpgradeableProxy).creationCode,
                abi.encode(templates.bridge, proxyAdmin, "")
            );
    }

    function salt(IRollupCreator.RollupParams memory rollupParams, uint256 nonce)
        internal
        pure
        returns (bytes32)
    {
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
