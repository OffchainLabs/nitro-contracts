// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
// CHRIS: TODO: fix the sol version
import { ArbWasm } from "../precompiles/ArbWasm.sol";

// 0. scrub useless comments
// 1. docs and tests - how can we do that? fork test? nope, that wont work either? e2e test with the testnode
// 2. should this contract be deployable at the same address on all chains? yes, deploy from one of the existing proxies - that's a decent reason to use solidity tbh is it tho, cos we could use an existing deployer i think
// 3. we want to support create2 so that people can have the same stylus contract on multiple chains if they want to - does that matter? yes for some users
//    even bother with create1? people can choose a random nonce if they dont care - let them inject a salt, or just use the current account nonce
//    maybe create2 doesnt make sense for this use case since all have empty constructors? can we use the init code as a salt? yes + a user salt + the value

// CHRIS: TODO: should we add caching to this contract? caching can be done by anyone at any time. It's not necessary
contract CargoStylusFactory {
    ArbWasm constant ARB_WASM = ArbWasm(0x0000000000000000000000000000000000000071);

    // CHRIS: TODO: check all events and errors for usage
    event ContractDeployed(address deployedContract);

    error ContractDeploymentError(bytes bytecode);
    error ContractInitializationError(address newContract);
    error RefundExcessValueError(uint256 excessValue);
    error EmptyBytecode();
    error InitValueButNotInitData();


    // CHRIS: TODO: consider breaking out the deploy func, it's got quite big now
    
    // if they dont need to activate, then whats the cost?
    // if they supply 0 activation value then we'll skip the step - they'll error out anyway 

    // CHRIS: TODO: document that this is the way to use this function:
    // 1. calculate code hash - how do? easy
    // 2. check if it's activated. easy
    // 3. estimate activation cost. 
    // 4. estimate deploy costs

    // CHRIS: TODO: include some of the following comments in the public dev docs
    // to deploy currently
    // 1. deploy the contract
    // 2. check activation, if not there, then estimate activation and activate
    // 3. init
    // we need to activate in order to init - therefore we have to do it here if we want it all together
    // caching is not the same - we can do that separately if we want to
    // ok, so here we can check activation but the user should have done that already
    // so we're just saving them some gas in the case of multiple deploys
    // CHRIS: TODO: document the behaviour of supplying enough value to activate
    //            : we would get a failure otherwise right? we want it to give the correct val, or fail

    /// @notice Deploy, activate and initialize a stylus contract
    ///         In order to call a stylus contract, and therefore initialize it, it must first be activated.
    ///         This contract provides an atomic way of deploying, activating and initializing a stylus contract.
    ///
    ///         Initialisation will be called if initData is supplied, other initialization is skipped
    ///         Activation is not always necessary. If a contract has the same code has as another recently activated
    ///         contract then activation will be skipped.
    ///
    ///         The caller should do the following before calling this contract:
    ///         1. Calculate the code hash that the deployed contract will have
    ///         2. Check if that code hash will require activation by calling ARB_WASM.codehashVersion and comparing with
    ///            the current ARB_WASM.stylusVersion
    ///         3. If activation is required then estimate the data fee of activation. Do this by spoofing the code at an address
    ///            then calling the ArbWasm.activateProgram and observing the returned dataFee
    ///         4. Next this deploy function can be called. The value of the call must be set to the previously ascertained dataFee + initValue
    ///            If activation is not require, the value of the call should be set to initValue
    /// @dev CHRIS: TODO
    /// @param bytecode CHRIS: TODO
    /// @param initData CHRIS: TODO
    /// @param initValue CHRIS: TODO
    /// @param salt CHRIS: TODO
    /// @return The address of the deployed conract
    function deploy(
        bytes calldata bytecode,
        bytes calldata initData,
        uint256 initValue,
        bytes32 salt
    ) public payable returns (address) {
        if(salt != 0) {
            // CHRIS: TODO: put this somewhere nicer?
            // hash the salt with init value and init data to guarantee that anywhere the address of this 
            // contract is seen the same init data and value were used
            salt = keccak256(abi.encodePacked(initValue, initData, salt));
        }
        address newContractAddress = deployContract(bytecode, salt);
        bool shouldActivate = requiresActivation(newContractAddress);
        if(shouldActivate) {
            // ensure there will be enough left over to call init with
            uint256 activationValue = msg.value - initValue;
            ARB_WASM.activateProgram{value: activationValue}(
                newContractAddress
            );
        }
        // initialize - this will fail if the program was activated by this point
        // CHRIS: TODO: test the above comment - and should we give a kinder error for that case?
        // CHRIS: TODO: test what happens when a stylus contract is called with a empty data - we hit the fallback i guess?
        //            : we're not gonna support that here, so that needs to be documented
        if(initData.length != 0) {
            (bool success, ) = address(newContractAddress).call{value: initValue}(initData);
            if (!success) {
                revert ContractInitializationError(newContractAddress);
            }
        } else if(initValue != 0) {
            // if initValue exists init data should too
            revert InitValueButNotInitData();
        }
        
        // refund any remaining value - activation can return some to this contract
        // CHRIS: TODO: should we only do this if the contract was actually activated?
        if(shouldActivate) {
            uint256 bal = address(this).balance;
            if(bal != 0) {
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

    function requiresActivation(address addr) public view returns(bool) {
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

    function deployContract(bytes memory bytecode, bytes32 salt) internal returns (address) {
        if(bytecode.length == 0) {
            revert EmptyBytecode();
        }

        address newContractAddress;

        if(salt != 0) {
            // CHRIS: TODO: use OZ for this?
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

    // CHRIS: TODO: add create2 util getter
    // CHRIS: TODO: get the init return data - either bubble it up in revert if fail or log and return if success
    // CHRIS: TODO: decide whether to add full data to the event: initData, initValue, salt, msg.sender, initReturnVal, whether init occurred
    // CHRIS: TODO: public helper for the salt?
}
