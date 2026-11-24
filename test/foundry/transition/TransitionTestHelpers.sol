// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../../../src/rollup/transition/RollupAdminLogicTransitional.sol";

/// @notice No admin entrypoint can rewrite an assertion's config hash, so tests use this to give an
///         existing assertion the pre-MEL shape a live chain would have at upgrade time.
contract RollupAdminLogicTransitionalTestHelper is RollupAdminLogicTransitional {
    function setConfigHash(
        bytes32 assertionHash,
        bytes32 configHash
    ) external {
        getAssertionStorage(assertionHash).configHash = configHash;
    }
}
