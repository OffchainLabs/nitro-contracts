// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "./util/TestUtil.sol";
import "../../src/bridge/IERC20Bridge.sol";
import "../../src/bridge/ERC20Bridge.sol";
import "../../src/bridge/extra/ERC20MigrationOutbox.sol";
import {NoZeroTransferToken} from "./util/NoZeroTransferToken.sol";

contract ERC20MigrationOutboxTest is Test {
    IERC20Bridge public bridge;

    IERC20MigrationOutbox public erc20MigrationOutbox;
    IERC20Bridge public erc20Bridge;
    IERC20 public nativeToken;

    address public user = address(100);
    address public rollup = address(1000);
    address public seqInbox = address(1001);
    address public constant dst = address(1337);

    function setUp() public {
        // deploy token, bridge and erc20MigrationOutbox
        nativeToken = new NoZeroTransferToken("Appchain Token", "App", 1_000_000, address(this));
        bridge = IERC20Bridge(TestUtil.deployProxy(address(new ERC20Bridge())));
        erc20Bridge = IERC20Bridge(address(bridge));

        // init bridge
        erc20Bridge.initialize(IOwnable(rollup), address(nativeToken));

        // deploy erc20MigrationOutbox
        erc20MigrationOutbox = new ERC20MigrationOutbox(bridge, dst);

        // set outbox
        vm.prank(rollup);
        bridge.setOutbox(address(erc20MigrationOutbox), true);
    }

    function test_invalid_destination() public {
        vm.expectRevert(IERC20MigrationOutbox.InvalidDestination.selector);
        new ERC20MigrationOutbox(bridge, address(0));
    }

    function test_migrate() public {
        nativeToken.transfer(address(bridge), 1000);

        vm.prank(user);
        erc20MigrationOutbox.migrate();

        assertEq(nativeToken.balanceOf(dst), 1000);
    }

    function test_migrate_no_balance() public {
        vm.expectRevert(IERC20MigrationOutbox.NoBalanceToMigrate.selector);
        vm.prank(user);
        erc20MigrationOutbox.migrate();
    }
}
