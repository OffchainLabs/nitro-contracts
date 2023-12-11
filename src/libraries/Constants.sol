// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.4;

uint64 constant NO_CHAL_INDEX = 0;

// Expected seconds per block in Ethereum PoS
uint256 constant ETH_POS_BLOCK_TIME = 12;

/// @dev If nativeTokenDecimals is different than 18 decimals, bridge will inflate or deflate token amounts
///      when depositing to child chain to match 18 decimal denomination. Opposite process happens when
///      amount is withdrawn back to parent chain. In order to avoid uint256 overflows we restrict max number
///      of decimals to 36 which should be enough for most practical use-cases.
uint8 constant MAX_ALLOWED_NATIVE_TOKEN_DECIMALS = uint8(36);

/// @dev Max amount that can be moved from parent chain to child chain. Also the max amount that can be
///      claimed on parent chain after withdrawing it from child chain. Amounts higher than this would
///      risk uint256 overflows. This amount is derived from the fact that we have set MAX_ALLOWED_NATIVE_TOKEN_DECIMALS
///      to 36 which means that in the worst case we are inflating by 18 decimals points. This constant
///      equals to ~1.1*10^59 tokens
uint256 constant MAX_BRIDGEABLE_AMOUNT = type(uint256).max / 10**18;