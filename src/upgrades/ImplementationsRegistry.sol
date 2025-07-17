// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

/// @notice A registry for nitro contracts implementations.
///         All contract implementations are now deployed with CREATE2.
///         This registry is also deployed with CREATE2 at each nitro contracts release.
///         It allows you to look up the address of a contract implementation by its name and constructor arguments.
///         Used by upgrade actions
contract ImplementationsRegistry {
    error UnknownContractName(string contractName);
    error ContractNotRegistered(string contractName, bytes32 argsHash);
    error InvalidArglessInitCode(bytes32 providedCodeHash, bytes32 expectedCodeHash);
    error ContractNotDeployed(string contractName, bytes32 argsHash, address addr);

    address public immutable create2Factory;
    bytes32 public immutable create2Salt;

    mapping(bytes32 => mapping(bytes32 => bytes32)) nameHashToArgsHashToInitCodeHash;
    mapping(bytes32 => bool) knownContractName;
    string[] contractNames;

    constructor(
        address _create2Factory,
        bytes32 _create2Salt,
        string[] memory _contractNames,
        bytes32[] memory _codeHashes
    ) {
        require(_contractNames.length == _codeHashes.length, "Mismatched lengths");

        create2Factory = _create2Factory;
        create2Salt = _create2Salt;

        contractNames = _contractNames;

        for (uint256 i = 0; i < _contractNames.length; i++) {
            bytes32 nameHash = keccak256(abi.encode(_contractNames[i]));
            bytes32 codeHash = _codeHashes[i];
            knownContractName[nameHash] = true;
            nameHashToArgsHashToInitCodeHash[nameHash][keccak256("")] = codeHash;
        }
    }

    function registerHashWithArgs(
        string memory contractName,
        bytes memory arglessInitCode,
        bytes memory args
    ) external {
        bytes32 nameHash = keccak256(abi.encode(contractName));
        if (!knownContractName[nameHash]) {
            revert UnknownContractName(contractName);
        }
        bytes32 arglessCodeHash = nameHashToArgsHashToInitCodeHash[nameHash][keccak256("")];
        if (keccak256(arglessInitCode) != arglessCodeHash) {
            revert InvalidArglessInitCode(keccak256(arglessInitCode), arglessCodeHash);
        }
        nameHashToArgsHashToInitCodeHash[nameHash][keccak256(args)] =
            keccak256(abi.encodePacked(arglessInitCode, args));
    }

    function getAddress(
        string memory contractName
    ) external view returns (address) {
        return getAddressWithArgs(contractName, keccak256(""));
    }

    function getAddressWithArgs(
        string memory contractName,
        bytes32 argsHash
    ) public view returns (address) {
        bytes32 codeHash =
            nameHashToArgsHashToInitCodeHash[keccak256(abi.encode(contractName))][argsHash];
        if (codeHash == bytes32(0)) {
            revert ContractNotRegistered(contractName, argsHash);
        }

        address addr = Create2.computeAddress(create2Salt, codeHash, create2Factory);

        // if an invalid argsHash is provided, the address won't have code
        // we should revert in that case
        if (addr.code.length == 0) {
            revert ContractNotDeployed(contractName, argsHash, addr);
        }

        return addr;
    }

    function getContractNames() external view returns (string[] memory) {
        return contractNames;
    }
}
