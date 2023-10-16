// Copyright 2022-2023, Offchain Labs, Inc.
// For license information, see https://github.com/nitro/blob/master/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity >=0.4.21 <0.9.0;

/**
 * @title Methods for managing user programs
 * @notice Precompiled contract that exists in every Arbitrum chain at 0x0000000000000000000000000000000000000071.
 */
interface ArbWasm {
    // @notice compile a wasm program
    // @param program the program to compile
    // @return version the stylus version the program was compiled against
    function activateProgram(address program) external returns (uint16 version);

    // @notice gets the latest stylus version
    // @return version the stylus version
    function stylusVersion() external view returns (uint16 version);

    // @notice gets the stylus version the program with codehash was most recently compiled against.
    // @return version the program version (0 for EVM contracts)
    function codehashVersion(bytes32 codehash) external view returns (uint16 version);

    // @notice gets the stylus version the program was most recently compiled against.
    // @return version the program version (0 for EVM contracts)
    function programVersion(address program) external view returns (uint16 version);

    // @notice gets the uncompressed size of the program at the given address in bytes
    // @return size the size of the program in bytes rounded up to a multiple of 512
    function programSize(address program) external view returns (uint32 size);

    // @notice gets the memory footprint of the program at the given address in pages
    // @return footprint the memory footprint of program in pages
    function programMemoryFootprint(address program) external view returns (uint16 footprint);

    // @notice gets the conversion rate between gas and ink
    // @return price the amount of ink 1 gas buys
    function inkPrice() external view returns (uint32 price);

    // @notice gets the wasm stack size limit
    // @return depth the maximum depth (in wasm words) a wasm stack may grow
    function maxStackDepth() external view returns (uint32 depth);

    // @notice gets the number of free wasm pages a program gets
    // @return pages the number of wasm pages (2^16 bytes)
    function freePages() external view returns (uint16 pages);

    // @notice gets the base cost of each additional wasm page (2^16 bytes)
    // @return gas base amount of gas needed to grow another wasm page
    function pageGas() external view returns (uint16 gas);

    // @notice gets the ramp that drives exponential memory costs
    // @return ramp bits representing the floating point value
    function pageRamp() external view returns (uint64 ramp);

    // @notice gets the maximum number of pages a wasm may allocate
    // @return limit the number of pages
    function pageLimit() external view returns (uint16 limit);

    // @notice gets the added wasm call cost based on binary size
    // @return gas cost paid per half kb uncompressed.
    function callScalar() external view returns (uint16 gas);

    event ProgramActivated(
        bytes32 indexed codehash,
        bytes32 moduleHash,
        address program,
        uint16 version
    );

    error ProgramNotActivated();
    error ProgramOutOfDate(uint16 version);
    error ProgramUpToDate();
}
