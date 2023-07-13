// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./AbsRollupCreator.sol";
import "./BridgeCreator.sol";

contract RollupCreator is AbsRollupCreator, IEthRollupCreator {
    constructor() AbsRollupCreator() {}

    /**
     * @notice Create a new rollup
     * @param  config       The configuration for the rollup
     * @param  _batchPoster The address of the batch poster, not used when set to zero address
     * @param  _validators  The list of validator addresses, not used when set to empty list
     * @return The address of the newly created rollup
     */
    function createRollup(
        Config memory config,
        address _batchPoster,
        address[] calldata _validators
    ) external override returns (address) {
        return _createRollup(config, _batchPoster, _validators, address(0));
    }

    function _createBridge(
        address proxyAdmin,
        address rollup,
        ISequencerInbox.MaxTimeVariation memory maxTimeVariation,
        address // nativeToken does not exist in context of standard Eth based rollup
    ) internal override returns (BridgeContracts memory) {
        (
            IBridge bridge,
            ISequencerInbox sequencerInbox,
            IInbox inbox,
            IRollupEventInbox rollupEventInbox,
            IOutbox outbox
        ) = BridgeCreator(address(bridgeCreator)).createBridge(
                proxyAdmin,
                rollup,
                maxTimeVariation
            );

        return BridgeContracts(bridge, sequencerInbox, inbox, rollupEventInbox, outbox);
    }
}
