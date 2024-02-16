// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/nitro/blob/master/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.4;

import "./AbsOutbox.sol";

contract ERC20Outbox is AbsOutbox {
    function l2ToL1WithdrawalAmount() external view returns (uint256 amount) {
        assembly {
            amount := tload(L2_TO_L1_WITHDRAWAL_AMOUNT_TSLOT)
        }
    }

    /// @inheritdoc AbsOutbox
    function _amountToSetInContext(uint256 value) internal pure override returns (uint256) {
        // native token withdrawal amount which can be fetched from context
        return value;
    }
}
