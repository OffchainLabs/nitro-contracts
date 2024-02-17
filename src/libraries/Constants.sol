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

/// @dev Max amount of erc20 native token that can deposit when upscaling is required (i.e. < 18 decimals)
///      Amounts higher than this would risk uint256 overflows when adjusting decimals. Considering
///      18 decimals are 60 bits, we choose 2^192 as the limit which equals to ~6.3*10^57 weis of token
uint256 constant MAX_UPSCALE_AMOUNT = type(uint192).max;
