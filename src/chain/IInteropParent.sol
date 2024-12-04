// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IInteropParent {
    struct Bid {
        address counter;
        bytes32 meta;
    }

    struct Agreement {
        address origin;
        int64 chosen;
    }

    function agreements(uint256 index) external view returns (address origin, int64 chosen);
    function aBids(uint256 agreementId, uint256 bidId)
        external
        view
        returns (address counter, bytes32 meta);

    function create() external returns (uint256);

    function bid(
        uint256 agreementId,
        address counter,
        bytes32 meta,
        uint256 condBlocknum,
        bytes32 condHash
    ) external returns (uint256);

    function agree(
        uint256 agreementId,
        uint256 bidId,
        bytes32 meta,
        uint256 condBlocknum,
        bytes32 condHash
    ) external;

    function sendResult(
        uint256 agreementId,
        address destChain,
        address destContract,
        uint256 gasLimit,
        uint256 maxFeePerGas,
        uint256 maxSubmissionCost
    ) external payable;
}
