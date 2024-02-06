// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./GasSpendingReferentReport.t.sol";

contract GasSpendingReportTest is GasSpendingReferentReportTest {
    /* solhint-disable func-name-mixedcase */

    function test_depositEth() public override {
        // create instance of inbox contract from current code, and use it in place of
        // actual inbox logic code that is deployed on-chain
        Inbox inbox = new Inbox(117_964);
        vm.etch(address(0x5aED5f8A1e3607476F1f81c3d8fe126deB0aFE94), address(inbox).code);

        super.test_depositEth();
    }

    function test_withdrawEth() public override {
        // create instance of outbox contract from current code, and use it in place of
        // actual outbox logic code that is deployed on-chain
        Outbox outbox = new Outbox();
        vm.etch(address(0x0eA7372338a589e7f0b00E463a53AA464ef04e17), address(outbox).code);

        super.test_withdrawEth();
    }

    function test_withdrawToken() public override {
        // create instance of outbox contract from current code, and use it in place of
        // actual outbox logic code that is deployed on-chain
        Outbox outbox = new Outbox();
        vm.etch(address(0x0eA7372338a589e7f0b00E463a53AA464ef04e17), address(outbox).code);

        super.test_withdrawToken();
    }
}
