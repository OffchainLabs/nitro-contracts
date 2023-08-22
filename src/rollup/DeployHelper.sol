// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import {IInbox} from "../bridge/IInbox.sol";

/// @notice Helper contract for deploying deterministic factories to Arbitrum using delayed inbox
contract DeployHelper {
    address public constant ANVIL_CREATE2FACTORY_DEPLOYER =
        0x3fAB184622Dc19b6109349B94811493BF2a45362;
    bytes public constant ANVIL_CREATE2FACTORY_PAYLOAD =
            hex"04f8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222";
    
    address public constant ERC2470_DEPLOYER = 0xBb6e024b9cFFACB947A71991E386681B1Cd1477D;
    bytes public constant ERC2470_PAYLOAD =
            hex"04f9016c8085174876e8008303c4d88080b90154608060405234801561001057600080fd5b50610134806100206000396000f3fe6080604052348015600f57600080fd5b506004361060285760003560e01c80634af63f0214602d575b600080fd5b60cf60048036036040811015604157600080fd5b810190602081018135640100000000811115605b57600080fd5b820183602082011115606c57600080fd5b80359060200191846001830284011164010000000083111715608d57600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600092019190915250929550509135925060eb915050565b604080516001600160a01b039092168252519081900360200190f35b6000818351602085016000f5939250505056fea26469706673582212206b44f8a82cb6b156bfcc3dc6aadd6df4eefd204bc928a4397fd15dacf6d5320564736f6c634300060200331b83247000822470";
    
    address public constant ZOLTU_CREATE2FACTORY_DEPLOYER =
        0x4c8D290a1B368ac4728d83a9e8321fC3af2b39b1;
    bytes public constant ZOLTU_CREATE2FACTORY_PAYLOAD =
            hex"04f87e8085174876e800830186a08080ad601f80600e600039806000f350fe60003681823780368234f58015156014578182fd5b80825250506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222";

    uint256 internal constant GASLIMIT = 100000;
    uint256 internal constant MAXFEEPERGAS = 1000000000;

    function _fundAndDeploy(IInbox inbox, address _l2Address, bytes memory payload) internal {
        uint256 submissionCost = inbox.calculateRetryableSubmissionFee(0, block.basefee);
        inbox.createRetryableTicket{value: 0.01 ether + submissionCost + GASLIMIT * MAXFEEPERGAS}({
            to: _l2Address,
            l2CallValue: 0.01 ether,
            maxSubmissionCost: submissionCost,
            excessFeeRefundAddress: msg.sender,
            callValueRefundAddress: msg.sender,
            gasLimit: GASLIMIT,
            maxFeePerGas: MAXFEEPERGAS,
            data: ""
        });
        inbox.sendL2Message(
            payload
        );
    }


    function perform(address _inbox) external payable {
        IInbox inbox = IInbox(_inbox);

        _fundAndDeploy(inbox, ANVIL_CREATE2FACTORY_DEPLOYER, ANVIL_CREATE2FACTORY_PAYLOAD);
        _fundAndDeploy(inbox, ERC2470_DEPLOYER, ERC2470_PAYLOAD);
        _fundAndDeploy(inbox, ZOLTU_CREATE2FACTORY_DEPLOYER, ZOLTU_CREATE2FACTORY_PAYLOAD);

        payable(msg.sender).transfer(address(this).balance);
    }
}
