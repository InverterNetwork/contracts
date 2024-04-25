// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
import {IFundingManager} from "src/modules/fundingManager/IFundingManager.sol";

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
    event ProtocolFeeTransferred(
        address indexed token, address indexed treasury, uint indexed feeAmount
    );
    event ProtocolFeeMinted(
        address indexed token, address indexed treasury, uint indexed feeAmount
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

    function testSupportsInterface() public {
        assertTrue(
            bondingCurveFundingManager.supportsInterface(
                type(IBondingCurveFundingManagerBase).interfaceId
            )
        );
        assertTrue(
            bondingCurveFundingManager.supportsInterface(
                type(IFundingManager).interfaceId
            )
        );
    }

    //--------------------------------------------------------------------------
    // Test: Invariant

    function testBPS() public {
        assertEq(feeManager.BPS(), bondingCurveFundingManager.call_BPS());
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
            IBondingCurveFundingManagerBase
                .BondingCurveFundingManager__BuyingFunctionaltiesClosed
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
            IBondingCurveFundingManagerBase
                .BondingCurveFundingManagerBase__InvalidRecipient
                .selector
        );
        bondingCurveFundingManager.buyFor(address(0), 100, 100);

        // Test for its own address)
        vm.expectRevert(
            IBondingCurveFundingManagerBase
                .BondingCurveFundingManagerBase__InvalidRecipient
                .selector
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
                ├── when the workflow fee is higher than 0
                │       └── it should substract the fee from the deposit amount
                │               ├── it should pull the buy amount from the caller  
                │               ├── it should take the fee out from the pulled amount 
                │               ├── it should determine the mint amount of tokens to mint from the rest
                │               ├── it should mint the tokens to the receiver 
                │               └── it should emit an event?  
                ├── when the workflow fee is 0
                │               ├── it should pull the buy amount from the caller  
                │               ├── it should determine the mint amount of tokens to mint 
                │               ├── it should mint the tokens to the receiver     
                │               └── it should emit an event?  
                └── when the protocol collateral fee is higher than 0
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
            IBondingCurveFundingManagerBase
                .BondingCurveFundingManagerBase__InsufficientOutputAmount
                .selector
        );
        bondingCurveFundingManager.buy(amount, minAmountOut);
    }

    function test_buyOrder(
        uint amount,
        uint _collateralFee,
        uint _issuanceFee,
        uint _workflowFee
    ) public {
        // Setup
        uint _bps = bondingCurveFundingManager.call_BPS();
        _collateralFee = bound(_collateralFee, 0, _bps);
        _issuanceFee = bound(_issuanceFee, 0, _bps);
        _workflowFee = bound(_workflowFee, 0, _bps - 1);
        vm.assume(_collateralFee + _workflowFee < _bps);

        uint maxAmount = type(uint).max / _bps; // to prevent overflows
        amount = bound(amount, 1, maxAmount);

        //Set Fee
        if (_collateralFee != 0) {
            feeManager.setDefaultCollateralFee(_collateralFee);
        }
        if (_issuanceFee != 0) {
            feeManager.setDefaultIssuanceFee(_issuanceFee);
        }

        if (_workflowFee != 0) {
            vm.prank(owner_address);
            bondingCurveFundingManager.setBuyFee(_workflowFee);
        }

        address buyer = makeAddr("buyer");

        // vm.assume(buyer != address(bondingCurveFundingManager) && buyer != address(tr) )
        _prepareBuyConditions(buyer, amount);

        // Pre-checks
        uint balanceBefore =
            _token.balanceOf(address(bondingCurveFundingManager));
        assertEq(_token.balanceOf(buyer), amount);
        assertEq(bondingCurveFundingManager.balanceOf(buyer), 0);

        // Calculate receiving amount

        uint protocolCollateralFeeAmount;
        uint protocolIssuanceFeeAmount;
        uint projectCollateralFeeAmount;
        uint finalAmount;
        uint amountAfterFirstFeeCollection;

        (
            amountAfterFirstFeeCollection,
            protocolCollateralFeeAmount,
            projectCollateralFeeAmount
        ) = bondingCurveFundingManager.call_calculateNetAndSplitFees(
            amount, _collateralFee, _workflowFee
        );

        (finalAmount, protocolIssuanceFeeAmount,) = bondingCurveFundingManager
            .call_calculateNetAndSplitFees(
            amountAfterFirstFeeCollection, _issuanceFee, 0
        );

        // Emit event
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit TokensBought(buyer, amount, finalAmount, buyer); // since the fee gets taken before interacting with the bonding curve, we expect the event to already have the fee substracted

        // Execution
        vm.prank(buyer);
        bondingCurveFundingManager.buy(amount, finalAmount);

        // Post-checks
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManager)),
            (balanceBefore + amount - protocolCollateralFeeAmount)
        );
        assertEq(_token.balanceOf(buyer), 0);
        assertEq(bondingCurveFundingManager.balanceOf(buyer), finalAmount);
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

    /* Test _getBuyFeesAndTreasuryAddresses() function
        └── When the function _getBuyFeesAndTreasuryAddresses() is called
            └── Then it should return the correct collateral treasury address
                └── And it should return the correct issuance treasury address
                    └── And it should return the correct collateral buy fee percentage
                        └── And it should return the correct issuance buy fee percentage

    */

    function testInternalGetBuyFeesAndTreasuryAddresses_works(
        address _treasury,
        uint _collateralFee,
        uint _issuanceFee
    ) public {
        uint _bps = bondingCurveFundingManager.call_BPS();
        vm.assume(_collateralFee <= _bps && _issuanceFee <= _bps);
        vm.assume(_treasury != address(0));

        // Set values in feeManager

        feeManager.setWorkflowTreasuries(address(_orchestrator), _treasury);
        bytes4 buyFeeFunctionSelector =
            bytes4(keccak256(bytes("_buyOrder(address, uint, uint)")));

        feeManager.setCollateralWorkflowFee(
            address(_orchestrator),
            address(bondingCurveFundingManager),
            buyFeeFunctionSelector,
            true,
            _collateralFee
        );
        feeManager.setIssuanceWorkflowFee(
            address(_orchestrator),
            address(bondingCurveFundingManager),
            buyFeeFunctionSelector,
            true,
            _issuanceFee
        );

        (
            address collateralTreasury,
            address issuanceTreasury,
            uint collateralFee,
            uint issuanceFee
        ) = bondingCurveFundingManager.call_getBuyFeesAndTreasuryAddresses();

        assertEq(collateralTreasury, _treasury);
        assertEq(issuanceTreasury, _treasury);
        assertEq(collateralFee, _collateralFee);
        assertEq(issuanceFee, _issuanceFee);
    }

    /* Test _processProtocolFeeViaMinting() function
        ├── Given the fee amount > 0
        │   └── And the treasury address is invalid
        │       └── When the function _processProtocolFeeViaMinting() is called
        │           └── Then the the transaction should revert
        ├── Given the feeAmount == 0
        │   └── When the function _processProtocolFeeViaMinting() is called
        │       └── Then no amount of token should be transferred
        └── Given the feeAmount > 0
            └── And the treasury address is valid
                └── When the function _processProtocolFeeViaMinting() is called
                    └── Then the _feeAmount should be transferred to treasury address
                        └── And an event should be emitted
    */

    function testInternalProcessProtocolFeeViaMinting_failsGivenTreasuryAddressInvalid(
        uint _feeAmount
    ) public {
        vm.assume(_feeAmount > 0);
        address _treasury = address(0);

        vm.expectRevert(
            IBondingCurveFundingManagerBase
                .BondingCurveFundingManagerBase__InvalidRecipient
                .selector
        );
        bondingCurveFundingManager.call_processProtocolFeeViaMinting(
            _treasury, _feeAmount
        );
    }

    function testInternalProcessProtocolFeeViaMinting_worksGivenFeeAmountIsZero(
        uint _feeAmount
    ) public {
        vm.assume(_feeAmount == 0);

        // Get balance before transfer
        uint balanceBeforeTransfer = _token.balanceOf(treasury);
        // Validate treasury has not tokens
        assertEq(balanceBeforeTransfer, 0);
        // Function call
        bondingCurveFundingManager.call_processProtocolFeeViaMinting(
            treasury, _feeAmount
        );
        // Get balance after transfer
        uint balanceAfterTransfer = _token.balanceOf(treasury);

        // Assert eq
        assertEq(balanceAfterTransfer, balanceBeforeTransfer + _feeAmount);
    }

    function testInternalProcessProtocolFeeViaMinting_worksGivenFeeAmountIsNotZero(
        uint _feeAmount
    ) public {
        _feeAmount = bound(_feeAmount, 1, type(uint).max);

        // Get balance before transfer
        uint balanceBeforeTransfer =
            bondingCurveFundingManager.balanceOf(treasury);
        // Validate treasury has not tokens
        assertEq(balanceBeforeTransfer, 0);

        // Expect event
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit ProtocolFeeMinted(
            address(bondingCurveFundingManager), treasury, _feeAmount
        );
        // Function call
        bondingCurveFundingManager.call_processProtocolFeeViaMinting(
            treasury, _feeAmount
        );

        // Get balance after transfer
        uint balanceAfterTransfer =
            bondingCurveFundingManager.balanceOf(treasury);
        // Assert eq
        assertEq(balanceAfterTransfer, balanceBeforeTransfer + _feeAmount);
    }

    /* Test _processProtocolFeeViaTransfer() function
        ├── Given the feeAmount == 0
        │   └── When the function _processProtocolFeeViaTransfer() is called
        │       └── Then no amount of token should be transferred
        ├── Given the fee amount > 0
        │   └── And the treasury address is invalid
        │       └── When the function _processProtocolFeeViaTransfer() is called
        │           └── Then the the transaction should revert
        └── Given the feeAmount > 0
            └── And the treasury address is valid
                └── When the function _processProtocolFeeViaTransfer() is called
                    └── Then the _feeAmount should be transferred to treasury address
    */

    function testInternalProcessProtocolFeeViaTransfer_failsGivenTreasuryAddressInvalid(
        uint _feeAmount
    ) public {
        vm.assume(_feeAmount > 0);
        address _treasury = address(0);

        vm.expectRevert(
            IBondingCurveFundingManagerBase
                .BondingCurveFundingManagerBase__InvalidRecipient
                .selector
        );
        bondingCurveFundingManager.call_processProtocolFeeViaTransfer(
            _treasury, IERC20(_token), _feeAmount
        );
    }

    function testInternalProcessProtocolFeeViaTransfer_worksGivenFeeAmountIsZero(
    ) public {
        uint _feeAmount = 0;

        // Get balance before transfer
        uint balanceBeforeTransfer = _token.balanceOf(treasury);
        // Validate treasury has not tokens
        assertEq(balanceBeforeTransfer, 0);
        // Function call
        bondingCurveFundingManager.call_processProtocolFeeViaTransfer(
            treasury, IERC20(_token), _feeAmount
        );
        // Get balance after transfer
        uint balanceAfterTransfer = _token.balanceOf(treasury);

        // Assert eq
        assertEq(balanceAfterTransfer, balanceBeforeTransfer + _feeAmount);
    }

    function testInternalProcessProtocolFeeViaTransfer_worksGivenFeeAmountIsNotZero(
        uint _feeAmount
    ) public {
        _feeAmount = bound(_feeAmount, 1, type(uint).max);
        _token.mint(address(bondingCurveFundingManager), _feeAmount);
        // Get balance before transfer
        uint balanceBeforeTransfer = _token.balanceOf(treasury);
        // Validate treasury has not tokens
        assertEq(balanceBeforeTransfer, 0);

        // Expect event
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit ProtocolFeeTransferred(address(_token), treasury, _feeAmount);
        // Function call
        bondingCurveFundingManager.call_processProtocolFeeViaTransfer(
            treasury, IERC20(_token), _feeAmount
        );

        // Get balance after transfer
        uint balanceAfterTransfer = _token.balanceOf(treasury);
        // Assert eq
        assertEq(balanceAfterTransfer, balanceBeforeTransfer + _feeAmount);
    }

    /* Test _calculateNetAndSplitFees() function
        ├── Given the (protocol fee + workflow fee) == 0
        │   └── When the function _calculateNetAndSplitFees() is called
        │       └── Then it should return totalAmount as netAmount
        │           └── And it should return 0 for protocol and workflow fee amount
        ├── Given the protocol fee == 0
        │   └── And the workflow fee  > 0
        │       └── When the function _calculateNetAndSplitFees() is called
        │           └── Then it should return the correct netAmount
        │               ├── And it should return protocolFeeAmount as 0
        │               └── And it should return the correct workflowFeeAmount
        ├── Given the protocol fee > 0
        │   └── And the workflow fee == 0
        │       └── When the function _calculateNetAndSplitFees() is called
        │           └── Then it should return the correct netAmount
        │               ├── And it should return the correct protocolFeeAmount
        │               └── And it should return the workflowFeeAmount == 0
        └── Given the protocol fee > 0
            └── And the workflow fee > 0
                └── When the function _calculateNetAndSplitFees() is called
                    └── Then it should return the correct netAmount
                        ├── And it should return the correct protocolFeeAmount
                        └── And it should return the correct workflowFeeAmount
    */

    function testInternalCalculateNetAndSplitFees_CombinedFee0() public {
        (uint netAmount, uint protocolFeeAmount, uint workflowFeeAmount) =
            bondingCurveFundingManager.call_calculateNetAndSplitFees(0, 0, 0);
        assertEq(netAmount, 0);
        assertEq(protocolFeeAmount, 0);
        assertEq(workflowFeeAmount, 0);
    }

    function testInternalCalculateNetAndSplitFees_ProtocolFee0(
        uint totalAmount,
        uint workflowFee
    ) public {
        uint _bps = bondingCurveFundingManager.call_BPS();
        totalAmount = bound(totalAmount, 1, 2 ^ 128);
        workflowFee = bound(workflowFee, 1, _bps);

        (uint netAmount, uint protocolFeeAmount, uint workflowFeeAmount) =
        bondingCurveFundingManager.call_calculateNetAndSplitFees(
            totalAmount, 0, workflowFee
        );
        assertEq(netAmount, totalAmount - workflowFeeAmount);
        assertEq(protocolFeeAmount, 0);
        assertEq(workflowFeeAmount, totalAmount * workflowFee / _bps);
    }

    function testInternalCalculateNetAndSplitFees_ProjectFee0(
        uint totalAmount,
        uint protocolFee
    ) public {
        uint _bps = bondingCurveFundingManager.call_BPS();
        totalAmount = bound(totalAmount, 1, 2 ^ 128);
        protocolFee = bound(protocolFee, 1, _bps);

        (uint netAmount, uint protocolFeeAmount, uint workflowFeeAmount) =
        bondingCurveFundingManager.call_calculateNetAndSplitFees(
            totalAmount, protocolFee, 0
        );
        assertEq(netAmount, totalAmount - protocolFeeAmount);
        assertEq(protocolFeeAmount, totalAmount * protocolFee / _bps);
        assertEq(workflowFeeAmount, 0);
    }

    function testInternalCalculateNetAndSplitFees_FeesBiggerThan0(
        uint totalAmount,
        uint protocolFee,
        uint workflowFee
    ) public {
        uint _bps = bondingCurveFundingManager.call_BPS();
        totalAmount = bound(totalAmount, 1, 2 ^ 128);
        protocolFee = bound(protocolFee, 1, _bps);
        workflowFee = bound(workflowFee, 1, _bps);
        vm.assume(workflowFee + protocolFee < _bps); //@todo add assumption in base code

        (uint netAmount, uint protocolFeeAmount, uint workflowFeeAmount) =
        bondingCurveFundingManager.call_calculateNetAndSplitFees(
            totalAmount, protocolFee, workflowFee
        );

        assertEq(netAmount, totalAmount - protocolFeeAmount - workflowFeeAmount);
        assertEq(protocolFeeAmount, totalAmount * protocolFee / _bps);
        assertEq(workflowFeeAmount, totalAmount * workflowFee / _bps);
    }

    /* Test _setDecimals function
       
        └── when setting decimals
            └── it should succeed
    */

    function testSetDecimals(uint8 _newDecimals) public {
        bondingCurveFundingManager.call_setDecimals(_newDecimals);

        assertEq(bondingCurveFundingManager.decimals(), _newDecimals);
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
