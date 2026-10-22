// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "../../src/libraries/ContractVersion.sol";
import "../../src/rollup/RollupProxy.sol";
import "../../src/rollup/RollupAdminLogic.sol";
import "../../src/rollup/RollupUserLogic.sol";

contract VersionStub {
    function nitroContractVersion() external pure returns (uint256) {
        return 1;
    }
}

contract ContractVersionTest is Test {
    bytes32 constant ADMIN_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    bytes32 constant PRIMARY_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 constant SECONDARY_IMPLEMENTATION_SLOT =
        0x2b1dbce74324248c222f0ec2d5ed7bd323cfc425b336f0253c5ccfda7265546d;

    function testVersionMatchesPackageJson() public {
        string memory version = vm.parseJsonString(vm.readFile("package.json"), ".version");
        assertEq(NITRO_CONTRACT_VERSION, this.pack(version));
    }

    function testAcceptsSuffixes() public {
        assertEq(this.pack("3.2.0-beta.12"), 3_002_000);
        assertEq(this.pack("12.34.56+build.17"), 12_034_056);
    }

    function testRejectsMalformedVersions() public {
        expectRejected("3.2");
        expectRejected("3.2.0.1");
        expectRejected("03.2.0");
        expectRejected("3..0");
        expectRejected("3.2.0junk");
        expectRejected("3.1000.0");
        expectRejected("3.2.1000");
    }

    function testSelector() public {
        assertEq(IContractVersion.nitroContractVersion.selector, bytes4(0x0c07b9e1));
    }

    function testRollupProxyRoutesByCaller() public {
        address admin = makeAddr("admin");
        RollupProxy proxy = new RollupProxy();
        vm.store(address(proxy), ADMIN_SLOT, bytes32(uint256(uint160(admin))));
        setImplementation(proxy, PRIMARY_IMPLEMENTATION_SLOT, address(new RollupAdminLogic()));
        setImplementation(proxy, SECONDARY_IMPLEMENTATION_SLOT, address(new RollupUserLogic()));
        IContractVersion versioned = IContractVersion(address(proxy));

        assertEq(versioned.nitroContractVersion(), NITRO_CONTRACT_VERSION);
        vm.prank(admin);
        assertEq(versioned.nitroContractVersion(), NITRO_CONTRACT_VERSION);

        // only the admin logic moves: non-admin callers keep seeing the user logic's version
        setImplementation(proxy, PRIMARY_IMPLEMENTATION_SLOT, address(new VersionStub()));
        assertEq(versioned.nitroContractVersion(), NITRO_CONTRACT_VERSION);
        vm.prank(admin);
        assertEq(versioned.nitroContractVersion(), 1);
    }

    function expectRejected(
        string memory version
    ) internal {
        vm.expectRevert();
        this.pack(version);
    }

    function setImplementation(
        RollupProxy proxy,
        bytes32 slot,
        address implementation
    ) internal {
        vm.store(address(proxy), slot, bytes32(uint256(uint160(implementation))));
    }

    // major * 1e6 + minor * 1e3 + patch; exactly three components, no leading zeros,
    // minor and patch below 1000, optional -prerelease or +build suffix
    function pack(
        string calldata version
    ) external pure returns (uint256) {
        bytes calldata text = bytes(version);
        uint256[3] memory parts;
        uint256[3] memory digits;
        uint256 index;
        uint256 i;
        for (; i < text.length; i++) {
            bytes1 character = text[i];
            if (character == ".") {
                require(index < 2, "too many components");
                index++;
                continue;
            }
            if (character < "0" || character > "9") break;
            require(digits[index] == 0 || parts[index] != 0, "leading zero");
            parts[index] = parts[index] * 10 + uint8(character) - 48;
            digits[index]++;
        }
        require(
            index == 2 && digits[0] > 0 && digits[1] > 0 && digits[2] > 0, "need major.minor.patch"
        );
        require(i == text.length || text[i] == "-" || text[i] == "+", "unexpected character");
        require(parts[1] < 1000 && parts[2] < 1000, "component too large");
        return parts[0] * 1e6 + parts[1] * 1e3 + parts[2];
    }
}
