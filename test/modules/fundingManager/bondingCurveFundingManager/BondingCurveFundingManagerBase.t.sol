// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

// Internal Dependencies
import {ModuleTest, IModule, IOrchestrator} from "test/modules/ModuleTest.sol";
import {BancorFormula} from
    "src/modules/fundingManager/bondingCurveFundingManager/formula/BancorFormula.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// Mocks
import {
    BondingCurveFundingManagerMock,
    IBondingCurveFundingManagerBase
} from
    "test/modules/fundingManager/bondingCurveFundingManager/marketMaker/utils/mocks/BondingCurveFundingManagerMock.sol";

contract BondingCurveFundingManagerBaseTest is ModuleTest {
    string private constant NAME = "Bonding Curve Token";
    string private constant SYMBOL = "BCT";
    uint8 private constant DECIMALS = 18;
    uint private constant BUY_FEE = 0;
    bool private constant BUY_IS_OPEN = true;

    BondingCurveFundingManagerMock bondingCurveFundingManager;
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
        address impl = address(new BondingCurveFundingManagerMock());

        bondingCurveFundingManager =
            BondingCurveFundingManagerMock(Clones.clone(impl));

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
        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        bondingCurveFundingManager.init(_orchestrator, _METADATA, abi.encode());
    }

    /* Test buyingIsEnabled modifier
        ├── when buy is not open
        │       └── it should revert
        └── when buy is open
                └── it should not revert (tested in buyOrder tests)

    */
    function testBuyingIsEnabled_FailsIfBuyNotOpen() public {
        vm.prank(owner_address);
        bondingCurveFundingManager.closeBuy();

        vm.prank(non_owner_address);
        vm.expectRevert(
            IBondingCurveFundingManagerBase
                .BondingCurveFundingManager__BuyingFunctionaltiesClosed
                .selector
        );
        bondingCurveFundingManager.buyOrderFor(non_owner_address, 100);
    }

    /* Test validReceiver modifier
        ├── when receiver is address 0
        │       └── it should revert
        ├── when receiver is address itself
        │       └── it should revert
        └── when address is not in the cases above
                └── it should not revert (tested in buyOrder tests)
    */
    function testValidReceiver_FailsForInvalidAddresses() public {
        vm.startPrank(non_owner_address);

        // Test for address(0)
        vm.expectRevert(
            IBondingCurveFundingManagerBase
                .BondingCurveFundingManagerBase__InvalidRecipient
                .selector
        );
        bondingCurveFundingManager.buyOrderFor(address(0), 100);

        // Test for its own address)
        vm.expectRevert(
            IBondingCurveFundingManagerBase
                .BondingCurveFundingManagerBase__InvalidRecipient
                .selector
        );
        bondingCurveFundingManager.buyOrderFor(
            address(bondingCurveFundingManager), 100
        );

        vm.stopPrank();
    }

    //  Test modifiers on buyOrderFor function

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
        bondingCurveFundingManager.buyOrderFor(receiver, amount);

        // Post-checks
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManager)),
            (balanceBefore + amount)
        );
        assertEq(_token.balanceOf(buyer), 0);
        assertEq(bondingCurveFundingManager.balanceOf(buyer), 0);
        assertEq(bondingCurveFundingManager.balanceOf(receiver), amount);
    }

    /* Test buyOrder and _buyOrder function
        ├── when the deposit amount is 0
        │       └── it should revert 
        └── when the deposit amount is not 0
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
            IBondingCurveFundingManagerBase
                .BondingCurveFundingManager__InvalidDepositAmount
                .selector
        );
        bondingCurveFundingManager.buyOrder(0);
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
        bondingCurveFundingManager.buyOrder(amount);

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
        bondingCurveFundingManager.buyOrder(amount);

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
            IBondingCurveFundingManagerBase
                .BondingCurveFundingManager__BuyingAlreadyOpen
                .selector
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
            IBondingCurveFundingManagerBase
                .BondingCurveFundingManager__BuyingAlreadyClosed
                .selector
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
            IBondingCurveFundingManagerBase
                .BondingCurveFundingManager__InvalidFeePercentage
                .selector
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

    /* Test _calculateFeeDeductedDepositAmount function
        ├── when feePct is higher than the BPS
        │      └── it should return zero 
        └── when feePct is lower than the BPS
                └── it should return the deposit amount with the fee deducted
    */
    function testCalculateFeeDeductedDepositAmount_ZeroIfFeeHigherThanBPS(
        uint _depositAmount,
        uint _fee
    ) public {
        vm.assume(_fee > bondingCurveFundingManager.call_BPS()); // fetch the BPS value through the mock
        vm.expectRevert(
            IBondingCurveFundingManagerBase
                .BondingCurveFundingManager__InvalidFeePercentage
                .selector
        );
        bondingCurveFundingManager.call_calculateFeeDeductedDepositAmount(
            _depositAmount, _fee
        );
    }

    function testCalculateFeeDeductedDepositAmount(uint _amount, uint _fee)
        public
    {
        uint _bps = bondingCurveFundingManager.call_BPS();
        vm.assume(_fee <= _bps);

        uint maxAmount = type(uint).max / _bps; // to prevent overflows
        _amount = bound(_amount, 1, maxAmount);

        uint amountMinusFee = _amount - (_amount * _fee / _bps);

        uint res = bondingCurveFundingManager
            .call_calculateFeeDeductedDepositAmount(_amount, _fee);

        assertEq(res, amountMinusFee);
    }

    /* Test _setDecimals 
        - Here we don't have limitations theoretically
    */
    function testSetDecimals(uint8 _newDecimals) public {
        // No authentication since it's an internal function exposed by the mock contract
        bondingCurveFundingManager.call_setDecimals(_newDecimals);

        assertEq(bondingCurveFundingManager.decimals(), _newDecimals);
    }

    // Test _issueTokens function
    // this is tested in the buyOrder tests

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
