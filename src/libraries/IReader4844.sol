pragma solidity >=0.6.9 <0.9.0;

interface IReader4844 {
    /// @notice Returns the current BLOBBASEFEE
    function getBlobBaseFee() external view returns (uint256);

    /// @notice Returns all the data hashes of all the blobs on the current transaction
    function getDataHashes() external view returns (bytes32[] memory);
}
