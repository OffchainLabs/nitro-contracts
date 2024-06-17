// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "../bridge/IHotShot.sol";

contract MockHotShot is IHotShot {
    mapping(uint256 => uint256) public commitments;
    mapping(uint256 => bool) public livenesses;

    function getHotShotCommitment(uint256 hotShotBlockHeight)
        external
        view
        override
        returns (HotShotCommitment memory)
    {
        return HotShotCommitment({
            blockHeight: uint64(hotShotBlockHeight),
            blockCommRoot: commitments[hotShotBlockHeight]
        });
    }

    function lagOverEscapeHatchThreshold(uint256 blockNumber, uint256 threshold)
        external
        view
        override
        returns (bool)
    {
        return true;
    }

    function setCommitment(uint256 height, uint256 commitment) external {
        commitments[height] = commitment;
    }

    function setLiveness(uint256 l1Height, bool isLive) external {
        livenesses[l1Height] = isLive;
    }
}
