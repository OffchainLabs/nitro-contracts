// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "../AssertionState.sol";

// Legacy configuration data structure for pre-MEL assertions
struct LegacyConfigData {
    bytes32 wasmModuleRoot;
    uint256 requiredStake;
    address challengeManager;
    uint64 confirmPeriodBlocks;
    uint64 nextInboxPosition;
}

struct LegacyBeforeStateData {
    // The assertion hash of the prev of the beforeState(prev)
    bytes32 prevPrevAssertionHash;
    // The sequencer inbox accumulator asserted by the beforeState(prev)
    bytes32 sequencerBatchAcc;
    // below are the components of config hash
    LegacyConfigData configData;
}

struct LegacyAssertionInputs {
    // Additional data used to validate the before state
    LegacyBeforeStateData beforeStateData;
    AssertionState beforeState;
    AssertionState afterState;
}
