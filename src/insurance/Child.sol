// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AddressAliasHelper} from "../libraries/AddressAliasHelper.sol";

// assumes parent and child chain uses ETH for fees
// EVERY FUNCTION MUST NEVER REVERT WHEN CALLED BY PARENT IN SEQUENCE, OTHERWISE QUEUE IS STUCK
contract Child {
    address public immutable parentChainAddr;
    address public immutable sequencerAddr;
    uint256 public sequenceNumber;
    uint256 public amtSatisfied;

    constructor(address _parentChainAddr, address _sequencerAddr) {
        parentChainAddr = _parentChainAddr;
        sequencerAddr = _sequencerAddr;
    }

    modifier onlyInSequenceFromParent(uint256 seqNum) {
        require(seqNum == sequenceNumber, "invalid sequence number");
        require(msg.sender == AddressAliasHelper.applyL1ToL2Alias(parentChainAddr), "only parent chain contract can call");
        sequenceNumber++;
        _;
    }

    function deposit(uint256 seqNum) public payable onlyInSequenceFromParent(seqNum) {
        // no need to do anything here, just receiving ETH
    }

    function withdraw(uint256 seqNum, uint256 amount) public onlyInSequenceFromParent(seqNum) {
        amount = amount < address(this).balance ? amount : address(this).balance;
        (bool success,) = payable(sequencerAddr).call{value: amount}("");
        require(success, "withdraw failed");
    }

    // If (blocknum, blockhash) is in the history of Chain X, then add amount to S. Otherwise pay out amount to beneficiaryAddr.
    // will revert if arb block num < blockNum
    function commit(uint256 seqNum, address beneficiary, uint256 amount, uint256 blockNum, bytes32 blockHash) external payable onlyInSequenceFromParent(seqNum) {
        // revert if arb block num < blockNum
        // pay msg.value to sequencer
        // check if blockHash is part of history
        // if yes: increment amtSatisfied (S)
        // if no: pay out amount to beneficiary. do not revert on failure, because a contract could DoS
    }
}
