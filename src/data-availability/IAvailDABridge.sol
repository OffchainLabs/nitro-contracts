// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./MerkleProofInput.sol";

/**
 * @author  @rishabhagrawalzra (Avail)
 * @title   AvailDABridge
 * @notice  An Avail on-chain data attestation verification interface
 * @custom:security security@availproject.org
 */
interface IAvailDABridge {
    /**
     * @notice  Takes a Merkle tree proof of inclusion for a blob leaf and verifies it
     * @dev     This function is used for data attestation on Ethereum
     * @param   input  Merkle tree proof of inclusion for the blob leaf
     * @return  bool  Returns true if the blob leaf is valid, else false
     */
    function verifyBlobLeaf(MerkleProofInput calldata input) external view returns (bool);
}
