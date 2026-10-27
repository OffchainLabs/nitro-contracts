// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./LegacyAssertion.sol";

/// @notice Legacy config hashing for assertions created before MEL.
library LegacyRollupLib {
    function legacyConfigHash(
        bytes32 wasmModuleRoot,
        uint256 requiredStake,
        address challengeManager,
        uint64 confirmPeriodBlocks,
        uint64 nextInboxPosition
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                wasmModuleRoot,
                requiredStake,
                challengeManager,
                confirmPeriodBlocks,
                nextInboxPosition
            )
        );
    }

    function validateConfigHash(
        LegacyConfigData calldata configData,
        bytes32 _configHash
    ) internal pure {
        require(
            _configHash
                == legacyConfigHash(
                    configData.wasmModuleRoot,
                    configData.requiredStake,
                    configData.challengeManager,
                    configData.confirmPeriodBlocks,
                    configData.nextInboxPosition
                ),
            "CONFIG_HASH_MISMATCH"
        );
    }
}
