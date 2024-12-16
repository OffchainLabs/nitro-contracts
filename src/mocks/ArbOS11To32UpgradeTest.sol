// Copyright 2024, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.24;

import "../precompiles/ArbSys.sol";

contract ArbOS11To32UpgradeTest {
    function mcopy() external view {
        require(ArbSys(address(0x64)).arbOSVersion() == 55 + 32, "EXPECTED_ARBOS_32");
    }
}
