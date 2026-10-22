// Copyright 2021-2026, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./IContractVersion.sol";

// major * 1e6 + minor * 1e3 + patch, so 3_002_000 reads as 3.2.0 on an explorer
uint256 constant NITRO_CONTRACT_VERSION = 3_002_000;

abstract contract ContractVersion is IContractVersion {
    function nitroContractVersion() external pure returns (uint256) {
        return NITRO_CONTRACT_VERSION;
    }
}
