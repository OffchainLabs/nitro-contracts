// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract NoZeroTransferToken is ERC20PresetFixedSupply {
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply,
        address owner
    ) ERC20PresetFixedSupply(name_, symbol_, initialSupply, owner) {}

    function _transfer(address from, address to, uint256 amount) internal virtual override {
        require(amount > 0, "NoZeroTransferToken: zero transfer");
        super._transfer(from, to, amount);
    }
}
