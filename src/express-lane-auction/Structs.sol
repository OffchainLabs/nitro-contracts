// SPDX-License-Identifier: UNLICENSED
// CHRIS: TODO: choose sol version
pragma solidity ^0.8.9;

/// @notice A bid to control the express lane for a specific round
struct Bid {
    /// @notice The address to be set as the express lane controller if this bid wins the auction round
    address expressLaneController;
    /// @notice The maximum amount the bidder is willing to pay if they win the round
    ///         The auction is a second price auction, so the winner may end up paying less than this amount
    ///         however this is the maximum amount up to which they may have to pay
    uint256 amount;
    // CHRIS: TODO: update the specs for this
    /// @notice Authentication of this bid by the bidder.
    ///         The bidder signs over a hash of the following
    ///         keccak256("\x19Ethereum Signed Message:\n32" ++ keccak(chainId ++ auctionContractAddress ++ auctionRound ++ bidAmount ++ expressLaneController))
    bytes signature;
}