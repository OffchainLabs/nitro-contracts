// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./IInteropChild.sol";
import "../libraries/AddressAliasHelper.sol";

contract InteropChild is IInteropChild {
    address public immutable parent;

    constructor(address _parent) {
        parent = _parent;
    }

    modifier onlyParent() {
        require(msg.sender == AddressAliasHelper.applyL1ToL2Alias(parent), "only parent");
        _;
    }

    function receiveResult(address counter, bytes32 meta) external onlyParent {
        // TODO: implement
    }
}
