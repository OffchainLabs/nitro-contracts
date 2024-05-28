pragma solidity ^0.8.0;

import "./MerkleProofInput.sol";
struct BlobPointer {
    bytes32 blockHash;
    string sender;
    uint32 nonce;
    bytes32 dasTreeRootHash;
    MerkleProofInput merkleProofInput;
}
