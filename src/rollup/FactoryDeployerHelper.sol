// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

/**
 * @title Helper contract for cross-chain deployment of deterministic factories when rollup uses custom fee token
 * @notice It bundles sending the fee token to inbox and invoking the factory deployment function.
 *         Prerequisite: fee token must be approved for this contract to send it to inbox.
 */
contract FactoryDeployerHelper {
    address public constant DEPLOY_HELPER = address(0x90D68B056c411015eaE3EC0b98AD94E2C91419F1);
    uint256 public constant MAX_FEE_PER_GAS = 100_000_000;

    function deploy(address inbox) external {
        deploy(inbox, MAX_FEE_PER_GAS);
    }

    function deploy(address inbox, uint256 maxFeePerGas) public {
        address bridge = address(IInboxBase(inbox).bridge());
        address feeToken = IERC20Bridge(bridge).nativeToken();

        uint256 amount = IDeployHelper(DEPLOY_HELPER).getDeploymentTotalCost(inbox, maxFeePerGas);
        IERC20(feeToken).transferFrom(msg.sender, inbox, amount);
        IDeployHelper(DEPLOY_HELPER).perform(inbox, feeToken, maxFeePerGas);
    }
}

interface IERC20 {
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);
}

interface IDeployHelper {
    function getDeploymentTotalCost(address inbox, uint256 maxFeePerGas)
        external
        view
        returns (uint256);

    function perform(
        address _inbox,
        address _nativeToken,
        uint256 _maxFeePerGas
    ) external payable;
}

interface IInboxBase {
    function bridge() external view returns (address);
}

interface IERC20Bridge {
    function nativeToken() external view returns (address);
}
