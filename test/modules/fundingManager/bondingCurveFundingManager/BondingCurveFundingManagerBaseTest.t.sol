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

    BondingCurveFundingManagerMock bondingCurveFundingManger;
    address formula;

    address owner_address = makeAddr("alice");
    address non_owner_address = makeAddr("bob");

    function setUp() public {
        // Deploy contracts
        address impl = address(new BondingCurveFundingManagerMock());

        bondingCurveFundingManger =
            BondingCurveFundingManagerMock(Clones.clone(impl));

        formula = address(new BancorFormula());

        _setUpOrchestrator(bondingCurveFundingManger);

        _authorizer.grantRole(_authorizer.getOwnerRole(), owner_address);

        // Init Module
        bondingCurveFundingManger.init(
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
            bondingCurveFundingManger.name(),
            string(abi.encodePacked(bytes32(abi.encodePacked(NAME)))),
            "Name has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManger.symbol(),
            string(abi.encodePacked(bytes32(abi.encodePacked(SYMBOL)))),
            "Symbol has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManger.decimals(),
            DECIMALS,
            "Decimals has not been set correctly"
        );
        assertEq(
            address(bondingCurveFundingManger.formula()),
            formula,
            "Formula has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManger.buyFee(),
            BUY_FEE,
            "Buy fee has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManger.buyIsOpen(),
            BUY_IS_OPEN,
            "Buy-is-open has not been set correctly"
        );
    }

    function testReinitFails() public override {
        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        bondingCurveFundingManger.init(_orchestrator, _METADATA, abi.encode());
    }

    /* Test buyingIsEnabled modifier
        ├── when buy is not open
        │       └── it should revert
        └── when buy is open
                └── it should not revert (tested in buyOrder tests)

    */
    function testBuyingIsEnabled_FailsIfBuyNotOpen() public {
        vm.prank(owner_address);
        bondingCurveFundingManger.closeBuy();

        vm.prank(non_owner_address);
        vm.expectRevert(
            IBondingCurveFundingManagerBase
                .BondingCurveFundingManager__BuyingFunctionaltiesClosed
                .selector
        );
        bondingCurveFundingManger.buyOrderFor(non_owner_address, 100);
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
        bondingCurveFundingManger.buyOrderFor(address(0), 100);

        // Test for its own address)
        vm.expectRevert(
            IBondingCurveFundingManagerBase
                .BondingCurveFundingManagerBase__InvalidRecipient
                .selector
        );
        bondingCurveFundingManger.buyOrderFor(
            address(bondingCurveFundingManger), 100
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
            _token.balanceOf(address(bondingCurveFundingManger));
        assertEq(_token.balanceOf(buyer), amount);
        assertEq(bondingCurveFundingManger.balanceOf(buyer), 0);
        assertEq(bondingCurveFundingManger.balanceOf(receiver), 0);

        // Execution
        vm.prank(buyer);
        bondingCurveFundingManger.buyOrderFor(receiver, amount);

        // Post-checks
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManger)),
            (balanceBefore + amount)
        );
        assertEq(_token.balanceOf(buyer), 0);
        assertEq(bondingCurveFundingManger.balanceOf(buyer), 0);
        assertEq(bondingCurveFundingManger.balanceOf(receiver), amount);
    }

    /* Test buyOrder and _buyOrder function
        ├── when the deposit amount is 0
        │       └── it should revert 
        └── when the deposit amount is not 0
                ├── when the fee is higher than 0
                │       └── it should substract the fee from the deposit amount
                │               └── it use determine the mint amount of tokens to mint 
                │               └── it should mint the tokens to the receiver    
                └── when the fee is 0
                        └── it use determine the mint amount of tokens to mint 
                        └── it should mint the tokens to the receiver     
        
    */
    function testBuyOrder_FailsIfDepositAmountIsZero() public {
        vm.startPrank(non_owner_address);

        vm.expectRevert(
            IBondingCurveFundingManagerBase
                .BondingCurveFundingManager__InvalidDepositAmount
                .selector
        );
        bondingCurveFundingManger.buyOrder(0);
    }

    function testBuyOrderWithZeroFee(uint amount) public {
        // Setup
        vm.assume(amount > 0);

        address buyer = makeAddr("buyer");
        _prepareBuyConditions(buyer, amount);

        // Pre-checks
        uint balanceBefore =
            _token.balanceOf(address(bondingCurveFundingManger));
        assertEq(_token.balanceOf(buyer), amount);
        assertEq(bondingCurveFundingManger.balanceOf(buyer), 0);

        // Execution
        vm.prank(buyer);
        bondingCurveFundingManger.buyOrder(amount);

        // Post-checks
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManger)),
            (balanceBefore + amount)
        );
        assertEq(_token.balanceOf(buyer), 0);
        assertEq(bondingCurveFundingManger.balanceOf(buyer), amount);
    }

    function testBuyOrderWithFee(uint amount, uint fee) public {
        // Setup
        uint _bps = bondingCurveFundingManger.call_BPS();
        vm.assume(fee < _bps);

        uint maxAmount = type(uint).max / _bps; // to prevent overflows
        amount = bound(amount, 1, maxAmount);

        vm.prank(owner_address);
        bondingCurveFundingManger.setBuyFee(fee);

        address buyer = makeAddr("buyer");
        _prepareBuyConditions(buyer, amount);

        // Pre-checks
        uint balanceBefore =
            _token.balanceOf(address(bondingCurveFundingManger));
        assertEq(_token.balanceOf(buyer), amount);
        assertEq(bondingCurveFundingManger.balanceOf(buyer), 0);

        // Execution
        vm.prank(buyer);
        bondingCurveFundingManger.buyOrder(amount);

        // Post-checks
        uint amountMinusFee =
            amount - (amount * fee / bondingCurveFundingManger.call_BPS());
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManger)),
            (balanceBefore + amount)
        );
        assertEq(_token.balanceOf(buyer), 0);
        assertEq(bondingCurveFundingManger.balanceOf(buyer), amountMinusFee);
    }

    // Modifier to ensure the caller has the owner role
    modifier callerIsOrchestratorOwner() {
        _authorizer.grantRole(_authorizer.getOwnerRole(), owner_address);
        vm.startPrank(owner_address);
        _;
    }

    /* Test openBuy and _openBuy function
        ├── when caller is not the Orchestrator owner
        │      └── it should revert (tested in base Module modifier tests)
        └── when caller is the Orchestrator owner
               └── when buy functionality is already open
                │      └── it should revert  -> sure? idempotence @note
                └── when buy functionality is not open
                        └── it should open the buy functionality
                        └── it should emit an event? @todo
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
        bondingCurveFundingManger.openBuy();
    }

    function testOpenBuy() public callerIsOrchestratorOwner {
        assertEq(bondingCurveFundingManger.buyIsOpen(), true);

        bondingCurveFundingManger.closeBuy();

        assertEq(bondingCurveFundingManger.buyIsOpen(), false);

        bondingCurveFundingManger.openBuy();

        assertEq(bondingCurveFundingManger.buyIsOpen(), true);
    }

    /* Test closeBuy and _closeBuy function
        ├── when caller is not the Orchestrator owner
        │      └── it should revert (tested in base Module tests)
        └── when caller is the Orchestrator owner
               └── when buy functionality is already closed
                │      └── it should revert ->  sure? idempotence @note
                └── when buy functionality is not closed
                        └── it should close the buy functionality
                        └── it should emit an event? @todo
    */
    function testCloseBuy_FailsIfAlreadyClosed()
        public
        callerIsOrchestratorOwner
    {
        bondingCurveFundingManger.closeBuy();

        vm.expectRevert(
            IBondingCurveFundingManagerBase
                .BondingCurveFundingManager__BuyingAlreadyClosed
                .selector
        );
        bondingCurveFundingManger.closeBuy();
    }

    function testCloseBuy() public callerIsOrchestratorOwner {
        assertEq(bondingCurveFundingManger.buyIsOpen(), true);

        bondingCurveFundingManger.closeBuy();

        assertEq(bondingCurveFundingManger.buyIsOpen(), false);
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
                        └── it should set the new fee
                        └── it should emit an event? @todo
    */
    function testSetBuyFee_FailsIfFee100PercentOrMore(uint _fee)
        public
        callerIsOrchestratorOwner
    {
        vm.assume(_fee >= bondingCurveFundingManger.call_BPS());
        vm.expectRevert(
            IBondingCurveFundingManagerBase
                .BondingCurveFundingManager__InvalidFeePercentage
                .selector
        );
        bondingCurveFundingManger.setBuyFee(_fee);
    }

    function testSetBuyFee(uint newFee) public callerIsOrchestratorOwner {
        vm.assume(newFee < bondingCurveFundingManger.call_BPS());

        bondingCurveFundingManger.setBuyFee(newFee);

        assertEq(bondingCurveFundingManger.buyFee(), newFee);
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
        vm.assume(_fee > bondingCurveFundingManger.call_BPS()); // fetch the BPS value through the mock
        vm.expectRevert(
            IBondingCurveFundingManagerBase
                .BondingCurveFundingManager__InvalidFeePercentage
                .selector
        );
        bondingCurveFundingManger.call_calculateFeeDeductedDepositAmount(
            _depositAmount, _fee
        );
    }

    function testCalculateFeeDeductedDepositAmount(uint _amount, uint _fee)
        public
    {
        uint _bps = bondingCurveFundingManger.call_BPS();
        vm.assume(_fee <= _bps);

        uint maxAmount = type(uint).max / _bps; // to prevent overflows
        _amount = bound(_amount, 1, maxAmount);

        uint amountMinusFee = _amount - (_amount * _fee / _bps);

        uint res = bondingCurveFundingManger
            .call_calculateFeeDeductedDepositAmount(_amount, _fee);

        assertEq(res, amountMinusFee);
    }

    // Test _issueTokens function
    // this is tested in the buyOrder tests

    //--------------------------------------------------------------------------
    // Helper functions

    // Helper function that mints enough collateral tokens to a buyer and approves the bonding curve to spend them
    function _prepareBuyConditions(address buyer, uint amount) internal {
        _token.mint(buyer, amount);
        vm.prank(buyer);
        _token.approve(address(bondingCurveFundingManger), amount);
    }
}
