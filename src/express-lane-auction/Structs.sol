// SPDX-License-Identifier: UNLICENSED
// CHRIS: TODO: choose sol version
pragma solidity ^0.8.9;

/// @notice a bid used for express lane auctions.
/// @param chainId     the chain id of the target chain.
/// @param round       the round number for which the bid is made.
/// @param bid         the amount of bid.
/// @param signature   an ecdsa signature by the bidder’s private key
///                    on the abi encoded tuple
///                    (uint16 domainValue, uint64 chainId, uint64 roundNumber, uint256 amount)
///                    where domainValue is a constant used for domain separation.
struct Bid {
    // replay protection need
    // chain id
    // contract address
    // round
    address expressLaneController;
    uint256 amount;
    bytes signature;
}

// CHRIS: TODO: if we just have two stages we dont require an enum? and we dont require stages at all, just booleans
enum RoundStage {
    Bidding,
    Resolving
}
