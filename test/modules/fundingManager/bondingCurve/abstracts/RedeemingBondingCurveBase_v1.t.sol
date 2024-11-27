// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";

import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";

// Internal Dependencies
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";
import {BancorFormula} from "@fm/bondingCurve/formulas/BancorFormula.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// Mocks
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {
    RedeemingBondingCurveBaseV1Mock,
    IRedeemingBondingCurveBase_v1
} from
    "test/modules/fundingManager/bondingCurve/utils/mocks/RedeemingBondingCurveBaseV1Mock.sol";

contract RedeemingBondingCurveBaseV1Test is ModuleTest {
    string private constant NAME = "Bonding Curve Token";
    string private constant SYMBOL = "BCT";
    uint8 private constant DECIMALS = 18;
    uint internal constant MAX_SUPPLY = type(uint).max;

    uint private constant BUY_FEE = 0;
    uint private constant SELL_FEE = 0;
    bool private constant BUY_IS_OPEN = true;
    bool private constant SELL_IS_OPEN = true;

    RedeemingBondingCurveBaseV1Mock bondingCurveFundingManager;
    address formula;

    ERC20Issuance_v1 issuanceToken;

    address admin_address = address(0xA1BA);
    address non_admin_address = address(0xB0B);

    event SellingEnabled();
    event SellingDisabled();
    event SellFeeUpdated(uint newSellFee, uint oldSellFee);
    event TokensSold(
        address indexed receiver,
        uint depositAmount,
        uint receivedAmount,
        address seller
    );

    function setUp() public {
        // Deploy contracts
        address impl = address(new RedeemingBondingCurveBaseV1Mock());

        bondingCurveFundingManager =
            RedeemingBondingCurveBaseV1Mock(Clones.clone(impl));

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
            abi.encode(
                address(issuanceToken),
                formula,
                BUY_FEE,
                BUY_IS_OPEN,
                SELL_IS_OPEN
            )
        );
    }

    function testSupportsInterface() public {
        assertTrue(
            bondingCurveFundingManager.supportsInterface(
                type(IRedeemingBondingCurveBase_v1).interfaceId
            )
        );
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
        assertEq(
            bondingCurveFundingManager.buyFee(),
            SELL_FEE,
            "Sell fee has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManager.buyIsOpen(),
            SELL_IS_OPEN,
            "Sell-is-open has not been set correctly"
        );
    }

    function testReinitFails() public override {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        bondingCurveFundingManager.init(_orchestrator, _METADATA, abi.encode());
    }

    /* Test sellingIsEnabled modifier
        ├── when sell is not open
        │       └── it should revert
        └── when sell is open
                └── it should not revert (tested in sell tests)

    */
    function testSellingIsEnabled_FailsIfSellNotOpen() public {
        vm.prank(admin_address);
        bondingCurveFundingManager.closeSell();

        vm.prank(non_admin_address);
        vm.expectRevert(
            IRedeemingBondingCurveBase_v1
                .Module__RedeemingBondingCurveBase__SellingFunctionaltiesClosed
                .selector
        );
        bondingCurveFundingManager.sellTo(non_admin_address, 100, 100);
    }

    // test modifier on sellTo function

    function testPassingModifiersOnSellOrderFor(uint sellAmount) public {
        // Setup
        vm.assume(sellAmount > 0);

        address seller = makeAddr("seller");
        address receiver = makeAddr("receiver");

        _prepareSellConditions(seller, sellAmount);

        // Pre-checks
        uint bondingCurveBalanceBefore =
            _token.balanceOf(address(bondingCurveFundingManager));
        uint receiverBalanceBefore = _token.balanceOf(receiver);
        assertEq(_token.balanceOf(seller), 0);
        assertEq(_token.balanceOf(receiver), 0);
        assertEq(issuanceToken.balanceOf(seller), sellAmount);

        // Execution
        vm.prank(seller);
        bondingCurveFundingManager.sellTo(receiver, sellAmount, sellAmount);

        // Post-checks
        uint redeemAmount = _token.balanceOf(receiver) - receiverBalanceBefore;
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManager)),
            (bondingCurveBalanceBefore - redeemAmount)
        );
        assertEq(issuanceToken.balanceOf(seller), 0);
        assertEq(_token.balanceOf(seller), 0);
    }

    /* Test sell and _sellOrder function
        ├── when the sell amount is 0
        │       └── it should revert 
        └── when the sell amount is not 0
                ├── when the return amount is lower than minimum expected amount out
                │       └── it should revert 
                ├── when the fee is higher than 0
                │               ├── it should burn the sell amount from the caller
                │               ├── it should determine the redeem amount of the sent tokens 
                │               ├── it should substract the fee from the redeem amount
                │               ├── When there IS NOT enough collateral in the contract to cover the redeem amount
                │               │        └── it should revert
                │               └── When there IS enough collateral in the contract to cover the redeem amount
                │                   ├── it should send the rest to the receiver    
                │                   └── it should emit an event
                └── when the fee is 0
                                ├── it should burn the sell amount from the caller
                                ├── it should determine the redeem amount of the sent tokens 
                                ├── When there IS NOT enough collateral in the contract to cover the redeem amount
                                │        └── it should revert
                                └── When there IS enough collateral in the contract to cover the redeem amount
                                   ├── it should send the rest to the receiver    
                                   └── it should emit an event
    */

    function testSellOrder_FailsIfDepositAmountIsZero() public {
        vm.startPrank(non_admin_address);
        {
            vm.expectRevert(
                IBondingCurveBase_v1
                    .Module__BondingCurveBase__InvalidDepositAmount
                    .selector
            );
            bondingCurveFundingManager.sell(0, 0);
        }
        vm.stopPrank();
    }

    function testSellOrder_FailsIfNotEnoughCollateralInContract(uint amount)
        public
    {
        // Setup
        vm.assume(amount > 0);

        address seller = makeAddr("seller");
        _prepareSellConditions(seller, amount);

        // we simulate the fundingManager spending some funds. It can't cover full redemption anymore.
        _token.burn(address(bondingCurveFundingManager), 1);

        vm.startPrank(seller);
        {
            vm.expectRevert(
                IRedeemingBondingCurveBase_v1
                    .Module__RedeemingBondingCurveBase__InsufficientCollateralForRedemption
                    .selector
            );
            bondingCurveFundingManager.sell(amount, amount);
        }
        vm.stopPrank();
    }

    function testSellOrder_FailsIfReturnAmountIsLowerThanMinAmount(uint amount)
        public
    {
        // Setup
        vm.assume(amount > 0 && amount < UINT256_MAX - 1); // Assume no max Uint because 1 is added for minAmountOut

        address seller = makeAddr("seller");
        _prepareSellConditions(seller, amount);
        // Mock formula contract returns amount in as amount out. Add 1 to trigger revert
        uint minAmountOut = amount + 1;

        vm.startPrank(seller);
        vm.expectRevert(
            IBondingCurveBase_v1
                .Module__BondingCurveBase__InsufficientOutputAmount
                .selector
        );
        bondingCurveFundingManager.sell(amount, minAmountOut);
    }

    function test_sellOrder(
        uint amount,
        uint _collateralFee,
        uint _issuanceFee,
        uint _workflowFee
    ) public {
        // Setup
        uint _bps = bondingCurveFundingManager.call_BPS();
        _collateralFee = bound(_collateralFee, 0, _bps);
        _issuanceFee = bound(_issuanceFee, 0, _bps - 1);
        _workflowFee = bound(_workflowFee, 0, _bps - 1);
        vm.assume(_collateralFee + _workflowFee < _bps);

        uint maxAmount = type(uint).max / _bps; // to prevent overflows
        amount = bound(
            amount,
            helperCalculateMinDepositAmount(
                _collateralFee, _issuanceFee, _workflowFee
            ),
            maxAmount
        );

        address seller = makeAddr("seller");
        _prepareSellConditions(seller, amount);

        // Set Fee
        if (_collateralFee != 0) {
            feeManager.setDefaultCollateralFee(_collateralFee);
        }
        if (_issuanceFee != 0) {
            feeManager.setDefaultIssuanceFee(_issuanceFee);
        }

        if (_workflowFee != 0) {
            vm.prank(admin_address);
            bondingCurveFundingManager.setSellFee(_workflowFee);
        }

        // Calculate receive amount

        uint protocolIssuanceFeeAmount;
        uint projectCollateralFeeAmount;
        uint finalAmount;
        uint amountAfterFirstFeeCollection;

        (amountAfterFirstFeeCollection, protocolIssuanceFeeAmount,) =
        bondingCurveFundingManager.call_calculateNetAndSplitFees(
            amount, _issuanceFee, 0
        );

        (finalAmount,, projectCollateralFeeAmount) = bondingCurveFundingManager
            .call_calculateNetAndSplitFees(
            amountAfterFirstFeeCollection, _collateralFee, _workflowFee
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
        emit TokensSold(seller, amount, finalAmount, seller);

        // Execution
        vm.prank(seller);
        (uint totalCollateralTokenMovedOut, uint returnedIssuanceFeeAmount) =
        bondingCurveFundingManager.call_sellOrder(seller, amount, finalAmount);

        assertEq(totalCollateralTokenMovedOut, amountAfterFirstFeeCollection);
        assertEq(returnedIssuanceFeeAmount, protocolIssuanceFeeAmount);

        // Post-checks
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManager)),
            protocolIssuanceFeeAmount + projectCollateralFeeAmount + finalAmount
        );

        assertEq(_token.balanceOf(seller), 0);
        assertEq(
            1,
            bondingCurveFundingManager.distributeCollateralTokenFunctionCalled()
        );

        assertEq(issuanceToken.balanceOf(seller), 0);
        assertEq(issuanceToken.totalSupply(), protocolIssuanceFeeAmount);
    }

    /* Test openSell function
        ├── when caller is not the Orchestrator admin
        │      └── it should revert (tested in base Module modifier tests)
        └── when caller is the Orchestrator admin
               └── when sell functionality is already open
                │      └── it should stay as is
                │      └── it should reemit an eventvert
                └── when sell functionality is not open
                        ├── it should open the sell functionality
                        └── it should emit an event
    */
    function testOpenSell_Idempotence() public callerIsOrchestratorAdmin {
        assertEq(bondingCurveFundingManager.sellIsOpen(), true);
        vm.expectEmit(address(bondingCurveFundingManager));
        emit SellingEnabled();

        bondingCurveFundingManager.openSell();
    }

    function testOpenSell() public callerIsOrchestratorAdmin {
        assertEq(bondingCurveFundingManager.sellIsOpen(), true);

        bondingCurveFundingManager.closeSell();

        assertEq(bondingCurveFundingManager.sellIsOpen(), false);

        vm.expectEmit(address(bondingCurveFundingManager));
        emit SellingEnabled();

        bondingCurveFundingManager.openSell();

        assertEq(bondingCurveFundingManager.sellIsOpen(), true);
    }

    /* Test closeSell function
        ├── when caller is not the Orchestrator admin
        │      └── it should revert (tested in base Module tests)
        └── when caller is the Orchestrator admin
               └── when sell functionality is already closed
                │      └── it should stay as is
                │      └── it should reemit an eventvert
                └── when sell functionality is not closed
                        ├── it should close the sell functionality
                        └── it should emit an event
    */

    function testCloseSell_FailsIfAlreadyClosed()
        public
        callerIsOrchestratorAdmin
    {
        assertEq(bondingCurveFundingManager.sellIsOpen(), true);

        vm.expectEmit(address(bondingCurveFundingManager));
        emit SellingDisabled();
        bondingCurveFundingManager.closeSell();

        assertEq(bondingCurveFundingManager.sellIsOpen(), false);

        vm.expectEmit(address(bondingCurveFundingManager));
        emit SellingDisabled();
        bondingCurveFundingManager.closeSell();

        assertEq(bondingCurveFundingManager.sellIsOpen(), false);
    }

    function testCloseSell() public callerIsOrchestratorAdmin {
        assertEq(bondingCurveFundingManager.sellIsOpen(), true);

        vm.expectEmit(address(bondingCurveFundingManager));
        emit SellingDisabled();
        bondingCurveFundingManager.closeSell();

        assertEq(bondingCurveFundingManager.sellIsOpen(), false);
    }

    /* Test setSellFee and _setSellFee function
        ├── when caller is not the Orchestrator admin
        │      └── it should revert (tested in base Module tests)
        └── when caller is the Orchestrator admin
               └── when fee is over 100% 
                │      └── it should revert
                ├── when fee is 100% 
                │       ├── it should set the new fee (it's basically a burn function))
                │       └── it should emit an event
                └── when fee is below 100%
                        ├── it should set the new fee
                        └── it should emit an event?
    */

    function testSetSellFee_FailsIfFeeIsOver100Percent(uint _fee)
        public
        callerIsOrchestratorAdmin
    {
        vm.assume(_fee > bondingCurveFundingManager.call_BPS());
        vm.expectRevert(
            IBondingCurveBase_v1
                .Module__BondingCurveBase__InvalidFeePercentage
                .selector
        );
        bondingCurveFundingManager.setSellFee(_fee);
    }

    function testSetSellFee(uint _fee) public callerIsOrchestratorAdmin {
        vm.assume(_fee <= bondingCurveFundingManager.call_BPS());

        uint oldSellFee = bondingCurveFundingManager.sellFee();

        vm.expectEmit(
            true, true, false, false, address(bondingCurveFundingManager)
        );
        emit SellFeeUpdated(_fee, oldSellFee);
        bondingCurveFundingManager.setSellFee(_fee);

        assertEq(bondingCurveFundingManager.sellFee(), _fee);
    }

    /* Test internal _calculateSaleReturn function
        ├── When deposit amount is 0
        │       └── it should revert 
        └── When deposit amount is not 0
                ├── when the fee is 0
                │       └── it should succeed 
                └── when the fee is not 0
                        └── it should succeed 
    */

    function testInternalCalculateSaleReturn_FailsIfDepositAmountZero()
        public
    {
        uint depositAmount = 0;

        vm.expectRevert(
            IBondingCurveBase_v1
                .Module__BondingCurveBase__InvalidDepositAmount
                .selector
        );
        bondingCurveFundingManager.calculateSaleReturn(depositAmount);
    }

    function testInternalCalculateSaleReturnWithZeroFee(uint _depositAmount)
        public
    {
        // Above an amount of 1e26 the BancorFormula starts to revert.
        _depositAmount = bound(_depositAmount, 1, 1e26);

        // As the implementation is a mock, we return the deposit amount in a 1:1 ratio
        uint functionReturn =
            bondingCurveFundingManager.calculateSaleReturn(_depositAmount);
        assertEq(functionReturn, _depositAmount);
    }

    function helperMax(uint a, uint b) public pure returns (uint) {
        return a >= b ? a : b;
    }

    function helperCalculateMinDepositAmount(
        uint _collateralFee,
        uint _issuanceFee,
        uint _workflowFee
    ) public view returns (uint _depositAmount) {
        uint _bps = bondingCurveFundingManager.call_BPS();

        uint minDepositAmountWorkflowFee = 0;
        uint minDepositAmountIssuanceFee = 0;
        uint minDepositAmountCollateralFee = 0;
        if (_workflowFee > 0) {
            minDepositAmountWorkflowFee =
                _bps / _workflowFee + (_bps % _workflowFee > 0 ? 1 : 0);
        }
        if (_issuanceFee > 0) {
            minDepositAmountIssuanceFee =
                _bps / _issuanceFee + (_bps % _issuanceFee > 0 ? 1 : 0);
        }
        if (_collateralFee > 0) {
            minDepositAmountCollateralFee =
                _bps / _collateralFee + (_bps % _collateralFee > 0 ? 1 : 0);
        }

        // Calculate the minimum amount for the combined collateral and workflow fees
        uint minAmountCollateralAndWorkflow = helperMax(
            minDepositAmountWorkflowFee, minDepositAmountCollateralFee
        );

        // Calculate the overall minimum deposit amount
        _depositAmount = helperMax(
            minAmountCollateralAndWorkflow, minDepositAmountIssuanceFee
        );

        // Ensure the deposit amount is large enough for both fee calculations
        if (_issuanceFee > 0) {
            uint afterIssuanceFee =
                (_depositAmount * (_bps - _issuanceFee)) / _bps;
            if (afterIssuanceFee < minAmountCollateralAndWorkflow) {
                _depositAmount = (minAmountCollateralAndWorkflow * _bps)
                    / (_bps - _issuanceFee) + 1;
            }
        }

        return _depositAmount == 0 ? 1 : _depositAmount;
    }

    function testInternalCalculateSaleReturnWithFee(
        uint _depositAmount,
        uint _collateralFee,
        uint _issuanceFee,
        uint _workflowFee
    ) public {
        // Setup
        uint _bps = bondingCurveFundingManager.call_BPS();
        _collateralFee = bound(_collateralFee, 0, _bps);
        _issuanceFee = bound(_issuanceFee, 0, _bps - 1);
        _workflowFee = bound(_workflowFee, 0, _bps - 1);
        vm.assume(_collateralFee + _workflowFee < _bps);

        _depositAmount = bound(
            _depositAmount,
            helperCalculateMinDepositAmount(
                _collateralFee, _issuanceFee, _workflowFee
            ),
            1e38
        );

        // Set Fee
        if (_collateralFee != 0) {
            feeManager.setDefaultCollateralFee(_collateralFee);
        }
        if (_issuanceFee != 0) {
            feeManager.setDefaultIssuanceFee(_issuanceFee);
        }

        if (_workflowFee != 0) {
            vm.prank(admin_address);
            bondingCurveFundingManager.setSellFee(_workflowFee);
        }

        // Deduct protocol sell fee from issuance
        (
            uint netIssuanceDepositAmount, /* protocolFeeAmount */
            , /* workflowFeeAmount */
        ) = bondingCurveFundingManager.call_calculateNetAndSplitFees(
            _depositAmount, _issuanceFee, 0
        );

        // As the implementation is a mock and the function calculatePurchaseReturn returns the deposit amount
        // in a 1:1 ratio, we use the collateral deposit amount without fee to withdraw the issuance fee

        // Deduct protocol and project sell fee from collateral
        (
            uint netCollateralRedeemAmount, /* protocolFeeAmount */
            , /* workflowFeeAmount */
        ) = bondingCurveFundingManager.call_calculateNetAndSplitFees(
            netIssuanceDepositAmount, _collateralFee, _workflowFee
        );

        // Get return value from function
        uint functionReturn =
            bondingCurveFundingManager.calculateSaleReturn(_depositAmount);

        assertEq(functionReturn, netCollateralRedeemAmount);
    }
    /*    Test calculateSaleReturn function
            └── when function calculateSaleReturn is called
                └── then it should return the same as the internal _calculateSaleReturn function
    */

    function testCalculateSaleReturn_workGivenSameValueReturnedAsInternalFunction(
        uint _depositAmount
    ) public {
        _depositAmount = bound(_depositAmount, 1, 1e38);

        uint internalFunctionReturnValue =
            bondingCurveFundingManager.calculateSaleReturn(_depositAmount);

        uint functionReturnValue =
            bondingCurveFundingManager.calculateSaleReturn(_depositAmount);

        assertEq(internalFunctionReturnValue, functionReturnValue);
    }

    //--------------------------------------------------------------------------
    // Helper functions

    // Modifier to ensure the caller has the admin role
    modifier callerIsOrchestratorAdmin() {
        _authorizer.grantRole(_authorizer.getAdminRole(), admin_address);
        vm.startPrank(admin_address);
        _;
    }

    // Helper function that:
    //      - Mints collateral tokens to a seller and
    //      - Deposits them so they can later be sold.
    //      - Approves the BondingCurve contract to spend the receipt tokens
    // This function assumes that we are using the Mock with a 0% buy fee, so the user will receive as many tokens as they deposit
    function _prepareSellConditions(address seller, uint amount) internal {
        _token.mint(seller, amount);

        vm.startPrank(seller);
        {
            _token.approve(address(bondingCurveFundingManager), amount);
            bondingCurveFundingManager.buy(amount, amount);

            issuanceToken.approve(address(bondingCurveFundingManager), amount);
        }
        vm.stopPrank();
    }
}
