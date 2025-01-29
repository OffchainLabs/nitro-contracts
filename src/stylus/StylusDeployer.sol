// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
// CHRIS: TODO: fix to a specific sol version
import {ArbWasm} from "../precompiles/ArbWasm.sol";

// 0. scrub useless comments
// 1. docs and tests - how can we do that? fork test? nope, that wont work either? e2e test with the testnode
// 2. should this contract be deployable at the same address on all chains? yes, deploy from one of the existing proxies - that's a decent reason to use solidity tbh is it tho, cos we could use an existing deployer i think
// 3. we want to support create2 so that people can have the same stylus contract on multiple chains if they want to - does that matter? yes for some users
//    even bother with create1? people can choose a random nonce if they dont care - let them inject a salt, or just use the current account nonce
//    maybe create2 doesnt make sense for this use case since all have empty constructors? can we use the init code as a salt? yes + a user salt + the value

// CHRIS: TODO: add create2 util getter
// CHRIS: TODO: get the init return data - either bubble it up in revert if fail or log and return if success
// CHRIS: TODO: decide whether to add full data to the event: initData, initValue, salt, msg.sender, initReturnVal, whether init occurred
// CHRIS: TODO: public helper for the salt?

contract StylusDeployer {
    ArbWasm constant ARB_WASM = ArbWasm(0x0000000000000000000000000000000000000071);

    // CHRIS: TODO: check all events and errors for usage
    event ContractDeployed(address deployedContract);

    error ContractDeploymentError(bytes bytecode);
    error ContractInitializationError(address newContract);
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
    /// @dev CHRIS: TODO
    /// @param bytecode The bytecode of the stylus contract to be deployed
    /// @param initData Initialisation call data. After deployment the contract will be called with this data
    ///                 If no initialisation data is provided then the newly deployed contract will not be called.
    ///                 This means that the fallback function cannot be called from this contract, only named functions can be.
    /// @param initValue Initialisation value. After deployment, the contract will be called with the init data and this value.
    ///                  At least as much eth as init value must be provided with this call. Init value is specified here separately
    ///                  rather than using the msg.value since the msg.value may need to be greater than the init value to accomodate activation data fee.
    ///                  See the @notice block above for more details.
    /// @param salt If a non zero salt is provided the contract will be created using CREATE2 instead of CREATE
    ///             The supplied salt will be hashed with the initData and the initValue so that wherever the address is observed
    ///             it was initialised with the same variables.
    /// @return The address of the deployed conract
    function deploy(
        bytes calldata bytecode,
        bytes calldata initData,
        uint256 initValue,
        bytes32 salt
    ) public payable returns (address) {
        if (salt != 0) {
            // if a salt was supplied, hash the salt with init value and init data. This guarantees that
            // anywhere the address of this contract is seen the same init data and value were used.
            salt = initSalt(salt, initData, initValue);
        }

        address newContractAddress = deployContract(bytecode, salt);
        bool shouldActivate = requiresActivation(newContractAddress);
        if (shouldActivate) {
            // ensure there will be enough left over for init
            uint256 activationValue = msg.value - initValue;
            ARB_WASM.activateProgram{value: activationValue}(newContractAddress);
        }

        // initialize - this will fail if the program wasn't activated by this point
        // we check if initData exists to avoid calling contracts unnecessarily
        // CHRIS: TODO: test the above comment - and should we give a kinder error for that case? should be a nice one
        // CHRIS: TODO: test what happens when a stylus contract is called with a empty data - we hit the fallback i guess?
        //            : we're not gonna support that here, so that needs to be documented
        // CHRIS: TODO: should we just call everytime?
        if (initData.length != 0) {
            (bool success, ) = address(newContractAddress).call{value: initValue}(initData);
            if (!success) {
                revert ContractInitializationError(newContractAddress);
            }
        } else if (initValue != 0) {
            // if initValue exists init data should too
            revert InitValueButNotInitData();
        }

        // refund any remaining value if:
        // - activation can return some to this contract
        // - some activation value was supplied but not used
        if (shouldActivate || msg.value != initValue) {
            // CHRIS: TODO: balance or just the expected amount - someone could force a refund this way otherwise
            uint256 bal = address(this).balance;
            if (bal != 0) {
                (bool sent, ) = payable(msg.sender).call{value: bal}("");
                // CHRIS: TODO: if we keep this we need to add it to the docs that the caller must be payable
                // CHRIS: TODO: someone can put funds into the here and cause a revert. Maybe we should calculate instead of using balance
                if (!sent) {
                    revert RefundExcessValueError(bal);
                }
            }
        }

        // activation already emits the following event:
        // event ProgramActivated(bytes32 indexed codehash, bytes32 moduleHash, address program, uint256 dataFee, uint16 version);
        emit ContractDeployed(newContractAddress);

        return newContractAddress;
    }

    // CHRIS: TODO: natspec
    function initSalt(
        bytes32 salt,
        bytes calldata initData,
        uint256 initValue
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(salt, initData, initValue));
    }

    function requiresActivation(address addr) public view returns (bool) {
        // currently codeHashVersion returns an error when codeHashVersion != stylus version
        // so we do a try/catch to to check it
        uint16 codeHashVersion;
        try ARB_WASM.codehashVersion(addr.codehash) returns (uint16 version) {
            codeHashVersion = version;
        } catch {
            // stylus version is always >= 1
            codeHashVersion = 0;
        }

        // CHRIS: TODO: decide whether we make this forward compatible or not - arguably not, then we can get rid of the below check and just return != 0

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
                // bubble up the revert if there was one
                if and(iszero(newContractAddress), not(iszero(returndatasize()))) {
                    let p := mload(0x40)
                    returndatacopy(p, 0, returndatasize())
                    revert(p, returndatasize())
                }
            }
        } else {
            assembly {
                newContractAddress := create(0, add(bytecode, 0x20), mload(bytecode))
                // bubble up the revert if there was one
                if and(iszero(newContractAddress), not(iszero(returndatasize()))) {
                    let p := mload(0x40)
                    returndatacopy(p, 0, returndatasize())
                    revert(p, returndatasize())
                }
            }
        }

        if (newContractAddress == address(0)) {
            revert ContractDeploymentError(bytecode);
        }

        return newContractAddress;
    }
}
