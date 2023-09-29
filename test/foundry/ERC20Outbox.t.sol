// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./AbsOutbox.t.sol";
import "./ERC20Inbox.t.sol";
import "../../src/bridge/ERC20Bridge.sol";
import "../../src/bridge/ERC20Outbox.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract ERC20OutboxTest is AbsOutboxTest {
    ERC20Outbox public erc20Outbox;
    ERC20Bridge public erc20Bridge;
    IERC20 public nativeToken;

    function setUp() public {
        // deploy token, bridge and outbox
        nativeToken = new ERC20PresetFixedSupply("Appchain Token", "App", 1_000_000, address(this));
        bridge = IBridge(TestUtil.deployProxy(address(new ERC20Bridge())));
        erc20Bridge = ERC20Bridge(address(bridge));
        outbox = IOutbox(TestUtil.deployProxy(address(new ERC20Outbox())));
        erc20Outbox = ERC20Outbox(address(outbox));

        // init bridge and outbox
        erc20Bridge.initialize(IOwnable(rollup), address(nativeToken));
        erc20Outbox.initialize(IBridge(bridge));

        vm.prank(rollup);
        bridge.setOutbox(address(outbox), true);

        // fund user account
        nativeToken.transfer(user, 1000);
    }

    /* solhint-disable func-name-mixedcase */
    function test_initialize_ERC20() public {
        assertEq(erc20Outbox.nativeTokenDecimals(), 18, "Invalid native token decimals");
        assertEq(erc20Outbox.l2ToL1WithdrawalAmount(), 0, "Invalid withdrawalAmount");
    }

    function test_initialize_ERC20_LessThan18Decimals() public {
        ERC20 _nativeToken = new ERC20_6Decimals();
        ERC20Bridge _bridge = ERC20Bridge(TestUtil.deployProxy(address(new ERC20Bridge())));
        ERC20Outbox _outbox = ERC20Outbox(TestUtil.deployProxy(address(new ERC20Outbox())));
        _bridge.initialize(IOwnable(makeAddr("rollup")), address(_nativeToken));
        _outbox.initialize(IBridge(_bridge));

        assertEq(_outbox.nativeTokenDecimals(), 6, "Invalid native token decimals");
    }

    function test_initialize_ERC20_NoDecimals() public {
        ERC20 _nativeToken = new ERC20NoDecimals();
        ERC20Bridge _bridge = ERC20Bridge(TestUtil.deployProxy(address(new ERC20Bridge())));
        ERC20Outbox _outbox = ERC20Outbox(TestUtil.deployProxy(address(new ERC20Outbox())));
        _bridge.initialize(IOwnable(makeAddr("rollup")), address(_nativeToken));
        _outbox.initialize(IBridge(_bridge));

        assertEq(_outbox.nativeTokenDecimals(), 0, "Invalid native token decimals");
    }

    function test_initialize_revert_AlreadyInit() public {
        vm.expectRevert(abi.encodeWithSelector(AlreadyInit.selector));
        erc20Outbox.initialize(IBridge(bridge));
    }

    function test_initialize_revert_DecimalsTooLarge() public {
        ERC20 _nativeToken = new ERC20_37Decimals();
        ERC20Bridge _bridge = ERC20Bridge(TestUtil.deployProxy(address(new ERC20Bridge())));
        ERC20Outbox _outbox = ERC20Outbox(TestUtil.deployProxy(address(new ERC20Outbox())));
        _bridge.initialize(IOwnable(makeAddr("rollup")), address(_nativeToken));

        vm.expectRevert(abi.encodeWithSelector(NativeTokenDecimalsTooLarge.selector, 37));
        _outbox.initialize(IBridge(_bridge));
    }

    function test_executeTransaction() public {
        // fund bridge with some tokens
        vm.startPrank(user);
        nativeToken.approve(address(bridge), 100);
        nativeToken.transfer(address(bridge), 100);
        vm.stopPrank();

        // store root
        vm.prank(rollup);
        outbox.updateSendRoot(
            0x7e87df146feb0900d5a441d1d081867190b34395307698f4e879c8164cd9a7f9,
            0x7e87df146feb0900d5a441d1d081867190b34395307698f4e879c8164cd9a7f9
        );

        // create msg receiver on L1
        ERC20L2ToL1Target target = new ERC20L2ToL1Target();
        target.setOutbox(address(outbox));

        //// execute transaction
        uint256 bridgeTokenBalanceBefore = nativeToken.balanceOf(address(bridge));
        uint256 targetTokenBalanceBefore = nativeToken.balanceOf(address(target));

        bytes32[] memory proof = new bytes32[](5);
        proof[0] = bytes32(0x1216ff070e3c87b032d79b298a3e98009ddd13bf8479b843e225857ca5f950e7);
        proof[1] = bytes32(0x2b5ee8f4bd7664ca0cf31d7ab86119b63f6ff07bb86dbd5af356d0087492f686);
        proof[2] = bytes32(0x0aa797064e0f3768bbac0a02ce031c4f282441a9cd8c669086cf59a083add893);
        proof[3] = bytes32(0xc7aac0aad5108a46ac9879f0b1870fd0cbc648406f733eb9d0b944a18c32f0f8);
        proof[4] = bytes32(0x477ce2b0bc8035ae3052b7339c7496531229bd642bb1871d81618cf93a4d2d1a);

        uint256 withdrawalAmount = 15;
        bytes memory data = abi.encodeWithSignature("receiveHook()");
        outbox.executeTransaction({
            proof: proof,
            index: 12,
            l2Sender: user,
            to: address(target),
            l2Block: 300,
            l1Block: 20,
            l2Timestamp: 1234,
            value: withdrawalAmount,
            data: data
        });

        uint256 bridgeTokenBalanceAfter = nativeToken.balanceOf(address(bridge));
        assertEq(
            bridgeTokenBalanceBefore - bridgeTokenBalanceAfter,
            withdrawalAmount,
            "Invalid bridge token balance"
        );

        uint256 targetTokenBalanceAfter = nativeToken.balanceOf(address(target));
        assertEq(
            targetTokenBalanceAfter - targetTokenBalanceBefore,
            withdrawalAmount,
            "Invalid target token balance"
        );

        /// check context was properly set during execution
        assertEq(uint256(target.l2Block()), 300, "Invalid l2Block");
        assertEq(uint256(target.timestamp()), 1234, "Invalid timestamp");
        assertEq(uint256(target.outputId()), 12, "Invalid outputId");
        assertEq(target.sender(), user, "Invalid sender");
        assertEq(uint256(target.l1Block()), 20, "Invalid l1Block");
        assertEq(uint256(target.withdrawalAmount()), withdrawalAmount, "Invalid withdrawalAmount");
    }

    function test_executeTransaction_revert_CallTargetNotAllowed() public {
        // // fund bridge with some tokens
        vm.startPrank(user);
        nativeToken.approve(address(bridge), 100);
        nativeToken.transfer(address(bridge), 100);
        vm.stopPrank();

        // store root
        vm.prank(rollup);
        outbox.updateSendRoot(
            0x5b6cd410f78e45e55eeb02133b8e72e6ca122c59b667eed4f214e374d808058e,
            0x5b6cd410f78e45e55eeb02133b8e72e6ca122c59b667eed4f214e374d808058e
        );

        //// execute transaction
        uint256 bridgeTokenBalanceBefore = nativeToken.balanceOf(address(bridge));
        uint256 userTokenBalanceBefore = nativeToken.balanceOf(address(user));

        bytes32[] memory proof = new bytes32[](5);
        proof[0] = bytes32(0x1216ff070e3c87b032d79b298a3e98009ddd13bf8479b843e225857ca5f950e7);
        proof[1] = bytes32(0x2b5ee8f4bd7664ca0cf31d7ab86119b63f6ff07bb86dbd5af356d0087492f686);
        proof[2] = bytes32(0x0aa797064e0f3768bbac0a02ce031c4f282441a9cd8c669086cf59a083add893);
        proof[3] = bytes32(0xc7aac0aad5108a46ac9879f0b1870fd0cbc648406f733eb9d0b944a18c32f0f8);
        proof[4] = bytes32(0x477ce2b0bc8035ae3052b7339c7496531229bd642bb1871d81618cf93a4d2d1a);

        uint256 withdrawalAmount = 15;

        address invalidTarget = address(nativeToken);

        vm.expectRevert(abi.encodeWithSelector(CallTargetNotAllowed.selector, invalidTarget));
        outbox.executeTransaction({
            proof: proof,
            index: 12,
            l2Sender: user,
            to: invalidTarget,
            l2Block: 300,
            l1Block: 20,
            l2Timestamp: 1234,
            value: withdrawalAmount,
            data: ""
        });

        uint256 bridgeTokenBalanceAfter = nativeToken.balanceOf(address(bridge));
        assertEq(bridgeTokenBalanceBefore, bridgeTokenBalanceAfter, "Invalid bridge token balance");

        uint256 userTokenBalanceAfter = nativeToken.balanceOf(address(user));
        assertEq(userTokenBalanceAfter, userTokenBalanceBefore, "Invalid user token balance");
    }

    function test_executeTransaction_DecimalsLessThan18() public {
        // create token/bridge/inbox
        uint8 decimals = 6;
        ERC20 _nativeToken = new ERC20_6Decimals();

        IERC20Bridge _bridge = IERC20Bridge(TestUtil.deployProxy(address(new ERC20Bridge())));
        IERC20Inbox _inbox = IERC20Inbox(TestUtil.deployProxy(address(new ERC20Inbox())));
        ERC20Outbox _outbox = ERC20Outbox(TestUtil.deployProxy(address(new ERC20Outbox())));

        // init bridge and inbox
        address _rollup = makeAddr("_rollup");
        _bridge.initialize(IOwnable(_rollup), address(_nativeToken));
        _inbox.initialize(_bridge, ISequencerInbox(makeAddr("_seqInbox")));
        _outbox.initialize(IBridge(address(_bridge)));
        vm.prank(_rollup);
        _bridge.setOutbox(address(_outbox), true);

        // fund bridge with some tokens
        ERC20_6Decimals(address(_nativeToken)).mint(address(_bridge), 1_000_000 * 10 ** decimals);

        // store root
        vm.prank(_rollup);
        _outbox.updateSendRoot(
            0x3c66096729d57a3c7528dc23097e4a7b800e7e52d4a8d71105f07e94177ae2a1,
            0x3c66096729d57a3c7528dc23097e4a7b800e7e52d4a8d71105f07e94177ae2a1
        );

        // create msg receiver on L1
        ERC20L2ToL1Target target = new ERC20L2ToL1Target();
        target.setOutbox(address(_outbox));

        //// execute transaction
        uint256 bridgeTokenBalanceBefore = _nativeToken.balanceOf(address(_bridge));
        uint256 targetTokenBalanceBefore = _nativeToken.balanceOf(address(target));

        bytes32[] memory proof = new bytes32[](17);
        proof[0] = bytes32(0x374de32809f4525d60cb461de130464fddfccb4684cfdbce7016f11f3a2118cf);
        proof[1] = bytes32(0x08ea4de37e43c6407da28848d26b37a56661caf119ab1d67d9af8ec76bca2d0d);
        proof[2] = bytes32(0x934fbafba47f664a03dde194b1d8a8211a39ae0c07d6ecc903252576e261307c);
        proof[3] = bytes32(0xf76d8c825305d7a261a874e863922214f1ad9b2fa833725080d4b2de6678d948);
        proof[4] = bytes32(0xdf1a4d32f399d99a9c2a633d63c7bfc15ee39bb8d51ee9e30328965b70248387);
        proof[5] = bytes32(0xe0a0781562562fca15375998f0c80ed72aa6cf5ed772c061150f1d3f0284f9cb);
        proof[6] = bytes32(0x190e26dd23006cce5d90fced90b381385517ca7f189af5a409343a6d50d52c14);
        proof[7] = bytes32(0xbf38be925e8044790f45f3a52cb13606b61a3a3d35823d2e304f50755107eeb9);
        proof[8] = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);
        proof[9] = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);
        proof[10] = bytes32(0x133461b685bb3ae4afeb28d936f6c0e63983ba34bf4bd5d8f9e39d8ab5920590);
        proof[11] = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);
        proof[12] = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);
        proof[13] = bytes32(0x51ec1883dd92281b382a85bee8276c6e21ae9d50349b8f2734ca6a894f69bc38);
        proof[14] = bytes32(0x822570b03bcf3f26ff2aba5ca9779f8756f855c940c904d00a11ebcab9f739c9);
        proof[15] = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);
        proof[16] = bytes32(0xb43a6b28077d49f37d58c87aec0b51f7bce13b648143f3295385f3b3d5ac3b9b);

        uint256 withdrawalAmount = 188_394_098_124_747_940;
        uint256 expetedAmountToUnlock = withdrawalAmount / (10 ** (18 - decimals));

        bytes memory data = abi.encodeWithSignature("receiveHook()");
        _outbox.executeTransaction({
            proof: proof,
            index: 12,
            l2Sender: user,
            to: address(target),
            l2Block: 300,
            l1Block: 20,
            l2Timestamp: 1234,
            value: withdrawalAmount,
            data: data
        });

        uint256 bridgeTokenBalanceAfter = _nativeToken.balanceOf(address(_bridge));
        assertEq(
            bridgeTokenBalanceBefore - bridgeTokenBalanceAfter,
            expetedAmountToUnlock,
            "Invalid bridge token balance"
        );

        uint256 targetTokenBalanceAfter = _nativeToken.balanceOf(address(target));
        assertEq(
            targetTokenBalanceAfter - targetTokenBalanceBefore,
            expetedAmountToUnlock,
            "Invalid target token balance"
        );

        /// check context was properly set during execution
        assertEq(uint256(target.l2Block()), 300, "Invalid l2Block");
        assertEq(uint256(target.timestamp()), 1234, "Invalid timestamp");
        assertEq(uint256(target.outputId()), 12, "Invalid outputId");
        assertEq(target.sender(), user, "Invalid sender");
        assertEq(uint256(target.l1Block()), 20, "Invalid l1Block");
        assertEq(
            uint256(target.withdrawalAmount()),
            expetedAmountToUnlock,
            "Invalid expetedAmountToUnlock"
        );
    }

    function test_executeTransaction_DecimalsMoreThan18() public {
        // create token/bridge/inbox
        uint8 decimals = 20;
        ERC20 _nativeToken = new ERC20_20Decimals();

        IERC20Bridge _bridge = IERC20Bridge(TestUtil.deployProxy(address(new ERC20Bridge())));
        IERC20Inbox _inbox = IERC20Inbox(TestUtil.deployProxy(address(new ERC20Inbox())));
        ERC20Outbox _outbox = ERC20Outbox(TestUtil.deployProxy(address(new ERC20Outbox())));

        // init bridge and inbox
        address _rollup = makeAddr("_rollup");
        _bridge.initialize(IOwnable(_rollup), address(_nativeToken));
        _inbox.initialize(_bridge, ISequencerInbox(makeAddr("_seqInbox")));
        _outbox.initialize(IBridge(address(_bridge)));
        vm.prank(_rollup);
        _bridge.setOutbox(address(_outbox), true);

        // fund bridge with some tokens
        ERC20_20Decimals(address(_nativeToken)).mint(address(_bridge), 1_000_000 * 10 ** decimals);

        // store root
        vm.prank(_rollup);
        _outbox.updateSendRoot(
            0x3c66096729d57a3c7528dc23097e4a7b800e7e52d4a8d71105f07e94177ae2a1,
            0x3c66096729d57a3c7528dc23097e4a7b800e7e52d4a8d71105f07e94177ae2a1
        );

        // create msg receiver on L1
        ERC20L2ToL1Target target = new ERC20L2ToL1Target();
        target.setOutbox(address(_outbox));

        //// execute transaction
        uint256 bridgeTokenBalanceBefore = _nativeToken.balanceOf(address(_bridge));
        uint256 targetTokenBalanceBefore = _nativeToken.balanceOf(address(target));

        bytes32[] memory proof = new bytes32[](17);
        proof[0] = bytes32(0x374de32809f4525d60cb461de130464fddfccb4684cfdbce7016f11f3a2118cf);
        proof[1] = bytes32(0x08ea4de37e43c6407da28848d26b37a56661caf119ab1d67d9af8ec76bca2d0d);
        proof[2] = bytes32(0x934fbafba47f664a03dde194b1d8a8211a39ae0c07d6ecc903252576e261307c);
        proof[3] = bytes32(0xf76d8c825305d7a261a874e863922214f1ad9b2fa833725080d4b2de6678d948);
        proof[4] = bytes32(0xdf1a4d32f399d99a9c2a633d63c7bfc15ee39bb8d51ee9e30328965b70248387);
        proof[5] = bytes32(0xe0a0781562562fca15375998f0c80ed72aa6cf5ed772c061150f1d3f0284f9cb);
        proof[6] = bytes32(0x190e26dd23006cce5d90fced90b381385517ca7f189af5a409343a6d50d52c14);
        proof[7] = bytes32(0xbf38be925e8044790f45f3a52cb13606b61a3a3d35823d2e304f50755107eeb9);
        proof[8] = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);
        proof[9] = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);
        proof[10] = bytes32(0x133461b685bb3ae4afeb28d936f6c0e63983ba34bf4bd5d8f9e39d8ab5920590);
        proof[11] = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);
        proof[12] = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);
        proof[13] = bytes32(0x51ec1883dd92281b382a85bee8276c6e21ae9d50349b8f2734ca6a894f69bc38);
        proof[14] = bytes32(0x822570b03bcf3f26ff2aba5ca9779f8756f855c940c904d00a11ebcab9f739c9);
        proof[15] = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);
        proof[16] = bytes32(0xb43a6b28077d49f37d58c87aec0b51f7bce13b648143f3295385f3b3d5ac3b9b);

        uint256 withdrawalAmount = 188_394_098_124_747_940;
        uint256 expetedAmountToUnlock = withdrawalAmount * (10 ** (decimals - 18));

        bytes memory data = abi.encodeWithSignature("receiveHook()");
        _outbox.executeTransaction({
            proof: proof,
            index: 12,
            l2Sender: user,
            to: address(target),
            l2Block: 300,
            l1Block: 20,
            l2Timestamp: 1234,
            value: withdrawalAmount,
            data: data
        });

        uint256 bridgeTokenBalanceAfter = _nativeToken.balanceOf(address(_bridge));
        assertEq(
            bridgeTokenBalanceBefore - bridgeTokenBalanceAfter,
            expetedAmountToUnlock,
            "Invalid bridge token balance"
        );

        uint256 targetTokenBalanceAfter = _nativeToken.balanceOf(address(target));
        assertEq(
            targetTokenBalanceAfter - targetTokenBalanceBefore,
            expetedAmountToUnlock,
            "Invalid target token balance"
        );

        /// check context was properly set during execution
        assertEq(uint256(target.l2Block()), 300, "Invalid l2Block");
        assertEq(uint256(target.timestamp()), 1234, "Invalid timestamp");
        assertEq(uint256(target.outputId()), 12, "Invalid outputId");
        assertEq(target.sender(), user, "Invalid sender");
        assertEq(uint256(target.l1Block()), 20, "Invalid l1Block");
        assertEq(
            uint256(target.withdrawalAmount()),
            expetedAmountToUnlock,
            "Invalid expetedAmountToUnlock"
        );
    }

    function test_executeTransaction_revert_AmountTooLarge() public {
        // create token/bridge/inbox
        ERC20 _nativeToken = new ERC20_36Decimals();

        IERC20Bridge _bridge = IERC20Bridge(TestUtil.deployProxy(address(new ERC20Bridge())));
        IERC20Inbox _inbox = IERC20Inbox(TestUtil.deployProxy(address(new ERC20Inbox())));
        ERC20Outbox _outbox = ERC20Outbox(TestUtil.deployProxy(address(new ERC20Outbox())));

        // init bridge and inbox
        address _rollup = makeAddr("_rollup");
        _bridge.initialize(IOwnable(_rollup), address(_nativeToken));
        _inbox.initialize(_bridge, ISequencerInbox(makeAddr("_seqInbox")));
        _outbox.initialize(IBridge(address(_bridge)));
        vm.prank(_rollup);
        _bridge.setOutbox(address(_outbox), true);

        // fund bridge with some tokens
        ERC20_36Decimals(address(_nativeToken)).mint(address(_bridge), type(uint256).max / 100);

        // store root
        vm.prank(_rollup);
        _outbox.updateSendRoot(
            0xcf78d107811be83d3ec56f935417458a3178dd76f3a96f9b92cbff0d1a8dd106,
            0xcf78d107811be83d3ec56f935417458a3178dd76f3a96f9b92cbff0d1a8dd106
        );

        // create msg receiver on L1
        ERC20L2ToL1Target target = new ERC20L2ToL1Target();
        target.setOutbox(address(_outbox));

        //// execute transaction
        bytes32[] memory proof = new bytes32[](17);
        proof[0] = bytes32(0x374de32809f4525d60cb461de130464fddfccb4684cfdbce7016f11f3a2118cf);
        proof[1] = bytes32(0x08ea4de37e43c6407da28848d26b37a56661caf119ab1d67d9af8ec76bca2d0d);
        proof[2] = bytes32(0x934fbafba47f664a03dde194b1d8a8211a39ae0c07d6ecc903252576e261307c);
        proof[3] = bytes32(0xf76d8c825305d7a261a874e863922214f1ad9b2fa833725080d4b2de6678d948);
        proof[4] = bytes32(0xdf1a4d32f399d99a9c2a633d63c7bfc15ee39bb8d51ee9e30328965b70248387);
        proof[5] = bytes32(0xe0a0781562562fca15375998f0c80ed72aa6cf5ed772c061150f1d3f0284f9cb);
        proof[6] = bytes32(0x190e26dd23006cce5d90fced90b381385517ca7f189af5a409343a6d50d52c14);
        proof[7] = bytes32(0xbf38be925e8044790f45f3a52cb13606b61a3a3d35823d2e304f50755107eeb9);
        proof[8] = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);
        proof[9] = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);
        proof[10] = bytes32(0x133461b685bb3ae4afeb28d936f6c0e63983ba34bf4bd5d8f9e39d8ab5920590);
        proof[11] = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);
        proof[12] = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);
        proof[13] = bytes32(0x51ec1883dd92281b382a85bee8276c6e21ae9d50349b8f2734ca6a894f69bc38);
        proof[14] = bytes32(0x822570b03bcf3f26ff2aba5ca9779f8756f855c940c904d00a11ebcab9f739c9);
        proof[15] = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);
        proof[16] = bytes32(0xb43a6b28077d49f37d58c87aec0b51f7bce13b648143f3295385f3b3d5ac3b9b);

        uint256 tooLargeWithdrawalAmount = type(uint256).max / 10 ** 18 + 1;

        bytes memory data = abi.encodeWithSignature("receiveHook()");

        vm.expectRevert(abi.encodeWithSelector(AmountTooLarge.selector, tooLargeWithdrawalAmount));
        _outbox.executeTransaction({
            proof: proof,
            index: 12,
            l2Sender: user,
            to: address(target),
            l2Block: 300,
            l1Block: 20,
            l2Timestamp: 1234,
            value: tooLargeWithdrawalAmount,
            data: data
        });
    }
}

/**
 * Contract for testing L2 to L1 msgs
 */
contract ERC20L2ToL1Target {
    address public outbox;

    uint128 public l2Block;
    uint128 public timestamp;
    bytes32 public outputId;
    address public sender;
    uint96 public l1Block;
    uint256 public withdrawalAmount;

    function receiveHook() external payable {
        l2Block = uint128(IOutbox(outbox).l2ToL1Block());
        timestamp = uint128(IOutbox(outbox).l2ToL1Timestamp());
        outputId = IOutbox(outbox).l2ToL1OutputId();
        sender = IOutbox(outbox).l2ToL1Sender();
        l1Block = uint96(IOutbox(outbox).l2ToL1EthBlock());
        withdrawalAmount = ERC20Outbox(outbox).l2ToL1WithdrawalAmount();
    }

    function setOutbox(address _outbox) external {
        outbox = _outbox;
    }
}
