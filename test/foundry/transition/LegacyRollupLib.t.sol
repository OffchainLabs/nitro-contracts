// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../challengeV2/Utils.sol";
import "../../../src/rollup/transition/LegacyRollupLib.sol";

contract LegacyRollupLibTest is Test {
    Random public rand = new Random();
    LegacyConfigData public config;
    bytes32 public configHash;

    function setUp() public {
        config = LegacyConfigData({
            wasmModuleRoot: rand.hash(),
            requiredStake: uint256(rand.hash()),
            challengeManager: rand.addr(),
            confirmPeriodBlocks: uint64(uint256(rand.hash())),
            nextInboxPosition: uint64(uint256(rand.hash()))
        });
        configHash = keccak256(
            abi.encodePacked(
                config.wasmModuleRoot,
                config.requiredStake,
                config.challengeManager,
                config.confirmPeriodBlocks,
                config.nextInboxPosition
            )
        );
    }

    function _validateConfigHash(
        LegacyConfigData calldata configData,
        bytes32 expectedHash
    ) external pure {
        LegacyRollupLib.validateConfigHash(configData, expectedHash);
    }

    function testLegacyConfigHashMatchesPreMelFormula() public {
        assertEq(
            LegacyRollupLib.legacyConfigHash(
                config.wasmModuleRoot,
                config.requiredStake,
                config.challengeManager,
                config.confirmPeriodBlocks,
                config.nextInboxPosition
            ),
            configHash
        );
    }

    function testValidateConfigHashAccepts() public view {
        this._validateConfigHash(config, configHash);
    }

    function testValidateConfigHashRejectsEachFieldChange() public {
        LegacyConfigData memory mutated = config;
        mutated.wasmModuleRoot = bytes32(uint256(2));
        _expectMismatch(mutated);

        mutated = config;
        mutated.requiredStake += 1;
        _expectMismatch(mutated);

        mutated = config;
        mutated.challengeManager = address(0xbb);
        _expectMismatch(mutated);

        mutated = config;
        mutated.confirmPeriodBlocks += 1;
        _expectMismatch(mutated);

        mutated = config;
        mutated.nextInboxPosition += 1;
        _expectMismatch(mutated);
    }

    function _expectMismatch(
        LegacyConfigData memory mutated
    ) internal {
        vm.expectRevert("CONFIG_HASH_MISMATCH");
        this._validateConfigHash(mutated, configHash);
    }
}
