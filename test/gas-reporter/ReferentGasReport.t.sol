// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import {Inbox} from "../../src/bridge/Inbox.sol";
import {Outbox} from "../../src/bridge/Outbox.sol";

contract ReferentGasReportTest is Test {
    /* solhint-disable func-name-mixedcase */

    // based on TX: 0xac95fa28b940a2f3c431b9766c53473e4ac6c3e4606376255141463b6549626c
    function test_depositEth() public virtual {
        Inbox inbox = Inbox(0x4Dbd4fc535Ac27206064B68FfCf827b0A60BAB3f);
        address origin = address(0x1c6601124e8adDC0926B4567Be6aC39C10d3Eeff);
        uint256 amount = 0.017022869911820077 ether;
        vm.deal(origin, amount);
        vm.prank(origin);
        inbox.depositEth{value: amount}();
    }

    /// based on TX: 0x739e443bec4154807f76c045ec2803bb2cfd6ac0488098038a6aec8080c814a4
    function test_withdrawEth() public virtual {
        Outbox outbox = Outbox(0x0B9857ae2D4A3DBe74ffE1d7DF045bb7F96E4840);

        bytes32[] memory proof = new bytes32[](17);
        proof[0] = bytes32(0xdac8eabe1cdbe8feda2aee1557b34ceab8d8e0589b81753470db782c8b27da1b);
        proof[1] = bytes32(0xc829ff2e4cf115d587a6cafb2692a4a97f1ee19d227befa285cd7ddf03940430);
        proof[2] = bytes32(0x71c595ca554242bc84cdf42e3602ca7a9890c536437b79e8d9eccdce4db5b338);
        proof[3] = bytes32(0x1256b48a6179ec31bf9ed60ea9c6684a46b9526f0255de7099edd355c7d8d48c);
        proof[4] = bytes32(0x628a15dc3a17d9bdf7904214f1e8783ed765273f181275370fc88dd6b84fc9c1);
        proof[5] = bytes32(0x4155ff4c6f1b32a22d118ac08687bfe3180df401108ebc0e1435517492d7840f);
        proof[6] = bytes32(0x70b3501ec5e9271d9db97b5592f0150452d969f9c3ded4987cbbdcb8e81c1ffd);
        proof[7] = bytes32(0x64ef3a11c5f4f7bec220255cbf15c3caa1809f383bdbdd515cd4dbcd5b03c301);
        proof[8] = bytes32(0xee9531d799b7b2b47a70eb1a06e96f7785b218b2d8ad338f5ad8c8894006bee5);
        proof[9] = bytes32(0x39944b31488fab0ebf2a72f7530e53b12f323f5b09682029857b9cf880fe0000);
        proof[10] = bytes32(0xbe63e637b21f7c5c32ca107cf1344a064abfe7bc77759d6fff901141b1f26302);
        proof[11] = bytes32(0xa162bccc7a8aefda9d526b49133ae3d14cd0e054059318d89cafb5062b081829);
        proof[12] = bytes32(0x4e87863e75796493a3f36c58351b8ab0e2dd2f6167b819a703ace5679b052bab);
        proof[13] = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);
        proof[14] = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);
        proof[15] = bytes32(0xc0425084107ea9f7a4118f5ed1e3566cda4e90b550363fc804df1e52ed5f2386);
        proof[16] = bytes32(0xb43a6b28077d49f37d58c87aec0b51f7bce13b648143f3295385f3b3d5ac3b9b);

        uint256 withdrawalAmount = 0.005589526859196637 ether;
        vm.prank(0x9Aee79fbFD80F09a67c3Ffc486Af6A007A7D4030);
        outbox.executeTransaction({
            proof: proof,
            index: uint256(104_223),
            l2Sender: address(0x9Aee79fbFD80F09a67c3Ffc486Af6A007A7D4030),
            to: address(0x9Aee79fbFD80F09a67c3Ffc486Af6A007A7D4030),
            l2Block: 170_630_414,
            l1Block: 19_010_896,
            l2Timestamp: 1_705_304_918,
            value: withdrawalAmount,
            data: ""
        });
    }

    /// based on TX: 0x9fbe48711d432ac2ad912f5260d577b0923909fae0a2c2b4ea2cc2d82d7f16dc
    function test_withdrawToken() public virtual {
        Outbox outbox = Outbox(0x0B9857ae2D4A3DBe74ffE1d7DF045bb7F96E4840);

        bytes32[] memory proof = new bytes32[](17);
        proof[0] = bytes32(0x0db57d3ad02d8f48998d134d45b7ab8eddb566f662c45045d824f67e9accb0e6);
        proof[1] = bytes32(0x2123ff6ef00f22209b8804b0e3a64ea4330f613cc7cac2b09468015955f341cf);
        proof[2] = bytes32(0xc57e585cbf237a4ff0dd739dd2326d70d2017c8d8c93164ae140adce84d97757);
        proof[3] = bytes32(0x2b670d9c2278a472cda698b9ee5d9663ee886aab2943631f328c9030459d481f);
        proof[4] = bytes32(0x9494723c378815885b803bd4701b97e605cec7875ce15637e06397ce85d0b57f);
        proof[5] = bytes32(0xd60add06a3e898ee23a92107cfe649c826cef383533410374b3b0749f0106d74);
        proof[6] = bytes32(0xc78bd69efed3f873fa06f83d6a888cfe0064d9c0431123a07087fd0b19c51a8a);
        proof[7] = bytes32(0x238dff0d1c5437566ca5b8d083ec474d1c739e55e2a011612a106fd1024a0597);
        proof[8] = bytes32(0xee9531d799b7b2b47a70eb1a06e96f7785b218b2d8ad338f5ad8c8894006bee5);
        proof[9] = bytes32(0x39944b31488fab0ebf2a72f7530e53b12f323f5b09682029857b9cf880fe0000);
        proof[10] = bytes32(0xbe63e637b21f7c5c32ca107cf1344a064abfe7bc77759d6fff901141b1f26302);
        proof[11] = bytes32(0xa162bccc7a8aefda9d526b49133ae3d14cd0e054059318d89cafb5062b081829);
        proof[12] = bytes32(0x4e87863e75796493a3f36c58351b8ab0e2dd2f6167b819a703ace5679b052bab);
        proof[13] = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);
        proof[14] = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);
        proof[15] = bytes32(0xc0425084107ea9f7a4118f5ed1e3566cda4e90b550363fc804df1e52ed5f2386);
        proof[16] = bytes32(0xb43a6b28077d49f37d58c87aec0b51f7bce13b648143f3295385f3b3d5ac3b9b);

        bytes memory data =
            hex"2e567b360000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c599000000000000000000000000f6bfec3bdf5098dfac0e671ebce06cbead7a958e000000000000000000000000f6bfec3bdf5098dfac0e671ebce06cbead7a958e000000000000000000000000000000000000000000000000000000002a51bd8000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000405600000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000";
        vm.prank(0xF6bFEc3BdF5098DfAC0E671EBCe06cBeAd7A958E);
        outbox.executeTransaction({
            proof: proof,
            index: uint256(104_341),
            l2Sender: address(0x09e9222E96E7B4AE2a407B98d48e330053351EEe),
            to: address(0xa3A7B6F88361F48403514059F1F16C8E78d60EeC),
            l2Block: 170_969_183,
            l1Block: 19_018_326,
            l2Timestamp: 1_705_394_566,
            value: 0,
            data: data
        });
    }
}
