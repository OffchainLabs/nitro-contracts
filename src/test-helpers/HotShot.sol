// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

contract MockHotShot {
    mapping(uint256 => uint256) public commitments;
    mapping(uint256 => bool) public availabilities;

    function setCommitment(uint256 height, uint256 commitment) external {
        commitments[height] = commitment;
    }

    function setAvailability(uint256 l1Height, bool isLive) external {
        availabilities[l1Height] = isLive;
    }
}
