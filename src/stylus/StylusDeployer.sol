// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ArbWasm} from "../precompiles/ArbWasm.sol";

/// @title A Stylus contract deployer, activator and initializer
/// @author The name of the author
/// @notice Stylus contracts do not support constructors. Instead, Stylus devs can use this contract to deploy and
///         initialize their contracts atomically
contract StylusDeployer {
    ArbWasm constant ARB_WASM = ArbWasm(0x0000000000000000000000000000000000000071);

    event ContractDeployed(address deployedContract);

    error ContractDeploymentError(bytes bytecode);
    error ContractInitializationError(address newContract, bytes data);
    error RefundExcessValueError(uint256 excessValue);
    error EmptyBytecode();
    error InitValueButNotInitData();

    /// @notice Deploy, activate and initialize a stylus contract
    ///         In order to call a stylus contract, and therefore initialize it, it must first be activated.
    ///         This contract provides an atomic way of deploying, activating and initializing a stylus contract.
    ///
    ///         Initialisation will be called if initData is supplied, other initialization is skipped
    ///         Activation is not always necessary. If a contract has the same code has as another recently activated
    ///         contract then activation will be skipped.
    ///         If additional value remains in the contract after activation it will be transferred to the msg.sender
    ///         to that end the caller must ensure that they can receive eth.
    ///
    ///         The caller should do the following before calling this contract:
    ///         1. Check whether the contract will require activation, and if so what the cost will be.
    ///            This can be done by spoofing an address with the contract code, then calling ArbWasm.programVersion to compare the
    ///            the returned result against ArbWasm.stylusVersion. If activation is required ArbWasm.activateProgram can then be called
    ///            to find the returned dataFee.
    ///         2. Next this deploy function can be called. The value of the call must be set to the previously ascertained dataFee + initValue
    ///            If activation is not require, the value of the call should be set to initValue
    ///
    ///         Note: Stylus contract caching is not done by the deployer, and will have to be done separately after deployment.
    ///         See https://docs.arbitrum.io/stylus/how-tos/caching-contracts for more details on caching
    /// @param bytecode The bytecode of the stylus contract to be deployed
    /// @param initData Initialisation call data. After deployment the contract will be called with this data
    ///                 If no initialisation data is provided then the newly deployed contract will not be called.
    ///                 This means that the receive or dataless fallback function cannot be called from this contract.
    /// @param initValue Initialisation value. After deployment, the contract will be called with the init data and this value.
    ///                  At least as much eth as init value must be provided with this call. Init value is specified here separately
    ///                  rather than using the msg.value since the msg.value may need to be greater than the init value to accomodate activation data fee.
    ///                  See the @notice block above for more details.
    /// @param salt If a non zero salt is provided the contract will be created using CREATE2 instead of CREATE
    ///             The supplied salt will be hashed with the initData so that wherever the address is observed
    ///             it was initialised with the same variables.
    /// @return The address of the deployed conract
    function deploy(
        bytes calldata bytecode,
        bytes calldata initData,
        uint256 initValue,
        bytes32 salt
    ) public payable returns (address) {
        if (salt != 0) {
            // if a salt was supplied, hash the salt with the init data. This guarantees that
            // anywhere the address of this contract is seen the same init data was used
            salt = initSalt(salt, initData);
        }

        address newContractAddress = deployContract(bytecode, salt);
        bool shouldActivate = requiresActivation(newContractAddress);
        uint256 dataFee = 0;
        if (shouldActivate) {
            // ensure there will be enough left over for init
            // activateProgram will return unused value back to this contract without an EVM call
            uint256 activationValue = msg.value - initValue;
            (, dataFee) = ARB_WASM.activateProgram{value: activationValue}(newContractAddress);
        }

        // initialize - this will fail if the program wasn't activated by this point
        // we check if initData exists to avoid calling contracts unnecessarily
        if (initData.length != 0) {
            (bool success, bytes memory data) =
                address(newContractAddress).call{value: initValue}(initData);
            if (!success) {
                revert ContractInitializationError(newContractAddress, data);
            }
        } else if (initValue != 0) {
            // if initValue exists init data should too
            revert InitValueButNotInitData();
        }

        // refund any remaining value
        uint256 bal = msg.value - dataFee - initValue;
        if (bal != 0) {
            // the caller must be payable
            (bool sent,) = payable(msg.sender).call{value: bal}("");
            if (!sent) {
                revert RefundExcessValueError(bal);
            }
        }

        // activation already emits the following event:
        // event ProgramActivated(bytes32 indexed codehash, bytes32 moduleHash, address program, uint256 dataFee, uint16 version);
        emit ContractDeployed(newContractAddress);

        return newContractAddress;
    }

    /// @notice When using CREATE2 the deployer includes the init data and value in the salt so that callers
    ///         can be sure that wherever they encourter this address it was initialized with the same data and value
    /// @param salt A user supplied salt
    /// @param initData The init data that will be used to init the deployed contract
    function initSalt(bytes32 salt, bytes calldata initData) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(salt, initData));
    }

    /// @notice Checks whether a contract requires activation
    function requiresActivation(
        address addr
    ) public view returns (bool) {
        // currently codeHashVersion returns an error when codeHashVersion != stylus version
        // so we do a try/catch to to check it
        uint16 codeHashVersion;
        try ARB_WASM.codehashVersion(addr.codehash) returns (uint16 version) {
            codeHashVersion = version;
        } catch {
            // stylus version is always >= 1
            codeHashVersion = 0;
        }

        // due to the bug in ARB_WASM.codeHashVersion we know that codeHashVersion will either be 0 or the current
        // version. We still check that is not equal to the stylusVersion
        return codeHashVersion != ARB_WASM.stylusVersion();
    }

    /// @notice Deploy the a contract with the supplied bytecode.
    ///         Will create2 if the supplied salt is non zero
    function deployContract(bytes memory bytecode, bytes32 salt) internal returns (address) {
        if (bytecode.length == 0) {
            revert EmptyBytecode();
        }

        address newContractAddress;
        if (salt != 0) {
            assembly {
                newContractAddress := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
            }
        } else {
            assembly {
                newContractAddress := create(0, add(bytecode, 0x20), mload(bytecode))
            }
        }

        // bubble up the revert if there was one
        assembly {
            if and(iszero(newContractAddress), not(iszero(returndatasize()))) {
                let p := mload(0x40)
                returndatacopy(p, 0, returndatasize())
                revert(p, returndatasize())
            }
        }

        if (newContractAddress == address(0)) {
            revert ContractDeploymentError(bytecode);
        }

        return newContractAddress;
    }
}
