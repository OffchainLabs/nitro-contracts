// Copyright 2022-2024, Offchain Labs, Inc.
// For license information, see https://github.com/nitro/blob/master/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity >=0.4.21 <0.9.0;

/**
 * @title Methods for managing user programs
 * @notice Precompiled contract that exists in every Arbitrum chain at 0x0000000000000000000000000000000000000071.
 */
interface ArbWasm {
    /// @notice activate a wasm program
    /// @param program the program to activate
    /// @return version the stylus version the program was activated against
    /// @return dataFee the data fee paid to store the activated program
    function activateProgram(address program)
        external
        payable
        returns (uint16 version, uint256 dataFee);

    /// @notice gets the latest stylus version
    /// @return version the stylus version
    function stylusVersion() external view returns (uint16 version);

    /// @notice gets the stylus version the program with codehash was most recently activated against
    /// @return version the program version (reverts for EVM contracts)
    function codehashVersion(bytes32 codehash) external view returns (uint16 version);

    /// @notice extends a program's expiration date.
    /// Reverts if too soon or if the program is not up to date.
    function codehashKeepalive(bytes32 codehash) external payable;

    /// @notice gets the stylus version the program was most recently activated against
    /// @return version the program version (reverts for EVM contracts)
    function programVersion(address program) external view returns (uint16 version);

    /// @notice gets the cost to invoke the program (not including minInitGas)
    /// @return gas the amount of gas
    function programInitGas(address program) external view returns (uint32 gas);

    /// @notice gets the memory footprint of the program at the given address in pages
    /// @return footprint the memory footprint of program in pages (reverts for EVM contracts)
    function programMemoryFootprint(address program) external view returns (uint16 footprint);

    /// @notice gets the amount of time remaining until the program expires
    /// @return _secs the time left in seconds (reverts for EVM contracts)
    function programTimeLeft(address program) external view returns (uint64 _secs);

    /// @notice gets the conversion rate between gas and ink
    /// @return price the amount of ink 1 gas buys
    function inkPrice() external view returns (uint32 price);

    /// @notice gets the wasm stack size limit
    /// @return depth the maximum depth (in wasm words) a wasm stack may grow
    function maxStackDepth() external view returns (uint32 depth);

    /// @notice gets the number of free wasm pages a program gets
    /// @return pages the number of wasm pages (2^16 bytes)
    function freePages() external view returns (uint16 pages);

    /// @notice gets the base cost of each additional wasm page (2^16 bytes)
    /// @return gas base amount of gas needed to grow another wasm page
    function pageGas() external view returns (uint16 gas);

    /// @notice gets the ramp that drives exponential memory costs
    /// @return ramp bits representing the floating point value
    function pageRamp() external view returns (uint64 ramp);

    /// @notice gets the maximum number of pages a wasm may allocate
    /// @return limit the number of pages
    function pageLimit() external view returns (uint16 limit);

    /// @notice gets the minimum cost to invoke a program
    /// @return gas amount of gas
    function minInitGas() external view returns (uint16 gas);

    /// @notice gets the number of days after which programs deactivate
    /// @return _days the number of days
    function expiryDays() external view returns (uint16 _days);

    /// @notice gets the age a program must be to perform a keepalive
    /// @return _days the number of days
    function keepaliveDays() external view returns (uint16 _days);

    event ProgramActivated(
        bytes32 indexed codehash,
        bytes32 moduleHash,
        address program,
        uint256 dataFee,
        uint16 version
    );
    event ProgramLifetimeExtended(bytes32 indexed codehash, uint256 dataFee);

    error ProgramNotActivated();
    error ProgramNeedsUpgrade(uint16 version, uint16 stylusVersion);
    error ProgramExpired(uint64 ageInSeconds);
    error ProgramUpToDate();
    error ProgramKeepaliveTooSoon(uint64 ageInSeconds);
    error ProgramInsufficientValue(uint256 have, uint256 want);
}
