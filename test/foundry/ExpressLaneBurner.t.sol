// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {
    ERC20BurnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {Burner} from "../../src/express-lane-auction/Burner.sol";
import "../../src/express-lane-auction/Errors.sol";

contract MockERC20 is ERC20BurnableUpgradeable {
    function initialize() public initializer {
        __ERC20_init("LANE", "LNE");
        _mint(msg.sender, 1_000_000);
    }
}

contract ExpressLaneBurner is Test {
    event Transfer(address indexed from, address indexed to, uint256 value);

    function testBurn() public {
        vm.expectRevert(ZeroAddress.selector);
        new Burner(address(0));

        MockERC20 erc20 = new MockERC20();
        erc20.initialize();
        Burner burner = new Burner(address(erc20));
        assertEq(address(burner.token()), address(erc20));

        erc20.transfer(address(burner), 20);

        uint256 totalSupplyBefore = erc20.totalSupply();
        assertEq(erc20.balanceOf(address(burner)), 20);

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(burner), address(0), 20);
        vm.prank(vm.addr(137));
        burner.burn();

        assertEq(totalSupplyBefore - erc20.totalSupply(), 20);
        assertEq(erc20.balanceOf(address(burner)), 0);

        // can burn 0 if we want to
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(burner), address(0), 0);
        vm.prank(vm.addr(138));
        burner.burn();
    }
}
