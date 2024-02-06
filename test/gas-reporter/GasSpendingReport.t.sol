// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./GasSpendingReferentReport.t.sol";

contract GasSpendingReportTest is GasSpendingReferentReportTest {
    /* solhint-disable func-name-mixedcase */

    // based on TX: 0x3089a4deb73be7a973112d6ccb412d0e0dced2b42b96a44d9450d7f0ff6c15b4
    function test_depositEth() public override {
        Inbox inbox = new Inbox(117_964);
        vm.etch(address(0x5aED5f8A1e3607476F1f81c3d8fe126deB0aFE94), address(inbox).code);

        super.test_depositEth();
    }

    /// based on TX: 0x3d1abfd87f7a0de35a2a8fab4810bf0c6d1ae06a28615a7d87610aec73bd5c79
    function test_withdrawEth() public override {
        Outbox outbox = new Outbox();
        vm.etch(address(0x0eA7372338a589e7f0b00E463a53AA464ef04e17), address(outbox).code);

        super.test_withdrawEth();
    }
}
