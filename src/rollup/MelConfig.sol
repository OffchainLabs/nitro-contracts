// Copyright 2021-2026, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./IMelConfig.sol";

contract MelConfig is IMelConfig {
    uint256 public version; // slot 0
    address public bridge; // slot 1

    error AlreadyInitialized();
    error ZeroVersion();

    function initialize(
        uint256 _version,
        address _bridge
    ) external override {
        if (bridge != address(0)) {
            revert AlreadyInitialized();
        }
        // MEL versions start at 1 so that 0 always means unset
        if (_version == 0) {
            revert ZeroVersion();
        }

        version = _version;
        bridge = _bridge;
    }
}
