// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

// assumes parent and child chain uses ETH for fees
contract Parent {
    struct SequencerCommitment {
        uint256 blockNum;
        bytes32 blockHash;
        uint256 pricePerEthWad;
    }

    address public immutable sequencer;

    // D
    uint256 public depositedAmount;
    // I - insurance sold
    uint256 public insuranceSold;

    // sequence number sigma
    uint256 public sequenceNumber;

    constructor(address _sequencer) {
        sequencer = _sequencer;
    }

    modifier onlySequencer() {
        require(msg.sender == sequencer, "only sequencer can call");
        _;
    }

    function deposit() public payable onlySequencer {
        // increment depositedAmount by value
        // create a retryable to hit the child contract deposit function
        // increment seqNum
    }

    function withdraw(uint256 amount) public onlySequencer {
        // decrement depositedAmount by amount
        // create a retryable to hit the child contract withdraw function
        // increment seqNum
    }

    function buy(uint256 amount, uint256 minSatisfied, address beneficiary, bytes memory signedCommitment) public payable {
        // verify the signed commitment
        // require depositAmount - insuranceSold + minSatisfied >= amount
        // require msg.value == price*amount
        // increment insuranceSold by amount
        // create a retryable to hit the child contract settle function, sending msg.value
        // increment seqNum
    }
}