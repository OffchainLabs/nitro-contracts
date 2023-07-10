// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/nitro/blob/master/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./AbsRollupCreator.sol";
import "./ERC20BridgeCreator.sol";

contract ERC20RollupCreator is AbsRollupCreator, IERC20RollupCreator {
    constructor() AbsRollupCreator() {}

    // After this setup:
    // Rollup should be the owner of bridge
    // RollupOwner should be the owner of Rollup's ProxyAdmin
    // RollupOwner should be the owner of Rollup
    // Bridge should have a single inbox and outbox
    function createRollup(
        Config memory config,
        address _batchPoster,
        address[] calldata _validators,
        address nativeToken
    ) external override returns (address) {
        return _createRollup(config, _batchPoster, _validators, nativeToken);
    }

    function _createBridge(
        address proxyAdmin,
        address rollup,
        ISequencerInbox.MaxTimeVariation memory maxTimeVariation,
        address nativeToken
    ) internal override returns (BridgeContracts memory) {
        (
            IBridge bridge,
            ISequencerInbox sequencerInbox,
            IInbox inbox,
            IRollupEventInbox rollupEventInbox,
            IOutbox outbox
        ) = ERC20BridgeCreator(address(bridgeCreator)).createBridge(
                proxyAdmin,
                rollup,
                nativeToken,
                maxTimeVariation
            );

        return BridgeContracts(bridge, sequencerInbox, inbox, rollupEventInbox, outbox);
    }
}
