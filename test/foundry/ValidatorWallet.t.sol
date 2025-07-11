// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "./util/TestUtil.sol";
import "../../src/rollup/ValidatorWallet.sol";
import "../../src/rollup/ValidatorWalletCreator.sol";
import "../../src/libraries/IGasRefunder.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract MockGasRefunder is IGasRefunder {
    event GasRefunded(address spender, uint256 gasUsed, uint256 calldataSize);

    function onGasSpent(
        address payable spender,
        uint256 gasUsed,
        uint256 calldataSize
    ) external override returns (bool success) {
        emit GasRefunded(spender, gasUsed, calldataSize);
        return true;
    }
}

contract MockTarget {
    uint256 public value;
    bool public shouldRevert;

    receive() external payable {
        if (shouldRevert) revert("MockTarget: revert");
    }

    function setValue(
        uint256 _value
    ) external payable {
        if (shouldRevert) revert("MockTarget: revert");
        value = _value;
    }

    function setShouldRevert(
        bool _shouldRevert
    ) external {
        shouldRevert = _shouldRevert;
    }
}

contract ValidatorWalletTest is Test {
    ValidatorWallet public walletImpl;
    ValidatorWallet public wallet;
    ProxyAdmin public proxyAdmin;

    address public owner = makeAddr("owner");
    address public executor = makeAddr("executor");
    address public executor2 = makeAddr("executor2");
    address public nonExecutor = makeAddr("nonExecutor");
    address public allowedDest1 = makeAddr("allowedDest1");
    address public allowedDest2 = makeAddr("allowedDest2");
    address public notAllowedDest = makeAddr("notAllowedDest");

    MockGasRefunder public gasRefunder;
    MockTarget public mockTarget1;
    MockTarget public mockTarget2;
    MockTarget public mockTargetNotAllowed;

    event ExecutorUpdated(address indexed executor, bool isExecutor);
    event AllowedExecutorDestinationsUpdated(address indexed destination, bool isSet);

    function setUp() public {
        // Deploy implementation
        walletImpl = new ValidatorWallet();

        // Deploy proxy admin
        proxyAdmin = new ProxyAdmin();

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            ValidatorWallet.initialize.selector, executor, owner, new address[](0)
        );
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(walletImpl), address(proxyAdmin), initData);
        wallet = ValidatorWallet(payable(address(proxy)));

        // Deploy mock contracts
        gasRefunder = new MockGasRefunder();
        mockTarget1 = new MockTarget();
        mockTarget2 = new MockTarget();
        mockTargetNotAllowed = new MockTarget();

        // Setup allowed destinations
        address[] memory destinations = new address[](2);
        destinations[0] = address(mockTarget1);
        destinations[1] = address(mockTarget2);
        bool[] memory isSet = new bool[](2);
        isSet[0] = true;
        isSet[1] = true;

        vm.prank(owner);
        wallet.setAllowedExecutorDestinations(destinations, isSet);

        // Fund accounts
        vm.deal(owner, 100 ether);
        vm.deal(executor, 100 ether);
        vm.deal(executor2, 100 ether);
        vm.deal(nonExecutor, 100 ether);
        vm.deal(address(wallet), 50 ether);
    }

    function testInitialize() public {
        // Deploy new wallet with initial allowed destinations
        address[] memory initialDests = new address[](2);
        initialDests[0] = allowedDest1;
        initialDests[1] = allowedDest2;

        ValidatorWallet newWalletImpl = new ValidatorWallet();
        bytes memory initData = abi.encodeWithSelector(
            ValidatorWallet.initialize.selector, executor2, owner, initialDests
        );

        vm.expectEmit(true, true, true, true);
        emit ExecutorUpdated(executor2, true);
        vm.expectEmit(true, true, true, true);
        emit AllowedExecutorDestinationsUpdated(allowedDest1, true);
        vm.expectEmit(true, true, true, true);
        emit AllowedExecutorDestinationsUpdated(allowedDest2, true);

        TransparentUpgradeableProxy newProxy =
            new TransparentUpgradeableProxy(address(newWalletImpl), address(proxyAdmin), initData);
        ValidatorWallet newWallet = ValidatorWallet(payable(address(newProxy)));

        // Verify state
        assertEq(newWallet.owner(), owner);
        assertTrue(newWallet.executors(executor2));
        assertTrue(newWallet.allowedExecutorDestinations(allowedDest1));
        assertTrue(newWallet.allowedExecutorDestinations(allowedDest2));
    }

    function testInitializeOnlyDelegated() public {
        // Try to initialize implementation directly (should fail)
        address[] memory empty = new address[](0);
        vm.expectRevert("Function must be called through delegatecall");
        walletImpl.initialize(executor, owner, empty);
    }

    function testSetExecutor() public {
        address[] memory executors = new address[](2);
        executors[0] = executor2;
        executors[1] = nonExecutor;
        bool[] memory isExecutor = new bool[](2);
        isExecutor[0] = true;
        isExecutor[1] = true;

        vm.expectEmit(true, true, true, true);
        emit ExecutorUpdated(executor2, true);
        vm.expectEmit(true, true, true, true);
        emit ExecutorUpdated(nonExecutor, true);

        vm.prank(owner);
        wallet.setExecutor(executors, isExecutor);

        assertTrue(wallet.executors(executor2));
        assertTrue(wallet.executors(nonExecutor));

        // Remove executor
        address[] memory removeExecutors = new address[](1);
        removeExecutors[0] = nonExecutor;
        bool[] memory removeIsExecutor = new bool[](1);
        removeIsExecutor[0] = false;

        vm.expectEmit(true, true, true, true);
        emit ExecutorUpdated(nonExecutor, false);

        vm.prank(owner);
        wallet.setExecutor(removeExecutors, removeIsExecutor);

        assertFalse(wallet.executors(nonExecutor));
    }

    function testSetExecutorOnlyOwner() public {
        address[] memory executors = new address[](1);
        executors[0] = executor2;
        bool[] memory isExecutor = new bool[](1);
        isExecutor[0] = true;

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(executor);
        wallet.setExecutor(executors, isExecutor);
    }

    function testSetExecutorBadArrayLength() public {
        address[] memory executors = new address[](2);
        executors[0] = executor2;
        executors[1] = nonExecutor;
        bool[] memory isExecutor = new bool[](1);
        isExecutor[0] = true;

        vm.expectRevert(abi.encodeWithSelector(BadArrayLength.selector, 2, 1));
        vm.prank(owner);
        wallet.setExecutor(executors, isExecutor);
    }

    function testSetAllowedExecutorDestinations() public {
        address[] memory destinations = new address[](2);
        destinations[0] = allowedDest1;
        destinations[1] = allowedDest2;
        bool[] memory isSet = new bool[](2);
        isSet[0] = true;
        isSet[1] = false;

        vm.expectEmit(true, true, true, true);
        emit AllowedExecutorDestinationsUpdated(allowedDest1, true);
        vm.expectEmit(true, true, true, true);
        emit AllowedExecutorDestinationsUpdated(allowedDest2, false);

        vm.prank(owner);
        wallet.setAllowedExecutorDestinations(destinations, isSet);

        assertTrue(wallet.allowedExecutorDestinations(allowedDest1));
        assertFalse(wallet.allowedExecutorDestinations(allowedDest2));
    }

    function testSetAllowedExecutorDestinationsOnlyOwner() public {
        address[] memory destinations = new address[](1);
        destinations[0] = allowedDest1;
        bool[] memory isSet = new bool[](1);
        isSet[0] = true;

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(executor);
        wallet.setAllowedExecutorDestinations(destinations, isSet);
    }

    function testSetAllowedExecutorDestinationsBadArrayLength() public {
        address[] memory destinations = new address[](2);
        destinations[0] = allowedDest1;
        destinations[1] = allowedDest2;
        bool[] memory isSet = new bool[](1);
        isSet[0] = true;

        vm.expectRevert(abi.encodeWithSelector(BadArrayLength.selector, 2, 1));
        vm.prank(owner);
        wallet.setAllowedExecutorDestinations(destinations, isSet);
    }

    function testExecuteTransaction() public {
        uint256 amount = 1 ether;
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        // Executor can execute to allowed destination
        vm.prank(executor);
        wallet.executeTransaction{value: amount}(data, address(mockTarget1), amount);

        assertEq(mockTarget1.value(), 42);
        assertEq(address(mockTarget1).balance, amount);
    }

    function testExecuteTransactionOwnerCanCallAnyDestination() public {
        uint256 amount = 1 ether;
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 99);

        // Owner can execute to non-allowed destination
        vm.prank(owner);
        wallet.executeTransaction{value: amount}(data, address(mockTargetNotAllowed), amount);

        assertEq(mockTargetNotAllowed.value(), 99);
        assertEq(address(mockTargetNotAllowed).balance, amount);
    }

    function testExecuteTransactionNotExecutorOrOwner() public {
        uint256 amount = 1 ether;
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.expectRevert(abi.encodeWithSelector(NotExecutorOrOwner.selector, nonExecutor));
        vm.prank(nonExecutor);
        wallet.executeTransaction{value: amount}(data, address(mockTarget1), amount);
    }

    function testExecuteTransactionExecutorNotAllowedDestination() public {
        uint256 amount = 1 ether;
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.expectRevert(
            abi.encodeWithSelector(
                OnlyOwnerDestination.selector, owner, executor, address(mockTargetNotAllowed)
            )
        );
        vm.prank(executor);
        wallet.executeTransaction{value: amount}(data, address(mockTargetNotAllowed), amount);
    }

    function testExecuteTransactionReverts() public {
        mockTarget1.setShouldRevert(true);
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.expectRevert("MockTarget: revert");
        vm.prank(executor);
        wallet.executeTransaction(data, address(mockTarget1), 0);
    }

    function testExecuteTransactionRequiresContractForData() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.expectRevert("NO_CODE_AT_ADDR");
        vm.prank(owner);
        wallet.executeTransaction(data, allowedDest1, 0);
    }

    function testExecuteTransactionETHTransferToEOA() public {
        uint256 amount = 1 ether;
        uint256 balanceBefore = allowedDest1.balance;

        // Empty data allows EOA transfer
        vm.prank(owner);
        wallet.executeTransaction{value: amount}("", allowedDest1, amount);

        assertEq(allowedDest1.balance, balanceBefore + amount);
    }

    function testExecuteTransactions() public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(MockTarget.setValue.selector, 42);
        data[1] = abi.encodeWithSelector(MockTarget.setValue.selector, 99);

        address[] memory destinations = new address[](2);
        destinations[0] = address(mockTarget1);
        destinations[1] = address(mockTarget2);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;

        vm.prank(executor);
        wallet.executeTransactions{value: 3 ether}(data, destinations, amounts);

        assertEq(mockTarget1.value(), 42);
        assertEq(mockTarget2.value(), 99);
        assertEq(address(mockTarget1).balance, 1 ether);
        assertEq(address(mockTarget2).balance, 2 ether);
    }

    function testExecuteTransactionsBadArrayLength() public {
        bytes[] memory data = new bytes[](2);
        address[] memory destinations = new address[](1);
        uint256[] memory amounts = new uint256[](2);

        vm.expectRevert(abi.encodeWithSelector(BadArrayLength.selector, 2, 1));
        vm.prank(executor);
        wallet.executeTransactions(data, destinations, amounts);

        destinations = new address[](2);
        amounts = new uint256[](1);

        vm.expectRevert(abi.encodeWithSelector(BadArrayLength.selector, 2, 1));
        vm.prank(executor);
        wallet.executeTransactions(data, destinations, amounts);
    }

    function testExecuteTransactionWithGasRefunder() public {
        uint256 amount = 1 ether;
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.expectEmit(false, false, false, false, address(gasRefunder));
        emit MockGasRefunder.GasRefunded(executor, 0, 0);

        vm.prank(executor);
        wallet.executeTransactionWithGasRefunder{value: amount}(
            gasRefunder, data, address(mockTarget1), amount
        );

        assertEq(mockTarget1.value(), 42);
    }

    function testExecuteTransactionsWithGasRefunder() public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(MockTarget.setValue.selector, 42);
        data[1] = abi.encodeWithSelector(MockTarget.setValue.selector, 99);

        address[] memory destinations = new address[](2);
        destinations[0] = address(mockTarget1);
        destinations[1] = address(mockTarget2);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;

        vm.expectEmit(false, false, false, false, address(gasRefunder));
        emit MockGasRefunder.GasRefunded(executor, 0, 0);

        vm.prank(executor);
        wallet.executeTransactionsWithGasRefunder{value: 3 ether}(
            gasRefunder, data, destinations, amounts
        );

        assertEq(mockTarget1.value(), 42);
        assertEq(mockTarget2.value(), 99);
    }

    function testValidateExecuteTransaction() public {
        // Executor can validate allowed destination
        vm.prank(executor);
        wallet.validateExecuteTransaction(address(mockTarget1));

        // Owner can validate any destination
        vm.prank(owner);
        wallet.validateExecuteTransaction(address(mockTargetNotAllowed));

        // Executor cannot validate non-allowed destination
        vm.expectRevert(
            abi.encodeWithSelector(
                OnlyOwnerDestination.selector, owner, executor, address(mockTargetNotAllowed)
            )
        );
        vm.prank(executor);
        wallet.validateExecuteTransaction(address(mockTargetNotAllowed));
    }

    function testWithdrawEth() public {
        uint256 amount = 10 ether;
        uint256 ownerBalanceBefore = owner.balance;

        vm.prank(owner);
        wallet.withdrawEth(amount, owner);

        assertEq(owner.balance, ownerBalanceBefore + amount);
    }

    function testWithdrawEthOnlyOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(executor);
        wallet.withdrawEth(1 ether, executor);
    }

    function testWithdrawEthFail() public {
        // Create a contract that rejects ETH
        MockTarget rejectingTarget = new MockTarget();
        rejectingTarget.setShouldRevert(true);

        vm.expectRevert(abi.encodeWithSelector(WithdrawEthFail.selector, address(rejectingTarget)));
        vm.prank(owner);
        wallet.withdrawEth(1 ether, address(rejectingTarget));
    }

    function testReceive() public {
        uint256 walletBalanceBefore = address(wallet).balance;
        uint256 sendAmount = 5 ether;

        // Send ETH to wallet
        (bool success,) = address(wallet).call{value: sendAmount}("");
        assertTrue(success);

        assertEq(address(wallet).balance, walletBalanceBefore + sendAmount);
    }

    function testMultipleExecutorsAndDestinations() public {
        // Add another executor
        address[] memory executors = new address[](1);
        executors[0] = executor2;
        bool[] memory isExecutor = new bool[](1);
        isExecutor[0] = true;

        vm.prank(owner);
        wallet.setExecutor(executors, isExecutor);

        // Both executors can execute to allowed destinations
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 111);

        vm.prank(executor);
        wallet.executeTransaction(data, address(mockTarget1), 0);
        assertEq(mockTarget1.value(), 111);

        vm.prank(executor2);
        wallet.executeTransaction(data, address(mockTarget2), 0);
        assertEq(mockTarget2.value(), 111);
    }

    function testExecuteTransactionRevertData() public {
        // Set up target to revert with specific data
        mockTarget1.setShouldRevert(true);
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        // Capture exact revert data
        vm.expectRevert("MockTarget: revert");
        vm.prank(executor);
        wallet.executeTransaction(data, address(mockTarget1), 0);
    }

    function testExecuteTransactionsPartialRevert() public {
        // Make second target revert
        mockTarget2.setShouldRevert(true);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(MockTarget.setValue.selector, 42);
        data[1] = abi.encodeWithSelector(MockTarget.setValue.selector, 99);

        address[] memory destinations = new address[](2);
        destinations[0] = address(mockTarget1);
        destinations[1] = address(mockTarget2);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = 0;

        vm.expectRevert("MockTarget: revert");
        vm.prank(executor);
        wallet.executeTransactions(data, destinations, amounts);

        // First transaction should not have executed
        assertEq(mockTarget1.value(), 0);
    }

    function testExecuteWithZeroGasRefunder() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        // Should work with zero address gas refunder
        vm.prank(executor);
        wallet.executeTransactionWithGasRefunder(
            IGasRefunder(address(0)), data, address(mockTarget1), 0
        );

        assertEq(mockTarget1.value(), 42);
    }
}

contract ValidatorWalletCreatorTest is Test {
    ValidatorWalletCreator public creator;

    address public user = makeAddr("user");
    address public dest1 = makeAddr("dest1");
    address public dest2 = makeAddr("dest2");

    event WalletCreated(
        address indexed walletAddress,
        address indexed executorAddress,
        address indexed ownerAddress,
        address adminProxy
    );

    function setUp() public {
        creator = new ValidatorWalletCreator();
    }

    function testCreateWallet() public {
        address[] memory allowedDests = new address[](2);
        allowedDests[0] = dest1;
        allowedDests[1] = dest2;

        vm.startPrank(user);

        // Expect the WalletCreated event
        vm.expectEmit(false, true, true, false);
        emit WalletCreated(address(0), user, user, address(0));

        address walletAddr = creator.createWallet(allowedDests);
        vm.stopPrank();

        // Verify the wallet was created and initialized correctly
        ValidatorWallet wallet = ValidatorWallet(payable(walletAddr));

        // Check that user is both executor and owner
        assertTrue(wallet.executors(user));
        assertEq(wallet.owner(), user);

        // Check allowed destinations
        assertTrue(wallet.allowedExecutorDestinations(dest1));
        assertTrue(wallet.allowedExecutorDestinations(dest2));
        assertFalse(wallet.allowedExecutorDestinations(makeAddr("randomDest")));
    }

    function testCreateWalletEmptyDestinations() public {
        address[] memory allowedDests = new address[](0);

        vm.startPrank(user);
        address walletAddr = creator.createWallet(allowedDests);
        vm.stopPrank();

        ValidatorWallet wallet = ValidatorWallet(payable(walletAddr));

        // Check that user is both executor and owner
        assertTrue(wallet.executors(user));
        assertEq(wallet.owner(), user);

        // No destinations should be allowed
        assertFalse(wallet.allowedExecutorDestinations(dest1));
    }

    function testCreateMultipleWallets() public {
        address[] memory allowedDests = new address[](1);
        allowedDests[0] = dest1;

        vm.startPrank(user);
        address wallet1 = creator.createWallet(allowedDests);
        address wallet2 = creator.createWallet(allowedDests);
        vm.stopPrank();

        // Wallets should have different addresses
        assertTrue(wallet1 != wallet2);

        // Both should be properly initialized
        ValidatorWallet w1 = ValidatorWallet(payable(wallet1));
        ValidatorWallet w2 = ValidatorWallet(payable(wallet2));

        assertEq(w1.owner(), user);
        assertEq(w2.owner(), user);
    }

    function testTemplateAddress() public {
        // Verify template is properly set
        address template = creator.template();
        assertTrue(template != address(0));

        // Template should be a ValidatorWallet contract
        // We can't call initialize on it directly as it's meant to be used via proxy
        assertEq(ValidatorWallet(payable(template)).owner(), address(0));
    }
}
