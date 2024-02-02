// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import {Inbox} from "../../src/bridge/Inbox.sol";
import {Outbox} from "../../src/bridge/Outbox.sol";

contract GasSpendingReportTest is Test {
    /* solhint-disable func-name-mixedcase */

    // based on TX: 0x3089a4deb73be7a973112d6ccb412d0e0dced2b42b96a44d9450d7f0ff6c15b4
    function test_depositEth() public {
        Inbox inbox = Inbox(0x4Dbd4fc535Ac27206064B68FfCf827b0A60BAB3f);
        address origin = address(0x585db1833EFA847aF75f748f5edB359F286106A9);
        vm.prank(origin);
        inbox.depositEth{value: 0.01 ether}();
    }

    /// based on TX: 0x3d1abfd87f7a0de35a2a8fab4810bf0c6d1ae06a28615a7d87610aec73bd5c79
    function test_withdrawEth() public {
        Outbox outbox = Outbox(0x0B9857ae2D4A3DBe74ffE1d7DF045bb7F96E4840);

        bytes32[] memory proof = new bytes32[](17);
        proof[0] = bytes32(0x1f72b48c2b27eb1f36c59474e303fd3ff666cf054fe377741285f1526e2adc5d);
        proof[1] = bytes32(0x33e7ffe193403d76081d7bfaa730040866ab53031d24868b01b02179efd89ab7);
        proof[2] = bytes32(0xfe08a6fb26be3442434aef6635084deeaa0d8dd8cf5d46b54da7df3ef5e72569);
        proof[3] = bytes32(0xb34c60845468800566445b891a08e4a152a62a1ff9e9c2aeec7f565d2b313651);
        proof[4] = bytes32(0x2ad163eea8d1d86da923c07d24b913a9444f215ec1b28b8f78227abe6eba825d);
        proof[5] = bytes32(0x01813e39c00e02b86335f52b896a170243b09a4f1c24ceca7dc57607d12dd4c5);
        proof[6] = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);
        proof[7] = bytes32(0xd7909c9104e31be38427c9861fb4c5048bc91ea2083cc4426e93fe171d2ffd7f);
        proof[8] = bytes32(0xffe8aba5b3426c6aa74fddcd607c530e8d4109429219f8b7059319d58e2495df);
        proof[9] = bytes32(0xaaab39a7d198768bfb9585f57507e25a8289f038ea33955a4f98b9152c665346);
        proof[10] = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);
        proof[11] = bytes32(0xa6288e21a4b82f2d0bf22bcdf4430409c2309d0ba6c33f89ce3d1100c8b4cba1);
        proof[12] = bytes32(0x4e87863e75796493a3f36c58351b8ab0e2dd2f6167b819a703ace5679b052bab);
        proof[13] = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);
        proof[14] = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);
        proof[15] = bytes32(0xc0425084107ea9f7a4118f5ed1e3566cda4e90b550363fc804df1e52ed5f2386);
        proof[16] = bytes32(0xb43a6b28077d49f37d58c87aec0b51f7bce13b648143f3295385f3b3d5ac3b9b);

        uint256 withdrawalAmount = 9 ether;
        vm.prank(0xa40c99A827733D2f0200Bb18118703Ce3DBF5558);
        outbox.executeTransaction({
            proof: proof,
            index: uint256(105_345),
            l2Sender: address(0xa40c99A827733D2f0200Bb18118703Ce3DBF5558),
            to: address(0xa40c99A827733D2f0200Bb18118703Ce3DBF5558),
            l2Block: 174_433_338,
            l1Block: 19_092_075,
            l2Timestamp: 1_706_287_813,
            value: withdrawalAmount,
            data: ""
        });
    }
}
