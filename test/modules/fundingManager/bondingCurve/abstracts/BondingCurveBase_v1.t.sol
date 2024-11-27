// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";

// Internal Dependencies
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";
import {BancorFormula} from "@fm/bondingCurve/formulas/BancorFormula.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// Mocks
import {
    BondingCurveBaseV1Mock,
    IBondingCurveBase_v1
} from
    "test/modules/fundingManager/bondingCurve/utils/mocks/BondingCurveBaseV1Mock.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";

contract BondingCurveBaseV1Test is ModuleTest {
    string private constant NAME = "Bonding Curve Token";
    string private constant SYMBOL = "BCT";
    uint8 private constant DECIMALS = 18;
    uint private constant BUY_FEE = 0;
    bool private constant BUY_IS_OPEN = true;

    BondingCurveBaseV1Mock bondingCurveFundingManager;
    address formula;

    ERC20Issuance_v1 issuanceToken;

    address admin_address = makeAddr("alice");
    address non_admin_address = makeAddr("bob");

    event BuyingEnabled();
    event BuyingDisabled();
    event BuyFeeUpdated(uint newBuyFee, uint oldBuyFee);
    event TokensBought(
        address indexed receiver,
        uint depositAmount,
        uint receivedAmount,
        address buyer
    );
    event IssuanceTokenSet(address indexed token, uint8 decimals);

    event ProtocolFeeMinted(
        address indexed token, address indexed treasury, uint feeAmount
    );
    event ProjectCollateralFeeWithdrawn(address receiver, uint amount);

    function setUp() public {
        // Deploy contracts
        address impl = address(new BondingCurveBaseV1Mock());

        bondingCurveFundingManager = BondingCurveBaseV1Mock(Clones.clone(impl));

        formula = address(new BancorFormula());

        issuanceToken = new ERC20Issuance_v1(
            NAME, SYMBOL, DECIMALS, type(uint).max, address(this)
        );

        issuanceToken.setMinter(address(bondingCurveFundingManager), true);

        _setUpOrchestrator(bondingCurveFundingManager);

        _authorizer.grantRole(_authorizer.getAdminRole(), admin_address);

        // Set max fee of feeManager to 100% for testing purposes
        vm.prank(address(governor));
        feeManager.setMaxFee(feeManager.BPS());

        // Init Module
        bondingCurveFundingManager.init(
            _orchestrator,
            _METADATA,
            abi.encode(address(issuanceToken), formula, BUY_FEE, BUY_IS_OPEN)
        );
    }

    function testSupportsInterface() public {
        assertTrue(
            bondingCurveFundingManager.supportsInterface(
                type(IBondingCurveBase_v1).interfaceId
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

    // This function also tests all the getters
    //--------------------------------------------------------------------------
    // Tests: Initialization

    function testInit() public override {
        assertEq(
            issuanceToken.name(),
            string(abi.encodePacked(NAME)),
            "Name has not been set correctly"
        );
        assertEq(
            issuanceToken.symbol(),
            string(abi.encodePacked(SYMBOL)),
            "Symbol has not been set correctly"
        );
        assertEq(
            issuanceToken.decimals(),
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
        vm.prank(admin_address);
        bondingCurveFundingManager.closeBuy();

        vm.prank(non_admin_address);
        vm.expectRevert(
            IBondingCurveBase_v1
                .Module__BondingCurveBase__BuyingFunctionaltiesClosed
                .selector
        );
        bondingCurveFundingManager.buyFor(non_admin_address, 100, 100);
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
        vm.startPrank(non_admin_address);

        // Test for address(0)
        vm.expectRevert(
            IBondingCurveBase_v1
                .Module__BondingCurveBase__InvalidRecipient
                .selector
        );
        bondingCurveFundingManager.buyFor(address(0), 100, 100);

        // Test for its own address)
        vm.expectRevert(
            IBondingCurveBase_v1
                .Module__BondingCurveBase__InvalidRecipient
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
        assertEq(issuanceToken.balanceOf(buyer), 0);
        assertEq(issuanceToken.balanceOf(receiver), 0);

        // Execution
        vm.prank(buyer);
        bondingCurveFundingManager.buyFor(receiver, amount, amount);

        // Post-checks
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManager)),
            (balanceBefore + amount)
        );
        assertEq(_token.balanceOf(buyer), 0);
        assertEq(issuanceToken.balanceOf(buyer), 0);
        assertEq(
            bondingCurveFundingManager.distributeIssuanceTokenFunctionCalled(),
            1
        );
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
                └── when the fee is 0
                                ├── it should pull the buy amount from the caller  
                                ├── it should determine the mint amount of tokens to mint 
                                ├── it should mint the tokens to the receiver     
                                └── it should emit an event?    
        
    */
    function testBuyOrder_FailsIfDepositAmountIsZero() public {
        vm.startPrank(non_admin_address);

        vm.expectRevert(
            IBondingCurveBase_v1
                .Module__BondingCurveBase__InvalidDepositAmount
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
            IBondingCurveBase_v1
                .Module__BondingCurveBase__InsufficientOutputAmount
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
        assertEq(issuanceToken.balanceOf(buyer), 0);

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
        assertEq(
            bondingCurveFundingManager.distributeIssuanceTokenFunctionCalled(),
            1
        );
    }

    function test_buyOrder(
        uint amount,
        uint _collateralFee,
        uint _issuanceFee,
        uint _workflowFee
    ) public {
        // Setup
        uint _bps = bondingCurveFundingManager.call_BPS();
        _collateralFee = bound(_collateralFee, 0, _bps - 1);
        _issuanceFee = bound(_issuanceFee, 0, _bps - 1);
        _workflowFee = bound(_workflowFee, 0, _bps - 1);
        vm.assume(_collateralFee + _workflowFee < _bps);

        amount = bound(
            amount,
            _calculateMinDepositAmount(
                _collateralFee, _workflowFee, _issuanceFee
            ), // minAmount added like this because stack to deep
            (type(uint).max / _bps)
        ); // to prevent overflows

        // Set Fee
        if (_collateralFee != 0) {
            feeManager.setDefaultCollateralFee(_collateralFee);
        }
        if (_issuanceFee != 0) {
            feeManager.setDefaultIssuanceFee(_issuanceFee);
        }

        if (_workflowFee != 0) {
            vm.prank(admin_address);
            bondingCurveFundingManager.setBuyFee(_workflowFee);
        }

        address buyer = makeAddr("buyer");

        _prepareBuyConditions(buyer, amount);

        // Pre-checks
        uint balanceBefore =
            _token.balanceOf(address(bondingCurveFundingManager));
        assertEq(_token.balanceOf(buyer), amount);
        assertEq(issuanceToken.balanceOf(buyer), 0);

        // Calculate receiving amount

        uint protocolCollateralFeeAmount;
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

        (finalAmount,,) = bondingCurveFundingManager
            .call_calculateNetAndSplitFees(
            amountAfterFirstFeeCollection, _issuanceFee, 0
        );

        if (projectCollateralFeeAmount != 0) {
            // Emit event
            vm.expectEmit(
                true, true, true, true, address(bondingCurveFundingManager)
            );
            emit IBondingCurveBase_v1.ProjectCollateralFeeAdded(
                projectCollateralFeeAmount
            );
        }

        // Emit event
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit TokensBought(buyer, amount, finalAmount, buyer); // since the fee gets taken before interacting with the bonding curve, we expect the event to already have the fee substracted

        // Execution
        vm.prank(buyer);
        (, uint collateralFeeAmount) =
            bondingCurveFundingManager.call_buyOrder(buyer, amount, finalAmount);

        assertEq(issuanceToken.balanceOf(treasury), issuanceToken.totalSupply());

        assertEq(
            collateralFeeAmount,
            protocolCollateralFeeAmount + projectCollateralFeeAmount
        );

        // Post-checks
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManager)),
            (balanceBefore + amount - protocolCollateralFeeAmount)
        );
        assertEq(_token.balanceOf(buyer), 0);

        assertEq(
            bondingCurveFundingManager.distributeIssuanceTokenFunctionCalled(),
            1
        );
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
        vm.assume(_collateralFee < _bps && _issuanceFee < _bps);
        vm.assume(_treasury != address(0));

        // Set values in feeManager

        feeManager.setWorkflowTreasury(address(_orchestrator), _treasury);
        bytes4 buyFeeFunctionSelector =
            bytes4(keccak256(bytes("_buyOrder(address,uint,uint)")));

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
            IBondingCurveBase_v1
                .Module__BondingCurveBase__InvalidRecipient
                .selector
        );
        bondingCurveFundingManager.call_processProtocolFeeViaMinting(
            _treasury, _feeAmount
        );
    }

    function testInternalProcessProtocolFeeViaMinting_worksGivenFeeAmountIsZero(
    ) public {
        uint _feeAmount = 0;
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
        uint balanceBeforeTransfer = issuanceToken.balanceOf(treasury);
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
        uint balanceAfterTransfer = issuanceToken.balanceOf(treasury);
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
            IBondingCurveBase_v1
                .Module__BondingCurveBase__InvalidRecipient
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
        emit IModule_v1.ProtocolFeeTransferred(
            address(_token), treasury, _feeAmount
        );
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
        ├── Given the (protocol fee + workflow fee) > BPS / 100%
        │   └── When the function _calculateNetAndSplitFees() is called
        │       └── Then it should revert with BondingCurveFundingManagerBase__FeeAmountToHigh
        ├── given the protocol fee > 0
        │   └── and the amount is low enough such that the workflow feeAmount calculated rounds down to 0
        │       └── when the function _calculateNetAndSplitFee() is called
        │           └── then it should revert
        ├── given the workflow fee > 0
        │   └── and the amount is low enough such that the protocol feeAmount calculated rounds down to 0
        │       └── when the function _calculateNetAndSplitFee() is called
        │           └── then it should revert
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

    function testInternalCalculateNetAndSplitFees_FailsIfFeeIsToHigh(
        uint protocolFee,
        uint workflowFee
    ) public {
        uint _bps = bondingCurveFundingManager.call_BPS();
        protocolFee = bound(protocolFee, 1, _bps - 1);
        workflowFee = bound(workflowFee, 1, _bps - 1);
        vm.assume(protocolFee + workflowFee >= _bps);

        vm.expectRevert(
            IBondingCurveBase_v1
                .Module__BondingCurveBase__FeeAmountToHigh
                .selector
        );
        bondingCurveFundingManager.call_calculateNetAndSplitFees(
            0, protocolFee, workflowFee
        );
    }

    function testInternalCalculateNetAndSplitFees_RevertGivenCalculatedWorkflowFeeAmountRoundsDownToZero(
    ) public {
        uint protocolFee = 0;
        uint workflowFee = 10;
        uint totalAmount = 100;

        vm.expectRevert(
            IBondingCurveBase_v1
                .Module__BondingCurveBase__TradeAmountTooLow
                .selector
        );
        bondingCurveFundingManager.call_calculateNetAndSplitFees(
            workflowFee, protocolFee, totalAmount
        );
    }

    function testInternalCalculateNetAndSplitFees_RevertGivenCalculatedProtocolFeeAmountRoundsDownToZero(
    ) public {
        uint protocolFee = 10;
        uint workflowFee = 0;
        uint totalAmount = 100;

        vm.expectRevert(
            IBondingCurveBase_v1
                .Module__BondingCurveBase__TradeAmountTooLow
                .selector
        );
        bondingCurveFundingManager.call_calculateNetAndSplitFees(
            workflowFee, protocolFee, totalAmount
        );
    }

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
        workflowFee = bound(workflowFee, 1, _bps - 1);

        uint minAmount = _bps / workflowFee + 1; // calculate min amount
        totalAmount = bound(totalAmount, minAmount, type(uint128).max);

        (uint netAmount, uint protocolFeeAmount, uint workflowFeeAmount) =
        bondingCurveFundingManager.call_calculateNetAndSplitFees(
            totalAmount, 0, workflowFee
        );
        assertEq(netAmount, totalAmount - workflowFeeAmount);
        assertEq(protocolFeeAmount, 0);
        assertEq(workflowFeeAmount, (totalAmount * workflowFee) / _bps);
    }

    function testInternalCalculateNetAndSplitFees_ProjectFee0(
        uint totalAmount,
        uint protocolFee
    ) public {
        uint _bps = bondingCurveFundingManager.call_BPS();
        protocolFee = bound(protocolFee, 1, _bps - 1);

        // calculate min amount
        uint minAmount = _bps / protocolFee + 1;
        totalAmount = bound(totalAmount, minAmount, type(uint128).max);

        (uint netAmount, uint protocolFeeAmount, uint workflowFeeAmount) =
        bondingCurveFundingManager.call_calculateNetAndSplitFees(
            totalAmount, protocolFee, 0
        );
        assertEq(netAmount, totalAmount - protocolFeeAmount);
        assertEq(protocolFeeAmount, (totalAmount * protocolFee) / _bps);
        assertEq(workflowFeeAmount, 0);
    }

    function testInternalCalculateNetAndSplitFees_FeesBiggerThan0(
        uint totalAmount,
        uint protocolFee,
        uint workflowFee
    ) public {
        uint _bps = bondingCurveFundingManager.call_BPS();
        protocolFee = bound(protocolFee, 1, _bps - 1);
        workflowFee = bound(workflowFee, 1, _bps - 1);
        vm.assume(workflowFee + protocolFee < _bps);

        uint minAmount = _calculateMinDepositAmount(protocolFee, workflowFee, 0);
        totalAmount = bound(totalAmount, minAmount, type(uint128).max);

        (uint netAmount, uint protocolFeeAmount, uint workflowFeeAmount) =
        bondingCurveFundingManager.call_calculateNetAndSplitFees(
            totalAmount, protocolFee, workflowFee
        );

        assertEq(netAmount, totalAmount - protocolFeeAmount - workflowFeeAmount);
        assertEq(protocolFeeAmount, (totalAmount * protocolFee) / _bps);
        assertEq(workflowFeeAmount, (totalAmount * workflowFee) / _bps);
    }

    /* Test openBuy and _openBuy function
        ├── when caller is not the Orchestrator_v1 admin
        │      └── it should revert (tested in base Module modifier tests)
        └── when caller is the Orchestrator_v1 admin
               └── when buy functionality is already open
                │      └── it should stay as is
                │      └── it should emit an event
                └── when buy functionality is not open
                        └── it should open the buy functionality
                        └── it should emit an event
    */
    function testOpenBuy_Idempotence() public callerIsOrchestratorAdmin {
        assertEq(bondingCurveFundingManager.buyIsOpen(), true);

        vm.expectEmit(address(bondingCurveFundingManager));
        emit BuyingEnabled();

        bondingCurveFundingManager.openBuy();

        assertEq(bondingCurveFundingManager.buyIsOpen(), true);
    }

    function testOpenBuy() public callerIsOrchestratorAdmin {
        assertEq(bondingCurveFundingManager.buyIsOpen(), true);

        bondingCurveFundingManager.closeBuy();

        assertEq(bondingCurveFundingManager.buyIsOpen(), false);

        vm.expectEmit(address(bondingCurveFundingManager));
        emit BuyingEnabled();

        bondingCurveFundingManager.openBuy();

        assertEq(bondingCurveFundingManager.buyIsOpen(), true);
    }

    /* Test closeBuy and _closeBuy function
        ├── when caller is not the Orchestrator_v1 admin
        │      └── it should revert (tested in base Module tests)
        └── when caller is the Orchestrator_v1 admin
               └── when buy functionality is already closed
                │      └── it should stay as is
                │      └── it should emit an event
                └── when buy functionality is not closed
                        ├── it should close the buy functionality
                        └── it should emit an event
    */
    function testCloseBuy_FailsIfAlreadyClosed()
        public
        callerIsOrchestratorAdmin
    {
        vm.expectEmit(address(bondingCurveFundingManager));
        emit BuyingDisabled();

        bondingCurveFundingManager.closeBuy();

        assertEq(bondingCurveFundingManager.buyIsOpen(), false);

        vm.expectEmit(address(bondingCurveFundingManager));
        emit BuyingDisabled();

        bondingCurveFundingManager.closeBuy();

        assertEq(bondingCurveFundingManager.buyIsOpen(), false);
    }

    function testCloseBuy() public callerIsOrchestratorAdmin {
        assertEq(bondingCurveFundingManager.buyIsOpen(), true);

        vm.expectEmit(address(bondingCurveFundingManager));
        emit BuyingDisabled();

        bondingCurveFundingManager.closeBuy();

        assertEq(bondingCurveFundingManager.buyIsOpen(), false);
    }

    /* Test setBuyFee and _setBuyFee function
        ├── when caller is not the Orchestrator_v1 admin
        │      └── it should revert (tested in base Module tests)
        └── when caller is the Orchestrator_v1 admin
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
        callerIsOrchestratorAdmin
    {
        vm.assume(_fee > bondingCurveFundingManager.call_BPS());
        vm.expectRevert(
            IBondingCurveBase_v1
                .Module__BondingCurveBase__InvalidFeePercentage
                .selector
        );
        bondingCurveFundingManager.setBuyFee(_fee);
    }

    function testSetBuyFee(uint newFee) public callerIsOrchestratorAdmin {
        vm.assume(newFee < bondingCurveFundingManager.call_BPS());

        vm.expectEmit(
            true, true, false, false, address(bondingCurveFundingManager)
        );
        emit BuyFeeUpdated(newFee, BUY_FEE);

        bondingCurveFundingManager.setBuyFee(newFee);

        assertEq(bondingCurveFundingManager.buyFee(), newFee);
    }

    /* Test _setIssuanceToken function
       
        └── when setting the Token
            ├── it should set the new token
            ├── it should emit an event
            ├── it should cache the new decimals
            └── it should succeed
    */

    function testSetIssuanceToken(uint _newMaxSupply, uint8 _newDecimals)
        public
    {
        vm.assume(_newDecimals > 0);
        vm.assume(_newMaxSupply != 0);

        address tokenBefore =
            address(bondingCurveFundingManager.getIssuanceToken());

        string memory _name = "New Issuance Token";
        string memory _symbol = "NEW";

        ERC20Issuance_v1 newIssuanceToken = new ERC20Issuance_v1(
            _name, _symbol, _newDecimals, _newMaxSupply, address(this)
        );

        // Emit event
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit IssuanceTokenSet(address(newIssuanceToken), _newDecimals);
        bondingCurveFundingManager.call_setIssuanceToken(
            address(newIssuanceToken)
        );

        ERC20Issuance_v1 issuanceTokenAfter =
            ERC20Issuance_v1(bondingCurveFundingManager.getIssuanceToken());

        assertNotEq(tokenBefore, address(issuanceTokenAfter));
        assertEq(issuanceTokenAfter.name(), _name);
        assertEq(issuanceTokenAfter.symbol(), _symbol);
        assertEq(issuanceTokenAfter.decimals(), _newDecimals);
        assertEq(issuanceTokenAfter.cap(), _newMaxSupply);
    }

    /* Test internal _calculatePurchaseReturn function
        ├── When deposit amount is 0
        │       └── it should revert 
        └── When deposit amount is not 0
                ├── when the fee is 0
                │       └── it should succeed 
                └── when the fee is not 0
                        └── it should succeed 
    */

    function testInternalCalculatePurchaseReturn_FailsIfDepositAmountZero()
        public
    {
        uint depositAmount = 0;

        vm.expectRevert(
            IBondingCurveBase_v1
                .Module__BondingCurveBase__InvalidDepositAmount
                .selector
        );
        bondingCurveFundingManager.call_calculatePurchaseReturn(depositAmount);
    }

    function testInternalCalculatePurchaseReturnWithZeroFee(uint _depositAmount)
        public
    {
        // Above an amount of 1e38 the BancorFormula starts to revert.
        _depositAmount = bound(_depositAmount, 1, 1e38);

        // As the implementation is a mock, we return the deposit amount in a 1:1 ratio
        uint functionReturn = bondingCurveFundingManager
            .call_calculatePurchaseReturn(_depositAmount);
        assertEq(functionReturn, _depositAmount);
    }

    function testInternalCalculatePurchaseReturnWithFee(
        uint _depositAmount,
        uint _collateralFee,
        uint _issuanceFee,
        uint _workflowFee
    ) public {
        // Setup
        uint _bps = bondingCurveFundingManager.call_BPS();
        _collateralFee = bound(_collateralFee, 0, _bps - 1);
        _issuanceFee = bound(_issuanceFee, 0, _bps - 1);
        _workflowFee = bound(_workflowFee, 0, _bps - 1);
        vm.assume(_collateralFee + _workflowFee < _bps);

        uint minAmount = _calculateMinDepositAmount(
            _collateralFee, _workflowFee, _issuanceFee
        );

        _depositAmount = bound(_depositAmount, minAmount, type(uint128).max);

        // Set Fee
        if (_collateralFee != 0) {
            feeManager.setDefaultCollateralFee(_collateralFee);
        }
        if (_issuanceFee != 0) {
            feeManager.setDefaultIssuanceFee(_issuanceFee);
        }

        if (_workflowFee != 0) {
            vm.prank(admin_address);
            bondingCurveFundingManager.setBuyFee(_workflowFee);
        }

        // Deduct protocol and project buy fee from collateral
        (
            uint netCollateralDepositAmount, /* protocolFeeAmount */ /* workflowFeeAmount */
            ,
        ) = bondingCurveFundingManager.call_calculateNetAndSplitFees(
            _depositAmount, _collateralFee, _workflowFee
        );
        // As the implementation is a mock and the function calculatePurchaseReturn returns the deposit amount
        // in a 1:1 ratio, we use the collateral deposit amount without fee to withdraw the issuance fee

        // Deduct protocol buy fee from issuance
        (
            uint netIssuanceMintAmount, /* protocolFeeAmount */ /* workflowFeeAmount */
            ,
        ) = bondingCurveFundingManager.call_calculateNetAndSplitFees(
            netCollateralDepositAmount, _issuanceFee, 0
        );

        // Get return value from function
        uint functionReturn = bondingCurveFundingManager
            .call_calculatePurchaseReturn(_depositAmount);

        assertEq(functionReturn, netIssuanceMintAmount);
    }

    /*    Test calculatePurchaseReturn function
            └── when function calculatePurchaseReturn is called
                └── then it should return the same as the internal _calculatePurchaseReturn function
    */
    function testCalculatePurchaseReturn_workGivenSameValueReturnedAsInternalFunction(
        uint _depositAmount
    ) public {
        _depositAmount = bound(_depositAmount, 1, 1e38);

        uint internalFunctionReturnValue = bondingCurveFundingManager
            .call_calculatePurchaseReturn(_depositAmount);

        uint functionReturnValue =
            bondingCurveFundingManager.calculatePurchaseReturn(_depositAmount);

        assertEq(internalFunctionReturnValue, functionReturnValue);
    }

    /*    Test withdrawProjectCollateralFee function
            └── Given the receiver is address zero or equal to bonding curve address
                └── When the function withdrawProjectCollateralFee function gets called
                    └── Then it should revert with invalid receiver
    */

    function testWithdrawProjectCollateralFee_revertGivenInvalidReceiver(
        uint _amount
    ) public {
        address receiver = address(0);

        vm.expectRevert(
            IBondingCurveBase_v1
                .Module__BondingCurveBase__InvalidRecipient
                .selector
        );
        bondingCurveFundingManager.withdrawProjectCollateralFee(
            receiver, _amount
        );

        receiver = address(bondingCurveFundingManager);
        vm.expectRevert(
            IBondingCurveBase_v1
                .Module__BondingCurveBase__InvalidRecipient
                .selector
        );
        bondingCurveFundingManager.withdrawProjectCollateralFee(
            receiver, _amount
        );
    }

    /*    Test internal _withdrawProjectCollateralFee function
            ├── Given the amount is bigger than the project trade fee collected
            │   └── When the internal function _withdrawProjectCollateralFee function gets called
            │       └── Then it should revert with invalid amount
            └── Given the amount is valid
                └── When the internal function _withdrawProjectCollateralFee function gets called
                    └── Then it should succeed in transferring the amount
                        ├── And it should update the state variable
                        └── And it should emit an event
    */

    function testInternalWithdrawProjectCollateralFee_revertGivenInvalidAmount(
        uint _amount
    ) public {
        address receiver = makeAddr("receiver");
        _amount = bound(_amount, 2, 1e36);
        // Set project fee lower than amount to be claimed
        uint projectTradeFeeCollected = _amount - 1;
        bondingCurveFundingManager.setProjectCollateralFeeCollectedHelper(
            projectTradeFeeCollected
        );

        vm.expectRevert(
            IBondingCurveBase_v1
                .Module__BondingCurveBase__InvalidWithdrawAmount
                .selector
        );
        bondingCurveFundingManager.call_withdrawProjectCollateralFee(
            receiver, _amount
        );
    }

    function testInternalWithdrawProjectCollateralFee_worksGivenValidAmountAndValidReceiver(
        uint _amount
    ) public {
        address receiver = makeAddr("receiver");

        _amount = bound(_amount, 2, 1e36);
        // Set project fee 1 higher than amount to be claimed
        uint projectTradeFeeCollected = _amount + 1;
        bondingCurveFundingManager.setProjectCollateralFeeCollectedHelper(
            projectTradeFeeCollected
        );
        assertEq(
            bondingCurveFundingManager.projectCollateralFeeCollected(),
            projectTradeFeeCollected
        );
        // mint collateral to bonding curve funding manager so it has enough to transfer fee
        _token.mint(
            address(bondingCurveFundingManager), projectTradeFeeCollected
        );

        // Assert receiver has not tokens
        assertEq(_token.balanceOf(receiver), 0);

        // Emit event
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit ProjectCollateralFeeWithdrawn(receiver, _amount);
        // Execute function
        bondingCurveFundingManager.call_withdrawProjectCollateralFee(
            receiver, _amount
        );

        // Assert right amount is deducted
        assertEq(
            bondingCurveFundingManager.projectCollateralFeeCollected(),
            projectTradeFeeCollected - _amount
        );
        // Assert right amount has been received
        assertEq(_token.balanceOf(receiver), _amount);
        // Assert right amount is still in FM_BC
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManager)),
            projectTradeFeeCollected - _amount
        );
    }

    /*  Test internal _ensureNonZeroTradeParameters()
        ├── given the depositAmount == 0
        │   └── when the internal function _ensureNonZeroTradeParameters() gets called
        │       └── then it should revert
        └── given the minAmountOut == 0
            └── when the internal function _ensureNonZeroTradeParameters() gets called
                └── then it should revert
    */

    function testInternalEnsureNonZeroTradeParameters_FailsGivenDepositAmountIsZero(
        uint _minAmountOut
    ) external {
        uint _depositAmount = 0;

        _minAmountOut = bound(_minAmountOut, 1, type(uint128).max);
        vm.expectRevert(
            IBondingCurveBase_v1
                .Module__BondingCurveBase__InvalidDepositAmount
                .selector
        );
        bondingCurveFundingManager.call_ensureNonZeroTradeParameters(
            _depositAmount, _minAmountOut
        );
    }

    function testInternalEnsureNonZeroTradeParameters_FailsGivenMinAmountOutIsZero(
        uint _depositAmount
    ) external {
        uint _minAmountOut = 0;

        _depositAmount = bound(_depositAmount, 1, type(uint128).max);
        vm.expectRevert(
            IBondingCurveBase_v1
                .Module__BondingCurveBase__InvalidMinAmountOut
                .selector
        );
        bondingCurveFundingManager.call_ensureNonZeroTradeParameters(
            _depositAmount, _minAmountOut
        );
    }

    // Test _handleIssuanceTokensAfterBuy function
    // this is tested in the buy tests

    //--------------------------------------------------------------------------
    // Helper functions

    // Modifier to ensure the caller has the admin role
    modifier callerIsOrchestratorAdmin() {
        _authorizer.grantRole(_authorizer.getAdminRole(), admin_address);
        vm.startPrank(admin_address);
        _;
    }

    // Helper function that mints enough collateral tokens to a buyer and approves the bonding curve to spend them
    function _prepareBuyConditions(address buyer, uint amount) internal {
        _token.mint(buyer, amount);
        vm.prank(buyer);
        _token.approve(address(bondingCurveFundingManager), amount);
    }

    // Helper function which calculates the minimum deposit amount which will not revert based on rounding down issue with integer division
    // when subtracting the fee amounts, given the different collateral and issuance fee.
    function _calculateMinDepositAmount(
        uint _collateralFee,
        uint _workflowFee,
        uint _issuanceFee
    ) internal view returns (uint minAmount) {
        uint _bps = bondingCurveFundingManager.call_BPS();

        // Calculate minimum amount for the first call
        uint minAmountCollateral =
            _collateralFee != 0 ? _bps / _collateralFee + 1 : 1;
        uint minAmountWorkflow = _workflowFee != 0 ? _bps / _workflowFee + 1 : 1;
        uint minAmountFirstCall = minAmountCollateral > minAmountWorkflow
            ? minAmountCollateral
            : minAmountWorkflow;

        // Calculate minimum amount for the second call, considering the effect of the first call
        uint minAmountIssuance = _issuanceFee != 0
            ? (_bps * _bps)
                / (_issuanceFee * (_bps - _collateralFee - _workflowFee)) + 1
            : 1;

        // Use the larger of the two minimum amounts
        minAmount = minAmountFirstCall > minAmountIssuance
            ? minAmountFirstCall
            : minAmountIssuance;
    }
}
