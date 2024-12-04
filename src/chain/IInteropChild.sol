// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IInteropChild {
    function receiveResult(address counter, bytes32 meta) external;
}
