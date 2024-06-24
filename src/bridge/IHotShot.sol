// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

struct HotShotCommitment {
    uint64 blockHeight;
    uint256 blockCommRoot;
}

interface IHotShot {
    function getHotShotCommitment(uint256 hotShotBlockHeight) external view returns (HotShotCommitment memory);
    function lagOverEscapeHatchThreshold(
        uint256 blockNumber,
        uint256 threshold
    ) external view returns (bool);
}
