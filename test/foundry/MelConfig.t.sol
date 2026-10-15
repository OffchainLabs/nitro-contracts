// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "../../src/rollup/MelConfig.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract MelConfigTest is Test {
    uint256 constant VERSION = 7;
    address bridge = makeAddr("bridge");

    function _slot(
        address target,
        uint256 slot
    ) internal view returns (bytes32) {
        return vm.load(target, bytes32(slot));
    }

    function _toBytes32(
        address value
    ) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(value)));
    }

    function testInitialize() public {
        MelConfig melConfig = new MelConfig();
        melConfig.initialize(VERSION, bridge);

        assertEq(melConfig.version(), VERSION, "Invalid version");
        assertEq(melConfig.bridge(), bridge, "Invalid bridge");
    }

    // The replay binary reads these slots through storage proofs, so their positions are consensus-critical
    function testStorageLayout() public {
        MelConfig melConfig = new MelConfig();
        melConfig.initialize(VERSION, bridge);

        assertEq(_slot(address(melConfig), 0), bytes32(VERSION), "Version not at slot 0");
        assertEq(_slot(address(melConfig), 1), _toBytes32(bridge), "Bridge not at slot 1");
    }

    function testStorageLayoutThroughProxy() public {
        MelConfig template = new MelConfig();
        address proxy = address(
            new TransparentUpgradeableProxy(address(template), address(new ProxyAdmin()), "")
        );
        IMelConfig(proxy).initialize(VERSION, bridge);

        assertEq(IMelConfig(proxy).version(), VERSION, "Invalid version");
        assertEq(IMelConfig(proxy).bridge(), bridge, "Invalid bridge");
        assertEq(_slot(proxy, 0), bytes32(VERSION), "Version not at proxy slot 0");
        assertEq(_slot(proxy, 1), _toBytes32(bridge), "Bridge not at proxy slot 1");
        assertEq(template.bridge(), address(0), "Template must stay uninitialized");
    }

    function testRevertInitializeTwice() public {
        MelConfig melConfig = new MelConfig();
        melConfig.initialize(VERSION, bridge);

        vm.expectRevert(MelConfig.AlreadyInitialized.selector);
        melConfig.initialize(VERSION + 1, makeAddr("otherBridge"));
    }
}
