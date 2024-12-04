// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import {IInbox} from "../bridge/IInbox.sol";
import {Child} from "./Child.sol";

// assumes parent and child chain uses ETH for fees
contract Parent is EIP712 {
    struct SequencerCommitment {
        // should be unique
        uint256 nonce;
        // commitments are unique to a beneficiary. specified here
        address beneficiary;
        // amount of insurance to sell
        uint256 insuranceAmount;
        // cost of insurance, paid by the buyer
        uint256 insuranceCost;
        // block number the sequencer is committing to
        uint256 blockNum;
        // block hash the sequencer is committing to
        bytes32 blockHash;
    }

    struct RetryableParams {
        uint256 maxSubmissionCost;
        uint256 gasLimit;
        uint256 gasPrice;
    }

    IInbox public immutable inbox;

    address public immutable sequencer;

    address public immutable childChainContract;

    // D
    uint256 public depositedAmount;
    // I - insurance sold
    uint256 public insuranceSold;

    // sequence number sigma
    uint256 public sequenceNumber;

    mapping(bytes32 => bool) public usedCommitments;

    constructor(address _sequencer, IInbox _inbox, address _childChainContract) EIP712("Parent", "1") {
        sequencer = _sequencer;
        inbox = _inbox;
        childChainContract = _childChainContract;
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

    // todo: amount and beneficiary should be part of the commitment
    // it's possible to frontrun the buyer and burn the commitment they got from the sequencer. 
    // This has little cost to the victim, but is annoying since they'll have to go get another commitment and might pay some unnecessary gas.
    function buy(
        uint256 minSatisfied,
        SequencerCommitment calldata commitment,
        bytes calldata signature,
        RetryableParams calldata retryableParams
    ) public payable {
        // require depositAmount - insuranceSold + minSatisfied >= insuranceAmount
        // put this check first because it's the mosy likely to fail without user error
        require(depositedAmount - insuranceSold + minSatisfied >= commitment.insuranceAmount, "potential undercollateralization");

        // verify the signature
        require(isValidSignature(commitment, signature), "invalid signature");

        // require msg.value == insuranceCost + retryableCost
        uint256 retryableCost = retryableParams.maxSubmissionCost + retryableParams.gasLimit * retryableParams.gasPrice;
        require(msg.value == retryableCost + commitment.insuranceCost, "invalid value");

        // require !hasUsedCommitment(commitment)
        require(!hasUsedCommitment(commitment), "commitment already used");

        // increment insuranceSold by amount
        insuranceSold += commitment.insuranceAmount;

        // mark commitment as used
        usedCommitments[hashCommitment(commitment)] = true;

        // build calldata for child contract
        bytes memory data = abi.encodeCall(
            Child.commit,
            (
                sequenceNumber,
                commitment.beneficiary,
                commitment.insuranceAmount,
                commitment.blockNum,
                commitment.blockHash
            )
        );

        // create a retryable to hit the child contract settle function, sending msg.value
        inbox.createRetryableTicket{value: msg.value}({
            to: childChainContract,
            l2CallValue: commitment.insuranceCost,
            maxSubmissionCost: retryableParams.maxSubmissionCost,
            excessFeeRefundAddress: msg.sender,
            callValueRefundAddress: msg.sender,
            gasLimit: retryableParams.gasLimit,
            maxFeePerGas: retryableParams.gasPrice,
            data: data
        });

        // increment seqNum
        sequenceNumber++;
    }

    function isValidSignature(SequencerCommitment calldata commitment, bytes calldata signature)
        public
        view
        returns (bool)
    {
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    keccak256(
                        "SequencerCommitment(uint256 nonce,uint256 blockNum,bytes32 blockHash,uint256 pricePerEthWad)"
                    ),
                    commitment
                )
            )
        );
        address signer = ECDSA.recover(digest, signature);
        return signer == sequencer;
    }

    function hasUsedCommitment(SequencerCommitment calldata commitment) public view returns (bool) {
        return usedCommitments[hashCommitment(commitment)];
    }

    function hashCommitment(SequencerCommitment calldata commitment) public pure returns (bytes32) {
        return keccak256(abi.encode(commitment));
    }
}
