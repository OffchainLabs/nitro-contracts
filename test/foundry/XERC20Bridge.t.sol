// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "./util/TestUtil.sol";
import {IXERC20 as IXERC20Base, XERC20} from "./util/XERC20.sol";
import "./AbsBridge.t.sol";
import "../../src/bridge/XERC20Bridge.sol";
import "../../src/bridge/ERC20Inbox.sol";
import "../../src/bridge/IEthBridge.sol";
import "../../src/libraries/AddressAliasHelper.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

import "forge-std/console.sol";

contract XERC20BridgeTest is AbsBridgeTest {
    IERC20Bridge public xerc20Bridge;
    XERC20 public nativeToken;

    address public tokenIssuer = makeAddr("tokenIssuer");

    uint256 public constant MAX_DATA_SIZE = 117_964;

    // msg details
    uint8 public kind = 7;
    bytes32 public messageDataHash = keccak256(abi.encodePacked("some msg"));
    uint256 public tokenFeeAmount = 30;

    function setUp() public {
        // deploy token and bridge
        nativeToken = new XERC20("Appchain Token", "App", tokenIssuer);
        bridge = XERC20Bridge(TestUtil.deployProxy(address(new XERC20Bridge())));
        xerc20Bridge = IERC20Bridge(address(bridge));

        // init bridge
        xerc20Bridge.initialize(IOwnable(rollup), address(nativeToken));

        // deploy inbox
        inbox = address(TestUtil.deployProxy(address(new ERC20Inbox(MAX_DATA_SIZE))));
        IERC20Inbox(address(inbox)).initialize(bridge, ISequencerInbox(seqInbox));

        // set issuer as minter for testing
        vm.prank(tokenIssuer);
        nativeToken.setLimits(tokenIssuer, tokenFeeAmount * 10, tokenFeeAmount * 10);

        // xerc20Bridge must to be a XERC20 bridge
        vm.prank(tokenIssuer);
        nativeToken.setLimits(address(xerc20Bridge), type(uint256).max / 2, type(uint256).max / 2);
    }

    /* solhint-disable func-name-mixedcase */
    function test_initialize() public {
        assertEq(
            address(xerc20Bridge.nativeToken()),
            address(nativeToken),
            "Invalid nativeToken ref"
        );
        assertEq(address(bridge.rollup()), rollup, "Invalid rollup ref");
        assertEq(bridge.activeOutbox(), address(0), "Invalid activeOutbox ref");
        assertEq(
            IERC20Bridge(address(bridge)).nativeTokenDecimals(),
            18,
            "Invalid native token decimals"
        );
    }

    function test_initialize_revert_ZeroAddressToken() public {
        XERC20Bridge noTokenBridge = XERC20Bridge(
            TestUtil.deployProxy(address(new XERC20Bridge()))
        );
        vm.expectRevert(abi.encodeWithSelector(InvalidTokenSet.selector, address(0)));
        noTokenBridge.initialize(IOwnable(rollup), address(0));
    }

    function test_initialize_ERC20_LessThan18Decimals() public {
        ERC20 _nativeToken = new ERC20_6Decimals();
        XERC20Bridge _bridge = XERC20Bridge(TestUtil.deployProxy(address(new XERC20Bridge())));

        _bridge.initialize(IOwnable(makeAddr("_rollup")), address(_nativeToken));
        assertEq(_bridge.nativeTokenDecimals(), 6, "Invalid native token decimals");
    }

    function test_initialize_ERC20_NoDecimals() public {
        ERC20NoDecimals _nativeToken = new ERC20NoDecimals();
        XERC20Bridge _bridge = XERC20Bridge(TestUtil.deployProxy(address(new XERC20Bridge())));

        _bridge.initialize(IOwnable(makeAddr("_rollup")), address(_nativeToken));
        assertEq(_bridge.nativeTokenDecimals(), 0, "Invalid native token decimals");
    }

    function test_initialize_revert_37Decimals() public {
        ERC20_37Decimals _nativeToken = new ERC20_37Decimals();
        XERC20Bridge _bridge = XERC20Bridge(TestUtil.deployProxy(address(new XERC20Bridge())));

        vm.expectRevert(abi.encodeWithSelector(NativeTokenDecimalsTooLarge.selector, 37));
        _bridge.initialize(IOwnable(makeAddr("_rollup")), address(_nativeToken));
    }

    function test_initialize_revert_ReInit() public {
        vm.expectRevert("Initializable: contract is already initialized");
        xerc20Bridge.initialize(IOwnable(rollup), address(nativeToken));
    }

    function test_initialize_revert_NonDelegated() public {
        IERC20Bridge noTokenBridge = new XERC20Bridge();
        vm.expectRevert("Function must be called through delegatecall");
        noTokenBridge.initialize(IOwnable(rollup), address(nativeToken));
    }

    function test_enqueueDelayedMessage() public {
        // add fee tokens to inbox
        vm.prank(tokenIssuer);
        nativeToken.mint(inbox, tokenFeeAmount);
        vm.prank(tokenIssuer);
        nativeToken.mint(user, tokenFeeAmount);

        // snapshot
        uint256 totalSupplyBefore = nativeToken.totalSupply();
        uint256 userNativeTokenBalanceBefore = nativeToken.balanceOf(address(user));
        uint256 bridgeNativeTokenBalanceBefore = nativeToken.balanceOf(address(bridge));
        uint256 inboxNativeTokenBalanceBefore = nativeToken.balanceOf(address(inbox));
        uint256 delayedMsgCountBefore = bridge.delayedMessageCount();

        // allow inbox
        vm.prank(rollup);
        bridge.setDelayedInbox(inbox, true);

        // approve bridge to burn tokens
        vm.prank(user);
        nativeToken.approve(address(bridge), tokenFeeAmount);

        // expect event
        vm.expectEmit(true, true, true, true);
        vm.fee(70);
        uint256 baseFeeToReport = 0;
        emit MessageDelivered(
            0,
            0,
            inbox,
            kind,
            AddressAliasHelper.applyL1ToL2Alias(user),
            messageDataHash,
            baseFeeToReport,
            uint64(block.timestamp)
        );

        // enqueue msg
        address userAliased = AddressAliasHelper.applyL1ToL2Alias(user);
        vm.prank(inbox);
        xerc20Bridge.enqueueDelayedMessage(kind, userAliased, messageDataHash, tokenFeeAmount);

        //// checks
        uint256 totalSupplyAfter = nativeToken.totalSupply();
        assertEq(totalSupplyAfter, totalSupplyBefore - tokenFeeAmount, "Invalid total supply");

        uint256 userNativeTokenBalanceAfter = nativeToken.balanceOf(address(user));
        assertEq(
            userNativeTokenBalanceAfter,
            userNativeTokenBalanceBefore,
            "Invalid user token balance"
        );

        uint256 bridgeNativeTokenBalanceAfter = nativeToken.balanceOf(address(bridge));
        assertEq(
            bridgeNativeTokenBalanceAfter,
            bridgeNativeTokenBalanceBefore,
            "Invalid bridge token balance"
        );

        uint256 inboxNativeTokenBalanceAfter = nativeToken.balanceOf(address(inbox));
        assertEq(
            inboxNativeTokenBalanceBefore - inboxNativeTokenBalanceAfter,
            tokenFeeAmount,
            "Invalid inbox token balance"
        );

        uint256 delayedMsgCountAfter = bridge.delayedMessageCount();
        assertEq(delayedMsgCountAfter - delayedMsgCountBefore, 1, "Invalid delayed message count");
    }

    function test_enqueueDelayedMessage_revert_UseEthForFees() public {
        // allow inbox
        vm.prank(rollup);
        bridge.setDelayedInbox(inbox, true);

        // enqueue msg
        hoax(inbox);
        vm.expectRevert();
        IEthBridge(address(bridge)).enqueueDelayedMessage{value: 0.1 ether}(
            kind,
            user,
            messageDataHash
        );
    }

    function test_enqueueDelayedMessage_revert_NotDelayedInbox() public {
        vm.prank(inbox);
        vm.expectRevert(abi.encodeWithSelector(NotDelayedInbox.selector, inbox));
        xerc20Bridge.enqueueDelayedMessage(kind, user, messageDataHash, tokenFeeAmount);
    }

    function test_executeCall_EmptyCalldata() public {
        // xerc20bridge can mint native tokens

        // allow outbox
        vm.prank(rollup);
        bridge.setOutbox(outbox, true);

        uint256 totalSupplyBefore = nativeToken.totalSupply();
        uint256 bridgeNativeTokenBalanceBefore = nativeToken.balanceOf(address(bridge));
        uint256 userTokenBalanceBefore = nativeToken.balanceOf(address(user));

        // call params
        uint256 withdrawalAmount = 15;
        bytes memory data = "";

        // expect event
        vm.expectEmit(true, true, true, true);
        emit BridgeCallTriggered(outbox, user, withdrawalAmount, data);

        //// execute call
        vm.prank(outbox);
        (bool success, ) = bridge.executeCall(user, withdrawalAmount, data);

        //// checks
        assertTrue(success, "Execute call failed");

        uint256 totalSupplyAfter = nativeToken.totalSupply();
        assertEq(
            totalSupplyAfter,
            totalSupplyBefore + withdrawalAmount,
            "Invalid bridge token balance"
        );

        uint256 bridgeNativeTokenBalanceAfter = nativeToken.balanceOf(address(bridge));
        assertEq(
            bridgeNativeTokenBalanceBefore,
            bridgeNativeTokenBalanceAfter,
            "Invalid bridge token balance"
        );

        uint256 userTokenBalanceAfter = nativeToken.balanceOf(address(user));
        assertEq(
            userTokenBalanceAfter - userTokenBalanceBefore,
            withdrawalAmount,
            "Invalid user token balance"
        );
    }

    function test_executeCall_ExtraCall() public {
        // xerc20bridge can mint native tokens

        // allow outbox
        vm.prank(rollup);
        bridge.setOutbox(outbox, true);

        // deploy some contract that will be call receiver
        EthVault vault = new EthVault();

        // native token balances
        uint256 totalSupplyBefore = nativeToken.totalSupply();
        uint256 bridgeNativeTokenBalanceBefore = nativeToken.balanceOf(address(bridge));
        uint256 vaultNativeTokenBalanceBefore = nativeToken.balanceOf(address(vault));

        // call params
        uint256 withdrawalAmount = 15;
        uint256 newVaultVersion = 7;
        bytes memory data = abi.encodeWithSelector(EthVault.setVersion.selector, newVaultVersion);

        // expect event
        vm.expectEmit(true, true, true, true);
        emit BridgeCallTriggered(outbox, address(vault), withdrawalAmount, data);

        //// execute call
        vm.prank(outbox);
        (bool success, ) = bridge.executeCall({
            to: address(vault),
            value: withdrawalAmount,
            data: data
        });

        //// checks
        assertTrue(success, "Execute call failed");
        assertEq(vault.version(), newVaultVersion, "Invalid newVaultVersion");

        uint256 totalSupplyAfter = nativeToken.totalSupply();
        assertEq(
            totalSupplyAfter,
            totalSupplyBefore + withdrawalAmount,
            "Invalid bridge token balance"
        );

        uint256 bridgeNativeTokenBalanceAfter = nativeToken.balanceOf(address(bridge));
        assertEq(
            bridgeNativeTokenBalanceBefore,
            bridgeNativeTokenBalanceAfter,
            "Invalid bridge native token balance"
        );

        uint256 vaultNativeTokenBalanceAfter = nativeToken.balanceOf(address(vault));
        assertEq(
            vaultNativeTokenBalanceAfter - vaultNativeTokenBalanceBefore,
            withdrawalAmount,
            "Invalid vault native token balance"
        );
    }

    function test_executeCall_UnsuccessfulExtraCall() public {
        // xerc20bridge can mint native tokens

        // allow outbox
        vm.prank(rollup);
        bridge.setOutbox(outbox, true);

        // deploy some contract that will be call receiver
        EthVault vault = new EthVault();

        // native token balances
        uint256 totalSupplyBefore = nativeToken.totalSupply();
        uint256 bridgeNativeTokenBalanceBefore = nativeToken.balanceOf(address(bridge));
        uint256 vaultNativeTokenBalanceBefore = nativeToken.balanceOf(address(vault));

        // call params
        uint256 withdrawalAmount = 15;
        bytes memory data = abi.encodeWithSelector(EthVault.justRevert.selector);

        // expect event
        vm.expectEmit(true, true, true, true);
        emit BridgeCallTriggered(outbox, address(vault), withdrawalAmount, data);

        //// execute call - do call which reverts
        vm.prank(outbox);
        (bool success, bytes memory returnData) = bridge.executeCall({
            to: address(vault),
            value: withdrawalAmount,
            data: data
        });

        //// checks
        assertEq(success, false, "Execute shall be unsuccessful");
        assertEq(vault.version(), 0, "Invalid vaultVersion");

        // get and assert revert reason
        assembly {
            returnData := add(returnData, 0x04)
        }
        string memory revertReason = abi.decode(returnData, (string));
        assertEq(revertReason, "bye", "Invalid revert reason");

        // bridge successfully sent native token even though extra call was unsuccessful (we didn't revert it)
        uint256 totalSupplyAfter = nativeToken.totalSupply();
        assertEq(
            totalSupplyAfter,
            totalSupplyBefore + withdrawalAmount,
            "Invalid bridge token balance"
        );

        uint256 bridgeNativeTokenBalanceAfter = nativeToken.balanceOf(address(bridge));
        assertEq(
            bridgeNativeTokenBalanceBefore,
            bridgeNativeTokenBalanceAfter,
            "Invalid bridge native token balance after unsuccessful extra call"
        );

        // vault successfully recieved native token even though extra call was unsuccessful (we didn't revert it)
        uint256 vaultNativeTokenBalanceAfter = nativeToken.balanceOf(address(vault));
        assertEq(
            vaultNativeTokenBalanceAfter - vaultNativeTokenBalanceBefore,
            withdrawalAmount,
            "Invalid vault native token balance after unsuccessful call"
        );
    }

    function test_executeCall_UnsuccessfulNativeTokenTransfer() public {
        // xerc20bridge can mint native tokens

        // allow outbox
        vm.prank(rollup);
        bridge.setOutbox(outbox, true);

        // deploy some contract that will be call receiver
        EthVault vault = new EthVault();

        // call params
        uint256 withdrawalAmount = 100;
        uint256 newVaultVersion = 9;
        bytes memory data = abi.encodeWithSelector(EthVault.setVersion.selector, newVaultVersion);

        // reduce minting limit
        address someAddress = makeAddr("someAddress");
        vm.prank(address(bridge));
        nativeToken.mint(someAddress, (type(uint256).max / 2) - withdrawalAmount + 1);

        //// execute call - do call which reverts on native token transfer due to invalid amount
        vm.prank(outbox);
        vm.expectRevert(IXERC20Base.IXERC20_NotHighEnoughLimits.selector);
        bridge.executeCall({to: address(vault), value: withdrawalAmount, data: data});
    }

    function test_executeCall_revert_NotOutbox() public {
        vm.expectRevert(abi.encodeWithSelector(NotOutbox.selector, address(this)));
        bridge.executeCall({to: user, value: 10, data: ""});
    }

    function test_executeCall_revert_NotContract() public {
        // allow outbox
        vm.prank(rollup);
        bridge.setOutbox(outbox, true);

        // executeCall shall revert when 'to' is not contract
        address to = address(234);
        vm.expectRevert(abi.encodeWithSelector(NotContract.selector, address(to)));
        vm.prank(outbox);
        bridge.executeCall({to: to, value: 10, data: "some data"});
    }

    function test_executeCall_revert_CallTargetNotAllowed() public {
        // allow outbox
        vm.prank(rollup);
        bridge.setOutbox(outbox, true);

        // executeCall shall revert when 'to' is not contract
        address to = address(nativeToken);
        vm.expectRevert(abi.encodeWithSelector(CallTargetNotAllowed.selector, to));
        vm.prank(outbox);
        bridge.executeCall({to: to, value: 10, data: "some data"});
    }

    function test_executeCall_revert_CallNotAllowed() public {
        // deploy and initi bridge contracts
        address _rollup = makeAddr("rollup");
        address _outbox = makeAddr("outbox");
        address _gateway = address(new MockGateway());
        address _nativeToken = address(new MockBridgedToken(_gateway));
        IERC20Bridge _bridge = IERC20Bridge(TestUtil.deployProxy(address(new XERC20Bridge())));
        _bridge.initialize(IOwnable(_rollup), address(_nativeToken));

        // allow outbox
        vm.prank(_rollup);
        _bridge.setOutbox(_outbox, true);

        vm.prank(_gateway);
        XERC20(_nativeToken).setLimits(
            address(_bridge),
            type(uint256).max / 2,
            type(uint256).max / 2
        );

        // fund bridge
        MockBridgedToken(_nativeToken).transfer(address(_bridge), 100 ether);

        // executeCall shall revert when call changes balance of the bridge
        address to = _gateway;
        uint256 withdrawAmount = 25 ether;
        bytes memory data = abi.encodeWithSelector(
            MockGateway.withdraw.selector,
            MockBridgedToken(_nativeToken),
            withdrawAmount
        );
        vm.expectRevert(abi.encodeWithSelector(CallNotAllowed.selector));
        vm.prank(_outbox);
        _bridge.executeCall({to: to, value: 10, data: data});
    }

    function test_executeCall_revert_CallNotAllowed_mint() public {
        // deploy and initi bridge contracts
        address _rollup = makeAddr("rollup");
        address _outbox = makeAddr("outbox");
        address _gateway = address(new MockGateway());
        address _nativeToken = address(new MockBridgedToken(_gateway));
        IERC20Bridge _bridge = IERC20Bridge(TestUtil.deployProxy(address(new XERC20Bridge())));
        _bridge.initialize(IOwnable(_rollup), address(_nativeToken));

        // allow outbox
        vm.prank(_rollup);
        _bridge.setOutbox(_outbox, true);

        vm.prank(_gateway);
        XERC20(_nativeToken).setLimits(
            address(_bridge),
            type(uint256).max / 2,
            type(uint256).max / 2
        );

        // fund bridge
        MockBridgedToken(_nativeToken).transfer(address(_bridge), 100 ether);

        // executeCall shall revert when call changes balance of the bridge
        address to = _gateway;
        uint256 withdrawAmount = 25 ether;
        bytes memory data = abi.encodeWithSelector(
            MockGateway.mint.selector,
            MockBridgedToken(_nativeToken),
            makeAddr("receiver"),
            withdrawAmount
        );
        vm.expectRevert(abi.encodeWithSelector(CallNotAllowed.selector));
        vm.prank(_outbox);
        _bridge.executeCall({to: to, value: 10, data: data});
    }
}

contract MockBridgedToken is XERC20 {
    address public gateway;

    constructor(address _gateway) XERC20("MockBridgedToken", "TT", _gateway) {
        gateway = _gateway;
        _mint(msg.sender, 1_000_000 ether);
    }

    function bridgeBurn(address account, uint256 amount) external {
        require(msg.sender == gateway, "ONLY_GATEWAY");
        _burn(account, amount);
    }

    function bridgeMint(address account, uint256 amount) external {
        require(msg.sender == gateway, "ONLY_GATEWAY");
        _mint(account, amount);
    }
}

contract MockGateway {
    function withdraw(MockBridgedToken token, uint256 amount) external {
        token.bridgeBurn(msg.sender, amount);
    }

    function mint(
        MockBridgedToken token,
        address receiver,
        uint256 amount
    ) external {
        token.bridgeMint(receiver, amount);
    }
}

/* solhint-disable contract-name-camelcase */
contract ERC20_6Decimals is ERC20 {
    constructor() ERC20("XY", "xy") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) public virtual {
        _mint(to, amount);
    }
}

/* solhint-disable contract-name-camelcase */
contract ERC20_20Decimals is ERC20 {
    constructor() ERC20("XY", "xy") {}

    function decimals() public pure override returns (uint8) {
        return 20;
    }

    function mint(address to, uint256 amount) public virtual {
        _mint(to, amount);
    }
}

/* solhint-disable contract-name-camelcase */
contract ERC20_37Decimals is ERC20 {
    constructor() ERC20("XY", "xy") {}

    function decimals() public pure override returns (uint8) {
        return 37;
    }

    function mint(address to, uint256 amount) public virtual {
        _mint(to, amount);
    }
}

/* solhint-disable contract-name-camelcase */
contract ERC20_36Decimals is ERC20 {
    constructor() ERC20("XY", "xy") {}

    function decimals() public pure override returns (uint8) {
        return 36;
    }

    function mint(address to, uint256 amount) public virtual {
        _mint(to, amount);
    }
}

contract ERC20NoDecimals is ERC20 {
    constructor() ERC20("XY", "xy") {}

    function decimals() public pure override returns (uint8) {
        revert("not supported");
    }

    function mint(address to, uint256 amount) public virtual {
        _mint(to, amount);
    }
}
