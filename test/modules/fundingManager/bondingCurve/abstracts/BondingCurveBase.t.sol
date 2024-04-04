// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";

// Internal Dependencies
import {ModuleTest, IModule, IOrchestrator} from "test/modules/ModuleTest.sol";
import {BancorFormula} from
    "src/modules/fundingManager/bondingCurve/formulas/BancorFormula.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// Mocks
import {
    BondingCurveBaseMock,
    IBondingCurveBase
} from
    "test/modules/fundingManager/bondingCurve/utils/mocks/BondingCurveBaseMock.sol";
import {IFundingManager} from "src/modules/fundingManager/IFundingManager.sol";

contract BondingCurveBaseTest is ModuleTest {
    string private constant NAME = "Bonding Curve Token";
    string private constant SYMBOL = "BCT";
    uint8 private constant DECIMALS = 18;
    uint private constant BUY_FEE = 0;
    bool private constant BUY_IS_OPEN = true;

    BondingCurveBaseMock bondingCurveFundingManager;
    address formula;

    address owner_address = makeAddr("alice");
    address non_owner_address = makeAddr("bob");

    event BuyingEnabled();
    event BuyingDisabled();
    event BuyFeeUpdated(uint indexed newBuyFee, uint indexed oldBuyFee);
    event TokensBought(
        address indexed receiver,
        uint indexed depositAmount,
        uint indexed receivedAmount,
        address buyer
    );

    function setUp() public {
        // Deploy contracts
        address impl = address(new BondingCurveBaseMock());

        bondingCurveFundingManager = BondingCurveBaseMock(Clones.clone(impl));

        formula = address(new BancorFormula());

        _setUpOrchestrator(bondingCurveFundingManager);

        _authorizer.grantRole(_authorizer.getOwnerRole(), owner_address);

        // Init Module
        bondingCurveFundingManager.init(
            _orchestrator,
            _METADATA,
            abi.encode(
                bytes32(abi.encodePacked(NAME)),
                bytes32(abi.encodePacked(SYMBOL)),
                DECIMALS,
                formula,
                BUY_FEE,
                BUY_IS_OPEN
            )
        );
    }

    function testSupportsInterface() public {
        assertTrue(
            bondingCurveFundingManager.supportsInterface(
                type(IBondingCurveBase).interfaceId
            )
        );
        assertTrue(
            bondingCurveFundingManager.supportsInterface(
                type(IFundingManager).interfaceId
            )
        );
    }

    //--------------------------------------------------------------------------
    // Test: Initialization

    //This function also tests all the getters
    //--------------------------------------------------------------------------
    // Tests: Initialization

    function testInit() public override {
        assertEq(
            bondingCurveFundingManager.name(),
            string(abi.encodePacked(bytes32(abi.encodePacked(NAME)))),
            "Name has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManager.symbol(),
            string(abi.encodePacked(bytes32(abi.encodePacked(SYMBOL)))),
            "Symbol has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManager.decimals(),
            DECIMALS,
            "Decimals has not been set correctly"
        );
        assertEq(
            address(bondingCurveFundingManager.formula()),
            formula,
            "Formula has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManager.buyFee(),
            BUY_FEE,
            "Buy fee has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManager.buyIsOpen(),
            BUY_IS_OPEN,
            "Buy-is-open has not been set correctly"
        );
    }

    function testReinitFails() public override {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        bondingCurveFundingManager.init(_orchestrator, _METADATA, abi.encode());
    }

    /* Test buyingIsEnabled modifier
        ├── when buy is not open
        │       └── it should revert
        └── when buy is open
                └── it should not revert (tested in buy tests)

    */
    function testBuyingIsEnabled_FailsIfBuyNotOpen() public {
        vm.prank(owner_address);
        bondingCurveFundingManager.closeBuy();

        vm.prank(non_owner_address);
        vm.expectRevert(
            IBondingCurveBase
                .BondingCurveBase__BuyingFunctionaltiesClosed
                .selector
        );
        bondingCurveFundingManager.buyFor(non_owner_address, 100, 100);
    }

    /* Test validReceiver modifier
        ├── when receiver is address 0
        │       └── it should revert
        ├── when receiver is address itself
        │       └── it should revert
        └── when address is not in the cases above
                └── it should not revert (tested in buy tests)
    */
    function testValidReceiver_FailsForInvalidAddresses() public {
        vm.startPrank(non_owner_address);

        // Test for address(0)
        vm.expectRevert(
            IBondingCurveBase.BondingCurveBase__InvalidRecipient.selector
        );
        bondingCurveFundingManager.buyFor(address(0), 100, 100);

        // Test for its own address)
        vm.expectRevert(
            IBondingCurveBase.BondingCurveBase__InvalidRecipient.selector
        );
        bondingCurveFundingManager.buyFor(
            address(bondingCurveFundingManager), 100, 100
        );

        vm.stopPrank();
    }

    //  Test modifiers on buyFor function

    function testPassingModifiersOnBuyOrderFor(uint amount) public {
        // Setup
        vm.assume(amount > 0);

        address buyer = makeAddr("buyer");
        address receiver = makeAddr("receiver");

        _prepareBuyConditions(buyer, amount);

        // Pre-checks
        uint balanceBefore =
            _token.balanceOf(address(bondingCurveFundingManager));
        assertEq(_token.balanceOf(buyer), amount);
        assertEq(bondingCurveFundingManager.balanceOf(buyer), 0);
        assertEq(bondingCurveFundingManager.balanceOf(receiver), 0);

        // Execution
        vm.prank(buyer);
        bondingCurveFundingManager.buyFor(receiver, amount, amount);

        // Post-checks
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManager)),
            (balanceBefore + amount)
        );
        assertEq(_token.balanceOf(buyer), 0);
        assertEq(bondingCurveFundingManager.balanceOf(buyer), 0);
        assertEq(bondingCurveFundingManager.balanceOf(receiver), amount);
    }

    /* Test buy and _buyOrder function
        ├── when the deposit amount is 0
        │       └── it should revert 
        └── when the deposit amount is not 0
                ├── when the return amount is lower than minimum expected amount out
                │       └── it should revert 
                ├── when the fee is higher than 0
                │       └── it should substract the fee from the deposit amount
                │               ├── it should pull the buy amount from the caller  
                │               ├── it should take the fee out from the pulled amount 
                │               ├── it should determine the mint amount of tokens to mint from the rest
                │               ├── it should mint the tokens to the receiver 
                │               └── it should emit an event?  
                └── when the fee is 0
                                ├── it should pull the buy amount from the caller  
                                ├── it should determine the mint amount of tokens to mint 
                                ├── it should mint the tokens to the receiver     
                                └── it should emit an event?    
        
    */
    function testBuyOrder_FailsIfDepositAmountIsZero() public {
        vm.startPrank(non_owner_address);

        vm.expectRevert(
            IBondingCurveBase.BondingCurveBase__InvalidDepositAmount.selector
        );
        bondingCurveFundingManager.buy(0, 0);
    }

    function testBuyOrder_FailsIfReturnAmountIsLowerThanMinAmount(uint amount)
        public
    {
        // Setup
        vm.assume(amount > 0 && amount < UINT256_MAX - 1); // Assume no max Uint because 1 is added for minAmountOut

        address buyer = makeAddr("buyer");
        _prepareBuyConditions(buyer, amount);
        // Mock formula contract returns amount in as amount out. Add 1 to trigger revert
        uint minAmountOut = amount + 1;

        vm.startPrank(buyer);
        vm.expectRevert(
            IBondingCurveBase
                .BondingCurveBase__InsufficientOutputAmount
                .selector
        );
        bondingCurveFundingManager.buy(amount, minAmountOut);
    }

    function testBuyOrderWithZeroFee(uint amount) public {
        // Setup
        vm.assume(amount > 0);

        address buyer = makeAddr("buyer");
        _prepareBuyConditions(buyer, amount);

        // Pre-checks
        uint balanceBefore =
            _token.balanceOf(address(bondingCurveFundingManager));
        assertEq(_token.balanceOf(buyer), amount);
        assertEq(bondingCurveFundingManager.balanceOf(buyer), 0);

        // Emit event
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit TokensBought(buyer, amount, amount, buyer);

        // Execution
        vm.prank(buyer);
        bondingCurveFundingManager.buy(amount, amount);

        // Post-checks
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManager)),
            (balanceBefore + amount)
        );
        assertEq(_token.balanceOf(buyer), 0);
        assertEq(bondingCurveFundingManager.balanceOf(buyer), amount);
    }

    function testBuyOrderWithFee(uint amount, uint fee) public {
        // Setup
        uint _bps = bondingCurveFundingManager.call_BPS();
        vm.assume(fee < _bps);

        uint maxAmount = type(uint).max / _bps; // to prevent overflows
        amount = bound(amount, 1, maxAmount);

        vm.prank(owner_address);
        bondingCurveFundingManager.setBuyFee(fee);

        address buyer = makeAddr("buyer");
        _prepareBuyConditions(buyer, amount);

        // Pre-checks
        uint balanceBefore =
            _token.balanceOf(address(bondingCurveFundingManager));
        assertEq(_token.balanceOf(buyer), amount);
        assertEq(bondingCurveFundingManager.balanceOf(buyer), 0);

        // Calculate receiving amount
        uint amountMinusFee =
            amount - (amount * fee / bondingCurveFundingManager.call_BPS());

        // Emit event
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit TokensBought(buyer, amountMinusFee, amountMinusFee, buyer); // since the fee gets taken before interacting with the bonding curve, we expect the event to already have the fee substracted

        // Execution
        vm.prank(buyer);
        bondingCurveFundingManager.buy(amount, amountMinusFee);

        // Post-checks
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManager)),
            (balanceBefore + amount)
        );
        assertEq(_token.balanceOf(buyer), 0);
        assertEq(bondingCurveFundingManager.balanceOf(buyer), amountMinusFee);
    }

    /* Test openBuy and _openBuy function
        ├── when caller is not the Orchestrator owner
        │      └── it should revert (tested in base Module modifier tests)
        └── when caller is the Orchestrator owner
               └── when buy functionality is already open
                │      └── it should revert
                └── when buy functionality is not open
                        └── it should open the buy functionality
                        └── it should emit an event
    */
    function testOpenBuy_FailsIfAlreadyOpen()
        public
        callerIsOrchestratorOwner
    {
        vm.expectRevert(
            IBondingCurveBase.BondingCurveBase__BuyingAlreadyOpen.selector
        );
        bondingCurveFundingManager.openBuy();
    }

    function testOpenBuy() public callerIsOrchestratorOwner {
        assertEq(bondingCurveFundingManager.buyIsOpen(), true);

        bondingCurveFundingManager.closeBuy();

        assertEq(bondingCurveFundingManager.buyIsOpen(), false);

        vm.expectEmit(address(bondingCurveFundingManager));
        emit BuyingEnabled();

        bondingCurveFundingManager.openBuy();

        assertEq(bondingCurveFundingManager.buyIsOpen(), true);
    }

    /* Test closeBuy and _closeBuy function
        ├── when caller is not the Orchestrator owner
        │      └── it should revert (tested in base Module tests)
        └── when caller is the Orchestrator owner
               └── when buy functionality is already closed
                │      └── it should revert 
                └── when buy functionality is not closed
                        ├── it should close the buy functionality
                        └── it should emit an event
    */
    function testCloseBuy_FailsIfAlreadyClosed()
        public
        callerIsOrchestratorOwner
    {
        bondingCurveFundingManager.closeBuy();

        vm.expectRevert(
            IBondingCurveBase.BondingCurveBase__BuyingAlreadyClosed.selector
        );
        bondingCurveFundingManager.closeBuy();
    }

    function testCloseBuy() public callerIsOrchestratorOwner {
        assertEq(bondingCurveFundingManager.buyIsOpen(), true);

        vm.expectEmit(address(bondingCurveFundingManager));
        emit BuyingDisabled();

        bondingCurveFundingManager.closeBuy();

        assertEq(bondingCurveFundingManager.buyIsOpen(), false);
    }

    /* Test setBuyFee and _setBuyFee function
        ├── when caller is not the Orchestrator owner
        │      └── it should revert (tested in base Module tests)
        └── when caller is the Orchestrator owner
               └── when fee is over 100% 
                │      └── it should revert
                ├── when fee is  100% 
                │     └── it should revert (empty buy-ins into the curve are not allowed)
                └── when fee is below 100%
                        ├── it should set the new fee
                        └── it should emit an event
    */
    function testSetBuyFee_FailsIfFee100PercentOrMore(uint _fee)
        public
        callerIsOrchestratorOwner
    {
        vm.assume(_fee >= bondingCurveFundingManager.call_BPS());
        vm.expectRevert(
            IBondingCurveBase.BondingCurveBase__InvalidFeePercentage.selector
        );
        bondingCurveFundingManager.setBuyFee(_fee);
    }

    function testSetBuyFee(uint newFee) public callerIsOrchestratorOwner {
        vm.assume(newFee < bondingCurveFundingManager.call_BPS());

        vm.expectEmit(
            true, true, false, false, address(bondingCurveFundingManager)
        );
        emit BuyFeeUpdated(newFee, BUY_FEE);

        bondingCurveFundingManager.setBuyFee(newFee);

        assertEq(bondingCurveFundingManager.buyFee(), newFee);
    }

    /* Test getCollateralFeeCollected function
        └── when the function gets called
            └── it should return the right value
    */

    function testGetCollateralFeeCollected_works(uint amount, uint fee)
        public
    {
        // Setup
        uint _bps = bondingCurveFundingManager.call_BPS();
        vm.assume(fee < _bps);

        uint maxAmount = type(uint).max / _bps; // to prevent overflows
        amount = bound(amount, 1, maxAmount);

        vm.prank(owner_address);
        bondingCurveFundingManager.setBuyFee(fee);

        address buyer = makeAddr("buyer");
        _prepareBuyConditions(buyer, amount);

        // Calculate receiving amount
        uint feeCollected = amount * fee / bondingCurveFundingManager.call_BPS();

        // Execution
        vm.prank(buyer);
        bondingCurveFundingManager.buy(amount, 0);

        vm.prank(owner_address);
        uint expectedReturnValue =
            bondingCurveFundingManager.totalCollateralTradeFeeCollected();

        assertEq(expectedReturnValue, feeCollected);
    }

    /* Test _calculateNetAmountAndFee function
        └── when feePct is lower than the BPS
                └── it should return the deposit amount with the fee deducted
    */
    function testCalculateFeeDeductedDepositAmount(uint _amount, uint _fee)
        public
    {
        uint _bps = bondingCurveFundingManager.call_BPS();
        vm.assume(_fee <= _bps);

        uint maxAmount = type(uint).max / _bps; // to prevent overflows
        _amount = bound(_amount, 1, maxAmount);

        uint feeAmount = _amount * _fee / _bps;
        uint amountMinusFee = _amount - feeAmount;

        (uint _amountMinusFee, uint _feeAmount) = bondingCurveFundingManager
            .call_calculateNetAmountAndFee(_amount, _fee);

        assertEq(_amountMinusFee, amountMinusFee);
        assertEq(_feeAmount, feeAmount);
    }

    /* Test _setDecimals function
       
        └── when setting decimals
            └── it should succeed
    */

    function testSetDecimals(uint8 _newDecimals) public {
        bondingCurveFundingManager.call_setDecimals(_newDecimals);

        assertEq(bondingCurveFundingManager.decimals(), _newDecimals);
    }

    /* Test calculatePurchaseReturn and _calculatePurchaseReturn function
        ├── When deposit amount is 0
        │       └── it should revert 
        └── When deposit amount is not 0
                ├── when the fee is 0
                │       └── it should succeed 
                └── when the fee is not 0
                        └── it should succeed 
    */

    function testCalculatePurchaseReturn_FailsIfDepositAmountZero() public {
        uint depositAmount = 0;

        vm.expectRevert(
            IBondingCurveBase.BondingCurveBase__InvalidDepositAmount.selector
        );
        bondingCurveFundingManager.calculatePurchaseReturn(depositAmount);
    }

    function testCalculatePurchaseReturnWithZeroFee(uint _depositAmount)
        public
    {
        // Above an amount of 1e38 the BancorFormula starts to revert.
        _depositAmount = bound(_depositAmount, 1, 1e38);

        // As the implementation is a mock, we return the deposit amount in a 1:1 ratio
        uint functionReturn =
            bondingCurveFundingManager.calculatePurchaseReturn(_depositAmount);
        assertEq(functionReturn, _depositAmount);
    }

    function testCalculatePurchaseReturnWithFee(uint _depositAmount, uint _fee)
        public
    {
        // Setup
        uint _bps = bondingCurveFundingManager.call_BPS();

        _fee = bound(_fee, 1, (_bps - 1)); // 100% buy fees are not allowed.
            // Above an amount of 1e38 the BancorFormula starts to revert.
        _depositAmount = bound(_depositAmount, 1, 1e38);

        vm.prank(owner_address);
        bondingCurveFundingManager.setBuyFee(_fee);

        // We calculate how much the real deposit amount will be after fees
        uint feeAmount =
            (_depositAmount * _fee) / bondingCurveFundingManager.call_BPS();
        uint buyAmountMinusFee = _depositAmount - feeAmount;

        // As the implementation is a mock, we return the deposit amount in a 1:1 ratio
        uint functionReturn =
            bondingCurveFundingManager.calculatePurchaseReturn(_depositAmount);
        assertEq(functionReturn, buyAmountMinusFee);
    }

    // Test _issueTokens function
    // this is tested in the buy tests

    //--------------------------------------------------------------------------
    // Helper functions

    // Modifier to ensure the caller has the owner role
    modifier callerIsOrchestratorOwner() {
        _authorizer.grantRole(_authorizer.getOwnerRole(), owner_address);
        vm.startPrank(owner_address);
        _;
    }

    // Helper function that mints enough collateral tokens to a buyer and approves the bonding curve to spend them
    function _prepareBuyConditions(address buyer, uint amount) internal {
        _token.mint(buyer, amount);
        vm.prank(buyer);
        _token.approve(address(bondingCurveFundingManager), amount);
    }
}
