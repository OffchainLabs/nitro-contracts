// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "./ERC20Inbox.t.sol";

import {DecimalsConverterHelper} from "../../src/libraries/DecimalsConverterHelper.sol";

contract DecimalsConverterHelperTest is Test {
    /* solhint-disable func-name-mixedcase */
    function test_adjust_decimals_equalDecimal() public {
        assertEq(DecimalsConverterHelper.adjustDecimals(752, 18, 18), 752, "Invalid 1");
        assertEq(DecimalsConverterHelper.adjustDecimals(752, 0, 0), 752, "Invalid 2");
        assertEq(DecimalsConverterHelper.adjustDecimals(752, 25, 25), 752, "Invalid 3");
    }

    function test_adjust_decimals_InLessThanOut() public {
        assertEq(
            DecimalsConverterHelper.adjustDecimals(752, 0, 18),
            752 * 10**18,
            "Invalid adjustment 2"
        );
        assertEq(
            DecimalsConverterHelper.adjustDecimals(752, 16, 18),
            75_200,
            "Invalid adjustment 4"
        );
    }

    function test_adjust_decimals_InGreaterThanOut() public {
        assertEq(DecimalsConverterHelper.adjustDecimals(752, 19, 18), 75, "Invalid adjustment 5");
        assertEq(DecimalsConverterHelper.adjustDecimals(752, 20, 18), 7, "Invalid adjustment 6");
        assertEq(DecimalsConverterHelper.adjustDecimals(752, 21, 18), 0, "Invalid adjustment 7");
    }

    function test_adjust_decimals_equalDecimal_Fuzz(uint256 amount, uint8 decimals) public {
        assertEq(
            DecimalsConverterHelper.adjustDecimals(amount, decimals, decimals),
            amount,
            "Invalid 8"
        );
    }

    function test_adjust_decimals_equalDecimal_InLessThanOut_Fuzz(uint256 amount, uint8 decimalsIn)
        public
    {
        uint8 decimalsOut = 18;
        vm.assume(decimalsIn < decimalsOut);
        vm.assume(amount < type(uint256).max / 10**(decimalsOut - decimalsIn));
        assertEq(
            DecimalsConverterHelper.adjustDecimals(amount, decimalsIn, decimalsOut),
            amount * 10**(decimalsOut - decimalsIn),
            "Invalid 9"
        );
    }

    function test_adjust_decimals_equalDecimal_InMoreThanOut_Fuzz(uint256 amount, uint8 decimalsIn)
        public
    {
        uint8 decimalsOut = 18;

        vm.assume(decimalsIn <= 36);
        vm.assume(decimalsIn > decimalsOut);
        assertEq(
            DecimalsConverterHelper.adjustDecimals(amount, decimalsIn, decimalsOut),
            amount / 10**(decimalsIn - decimalsOut),
            "Invalid 10"
        );
    }
}
