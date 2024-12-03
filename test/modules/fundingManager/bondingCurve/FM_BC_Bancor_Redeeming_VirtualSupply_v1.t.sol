// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// SuT
import {
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1,
    FM_BC_Bancor_Redeeming_VirtualSupply_v1,
    IFundingManager_v1
} from "@fm/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";

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
import {IVirtualIssuanceSupplyBase_v1} from
    "@fm/bondingCurve/interfaces/IVirtualIssuanceSupplyBase_v1.sol";
import {IVirtualCollateralSupplyBase_v1} from
    "@fm/bondingCurve/interfaces/IVirtualCollateralSupplyBase_v1.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {
    IRedeemingBondingCurveBase_v1,
    IRedeemingBondingCurveBase_v1
} from "@fm/bondingCurve/abstracts/RedeemingBondingCurveBase_v1.sol";
// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// Mocks
import {FM_BC_Bancor_Redeeming_VirtualSupplyV1Mock} from
    "test/modules/fundingManager/bondingCurve/utils/mocks/FM_BC_Bancor_Redeeming_VirtualSupplyV1Mock.sol";
import {ERC20PaymentClientBaseV1Mock} from
    "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV1Mock.sol";

import {RedeemingBondingCurveBaseV1Test} from
    "test/modules/fundingManager/bondingCurve/abstracts/RedeemingBondingCurveBase_v1.t.sol";

/*   
    Since the following functions just wrap the Bancor formula contract, their content is assumed to be tested in the original formula tests, not here:

    - _issueTokensFormulaWrapper(uint _depositAmount)
    - _redeemTokensFormulaWrapper(uint _depositAmount)
*/

contract FM_BC_Bancor_Redeeming_VirtualSupplyV1Test is ModuleTest {
    string internal constant NAME = "Bonding Curve Token";
    string internal constant SYMBOL = "BCT";
    uint8 internal constant DECIMALS = 18;
    uint internal constant MAX_SUPPLY = type(uint).max;

    uint internal constant INITIAL_ISSUANCE_SUPPLY = 195_642_169e16;
    uint internal constant INITIAL_COLLATERAL_SUPPLY = 39_097_931e16;
    uint32 internal constant RESERVE_RATIO_FOR_BUYING = 199_800;
    uint32 internal constant RESERVE_RATIO_FOR_SELLING = 199_800;
    uint internal constant BUY_FEE = 0;
    uint internal constant SELL_FEE = 0;
    bool internal constant BUY_IS_OPEN = true;
    bool internal constant SELL_IS_OPEN = true;

    FM_BC_Bancor_Redeeming_VirtualSupplyV1Mock bondingCurveFundingManager;
    address formula;

    ERC20Issuance_v1 issuanceToken;
    ERC20PaymentClientBaseV1Mock _erc20PaymentClientMock;

    address admin_address = address(0xA1BA);
    address non_admin_address = address(0xB0B);

    event Transfer(address indexed from, address indexed to, uint value);

    event TokensBought(
        address indexed receiver,
        uint depositAmount,
        uint receivedAmount,
        address buyer
    );
    event VirtualCollateralAmountAdded(uint amountAdded, uint newSupply);
    event VirtualCollateralAmountSubtracted(
        uint amountSubtracted, uint newSupply
    );
    event VirtualIssuanceAmountSubtracted(
        uint amountSubtracted, uint newSupply
    );
    event VirtualIssuanceAmountAdded(uint amountAdded, uint newSupply);
    event TokensSold(
        address indexed receiver,
        uint depositAmount,
        uint receivedAmount,
        address seller
    );
    event BuyReserveRatioSet(
        uint32 newBuyReserveRatio, uint32 oldBuyReserveRatio
    );
    event SellReserveRatioSet(
        uint32 newSellReserveRatio, uint32 oldSellReserveRatio
    );
    event VirtualIssuanceSupplySet(uint newSupply, uint oldSupply);
    event VirtualCollateralSupplySet(uint newSupply, uint oldSupply);
    event TransferOrchestratorToken(address indexed to, uint amount);
    event OrchestratorTokenSet(address indexed token, uint8 decimals);

    function setUp() public virtual {
        // Deploy contracts
        issuanceToken = new ERC20Issuance_v1(
            NAME, SYMBOL, DECIMALS, MAX_SUPPLY, address(this)
        );

        BancorFormula bancorFormula = new BancorFormula();
        formula = address(bancorFormula);

        IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties memory
            bc_properties;

        bc_properties.formula = formula;
        bc_properties.reserveRatioForBuying = RESERVE_RATIO_FOR_BUYING;
        bc_properties.reserveRatioForSelling = RESERVE_RATIO_FOR_SELLING;
        bc_properties.buyFee = BUY_FEE;
        bc_properties.sellFee = SELL_FEE;
        bc_properties.buyIsOpen = BUY_IS_OPEN;
        bc_properties.sellIsOpen = SELL_IS_OPEN;
        bc_properties.initialIssuanceSupply = INITIAL_ISSUANCE_SUPPLY;
        bc_properties.initialCollateralSupply = INITIAL_COLLATERAL_SUPPLY;

        address impl = address(new FM_BC_Bancor_Redeeming_VirtualSupplyV1Mock());

        bondingCurveFundingManager =
            FM_BC_Bancor_Redeeming_VirtualSupplyV1Mock(Clones.clone(impl));

        _setUpOrchestrator(bondingCurveFundingManager);

        _authorizer.grantRole(_authorizer.getAdminRole(), admin_address);

        vm.expectEmit(true, true, true, true);
        emit OrchestratorTokenSet(address(_token), DECIMALS);

        // Init Module
        bondingCurveFundingManager.init(
            _orchestrator,
            _METADATA,
            abi.encode(
                address(issuanceToken),
                bc_properties,
                _token // fetching from ModuleTest.sol (specifically after the _setUpOrchestrator function call)
            )
        );

        // we grant minting rights to the bonding curve
        issuanceToken.setMinter(address(bondingCurveFundingManager), true);
    }

    function testSupportsInterface() public {
        assertTrue(
            bondingCurveFundingManager.supportsInterface(
                type(IFM_BC_Bancor_Redeeming_VirtualSupply_v1).interfaceId
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
            bondingCurveFundingManager.call_collateralTokenDecimals(),
            _token.decimals(),
            "Collateral token decimals has not been set correctly"
        );
        assertEq(
            address(bondingCurveFundingManager.formula()),
            formula,
            "Formula has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManager.getVirtualIssuanceSupply(),
            INITIAL_ISSUANCE_SUPPLY,
            "Virtual token supply has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManager.getVirtualCollateralSupply(),
            INITIAL_COLLATERAL_SUPPLY,
            "Virtual collateral supply has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManager.call_reserveRatioForBuying(),
            RESERVE_RATIO_FOR_BUYING,
            "Reserve ratio for buying has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManager.call_reserveRatioForSelling(),
            RESERVE_RATIO_FOR_SELLING,
            "Reserve ratio for selling has not been set correctly"
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

    //--------------------------------------------------------------------------
    // Public Functions

    /* Test buy and _virtualSupplyBuyOrder function
        ├── when the deposit amount is 0
        │       └── it should revert 
        └── when the deposit amount is not 0
                ├── when the fee is higher than 0
                │       └── it should substract the fee from the deposit amount
                │               ├── it should pull the buy amount from the caller  
                │               ├── it should take the fee out from the pulled amount 
                │               ├── it should determine the mint amount of tokens to mint from the rest
                │               ├── it should mint the tokens to the receiver 
                │               ├── it should emit an event
                │               ├── it should update the virtual token amount
                │               ├── it should emit an event
                │               ├── it should update the virtual collateral amount
                │               └── it should emit an event            
                └── when the fee is 0
                                ├── it should pull the buy amount from the caller  
                                ├── it should determine the mint amount of tokens to mint 
                                ├── it should mint the tokens to the receiver 
                                ├── it should emit an event
                                ├── it should update the virtual token amount
                                ├── it should emit an event
                                ├── it should update the virtual collateral amount
                                └── it should emit an event     
        
    */
    function testBuyOrder_FailsIfDepositAmountIsZero() public {
        // Test covered in BondingCurveBase_v1
    }

    function testBuyOrder_FailsIfDepositAmountOverflowsVirtualCollateralSupply(
        uint amount
    ) public {
        // Setup
        amount = _bound_for_decimal_conversion(
            amount,
            1,
            1e38,
            bondingCurveFundingManager.call_collateralTokenDecimals(),
            issuanceToken.decimals()
        );
        // see comment in testBuyOrderWithZeroFee
        _token.mint(
            address(bondingCurveFundingManager), (type(uint).max - amount)
        );

        address buyer = makeAddr("buyer");
        _prepareBuyConditions(buyer, amount);

        // we set a virtual collateral supply that will not cover the amount to redeem
        _closeCurveInteractions(); // Buy & sell needs to be closed to set supply
        vm.prank(admin_address);
        bondingCurveFundingManager.setVirtualCollateralSupply(
            type(uint).max - amount + 1
        );
        _openCurveInteractions(); // Open Buy & sell

        vm.startPrank(buyer);
        {
            vm.expectRevert();
            // This results in an overflow of the bonding curve math
            bondingCurveFundingManager.buy(amount, amount);
        }
        vm.stopPrank();
    }

    function testBuyOrder_FailsIfMintAmountOverflowsVirtualIssuanceSupply(
        uint amount
    ) public {
        // Setup
        amount = _bound_for_decimal_conversion(
            amount,
            1,
            1e38,
            bondingCurveFundingManager.call_collateralTokenDecimals(),
            issuanceToken.decimals()
        );
        _token.mint(
            address(bondingCurveFundingManager), (type(uint).max - amount)
        );

        address buyer = makeAddr("buyer");
        _prepareBuyConditions(buyer, amount);

        // we set a virtual collateral supply that will not cover the amount to redeem
        _closeCurveInteractions(); // Buy & sell needs to be closed to set supply
        vm.prank(admin_address);
        bondingCurveFundingManager.setVirtualIssuanceSupply(type(uint).max);
        _openCurveInteractions(); // Open Buy & sell

        vm.startPrank(buyer);
        {
            vm.expectRevert();
            // This results in an overflow of the bonding curve math
            bondingCurveFundingManager.buy(amount, amount);
        }
        vm.stopPrank();
    }

    function testBuyOrderWithZeroFee(uint amount) public {
        // Setup
        // Above an amount of 1e38 the BancorFormula starts to revert.
        amount = _bound_for_decimal_conversion(
            amount,
            1e16,
            1e38,
            bondingCurveFundingManager.call_collateralTokenDecimals(),
            issuanceToken.decimals()
        );

        address buyer = makeAddr("buyer");
        _prepareBuyConditions(buyer, amount);

        // Pre-checks
        uint balanceBefore =
            _token.balanceOf(address(bondingCurveFundingManager));
        assertEq(_token.balanceOf(buyer), amount);
        assertEq(issuanceToken.balanceOf(buyer), 0);

        assertEq(
            bondingCurveFundingManager.call_collateralTokenDecimals(),
            _token.decimals()
        );

        // Use formula to get expected return values
        uint decimalConverted_depositAmount = bondingCurveFundingManager
            .call_convertAmountToRequiredDecimal(amount, _token.decimals(), 18);
        uint formulaReturn = bondingCurveFundingManager.formula()
            .calculatePurchaseReturn(
            bondingCurveFundingManager.call_getFormulaVirtualIssuanceSupply(),
            bondingCurveFundingManager.call_getFormulaVirtualCollateralSupply(),
            bondingCurveFundingManager.call_reserveRatioForBuying(),
            decimalConverted_depositAmount
        );

        // Execution
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true, address(_token));
        emit Transfer(buyer, address(bondingCurveFundingManager), amount);
        vm.expectEmit(true, true, true, true, address(issuanceToken));
        emit Transfer(address(0), buyer, formulaReturn);
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit TokensBought(buyer, amount, formulaReturn, buyer);
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit VirtualIssuanceAmountAdded(
            formulaReturn, (INITIAL_ISSUANCE_SUPPLY + formulaReturn)
        );
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit VirtualCollateralAmountAdded(
            amount, (INITIAL_COLLATERAL_SUPPLY + amount)
        );
        bondingCurveFundingManager.buy(amount, formulaReturn);

        // Post-checks
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManager)),
            (balanceBefore + amount)
        );
        assertEq(_token.balanceOf(buyer), 0);
        assertEq(issuanceToken.balanceOf(buyer), formulaReturn);
    }

    function testBuyOrderWithFee(uint amount, uint fee) public {
        // Setup
        uint _bps = bondingCurveFundingManager.call_BPS();
        fee = bound(fee, 1, (_bps - 1)); // 100% buy fees are not allowed.
        uint minAmount = 1e16;

        // see comment in testBuyOrderWithZeroFee for information on the upper bound
        amount = _bound_for_decimal_conversion(
            amount,
            minAmount,
            1e38,
            bondingCurveFundingManager.call_collateralTokenDecimals(),
            issuanceToken.decimals()
        );
        // see comment in testBuyOrderWithZeroFee for information on the upper bound

        vm.prank(admin_address);
        bondingCurveFundingManager.setBuyFee(fee);

        address buyer = makeAddr("buyer");
        _prepareBuyConditions(buyer, amount);

        // Pre-checks
        uint balanceBefore =
            _token.balanceOf(address(bondingCurveFundingManager));
        assertEq(_token.balanceOf(buyer), amount);
        assertEq(issuanceToken.balanceOf(buyer), 0);

        // We calculate how much the real deposit amount will be after fees
        uint feeAmount = (amount * fee) / bondingCurveFundingManager.call_BPS();
        uint buyAmountMinusFee = amount - feeAmount;

        uint decimalConverted_buyAmountMinusFee = bondingCurveFundingManager
            .call_convertAmountToRequiredDecimal(
            buyAmountMinusFee, _token.decimals(), 18
        );
        // Use formula to get expected return values
        uint formulaReturn = bondingCurveFundingManager.formula()
            .calculatePurchaseReturn(
            bondingCurveFundingManager.call_getFormulaVirtualIssuanceSupply(),
            bondingCurveFundingManager.call_getFormulaVirtualCollateralSupply(),
            bondingCurveFundingManager.call_reserveRatioForBuying(),
            decimalConverted_buyAmountMinusFee
        );

        // Execution
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true, address(_token));
        emit Transfer(buyer, address(bondingCurveFundingManager), amount);
        vm.expectEmit(true, true, true, true, address(issuanceToken));
        emit Transfer(address(0), buyer, formulaReturn);
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit TokensBought(buyer, amount, formulaReturn, buyer);
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit VirtualIssuanceAmountAdded(
            formulaReturn, (INITIAL_ISSUANCE_SUPPLY + formulaReturn)
        );
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit VirtualCollateralAmountAdded(
            buyAmountMinusFee, (INITIAL_COLLATERAL_SUPPLY + buyAmountMinusFee)
        );
        bondingCurveFundingManager.buy(amount, formulaReturn);

        // Post-checks
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManager)),
            (balanceBefore + amount)
        );
        assertEq(_token.balanceOf(buyer), 0);
        assertEq(issuanceToken.balanceOf(buyer), formulaReturn);
    }

    // test buyFor function
    //  - Both modifiers have been tested in the upstream tests
    //  - Buy order branches are tested in sell tests
    //  - The goal of this test is just to verify that the tokens get sent to a different receiver

    function testBuyOrderFor(address to, uint amount) public {
        // Setup

        address buyer = makeAddr("buyer");
        vm.assume(
            to != address(0) && to != address(this) && to != buyer
                && to != address(bondingCurveFundingManager)
        );

        // see comment in testBuyOrderWithZeroFee for information on the upper bound
        amount = _bound_for_decimal_conversion(
            amount,
            1e16,
            1e38,
            bondingCurveFundingManager.call_collateralTokenDecimals(),
            issuanceToken.decimals()
        );

        assertNotEq(to, buyer);

        _prepareBuyConditions(buyer, amount);

        // Pre-checks
        uint balanceBefore =
            _token.balanceOf(address(bondingCurveFundingManager));
        assertEq(_token.balanceOf(buyer), amount);
        assertEq(issuanceToken.balanceOf(buyer), 0);

        // Use formula to get expected return values.
        // Note that since we are calling the formula directly, we need to normalize the buy amount to 18 decimals (since that is what the curve uses internally)

        uint decimalConverted_depositAmount = bondingCurveFundingManager
            .call_convertAmountToRequiredDecimal(amount, _token.decimals(), 18);
        // Use formula to get expected return values
        uint formulaReturn = bondingCurveFundingManager.formula()
            .calculatePurchaseReturn(
            bondingCurveFundingManager.call_getFormulaVirtualIssuanceSupply(),
            bondingCurveFundingManager.call_getFormulaVirtualCollateralSupply(),
            bondingCurveFundingManager.call_reserveRatioForBuying(),
            decimalConverted_depositAmount
        );
        // MinAmountOut cannot be 0. Set to 1 accordingly
        formulaReturn = formulaReturn == 0 ? 1 : formulaReturn;

        // Execution
        vm.prank(buyer);
        bondingCurveFundingManager.buyFor(to, amount, formulaReturn);

        // Post-checks
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManager)),
            (balanceBefore + amount)
        );
        assertEq(_token.balanceOf(buyer), 0);
        assertEq(issuanceToken.balanceOf(buyer), 0);
        assertEq(issuanceToken.balanceOf(to), formulaReturn);
    }

    /* Test sell and _virtualSupplySellOrder function
        ├── when the sell amount is 0
        │       └── it should revert 
        └── when the sell amount is not 0
                ├── when the fee is higher than 0
                │               ├── it should take the sell amount from the caller
                │               ├── it should determine the redeem amount of the sent tokens 
                │               ├── it should substract the fee from the redeem amount
                │               ├── When there IS NOT enough collateral in the contract to cover the redeem amount
                │               │        └── it should revert
                │               └── When there IS enough collateral in the contract to cover the redeem amount
                │                       ├── When the amount of redeemed tokens exceeds the virtual issuance supply
                │                       │       └── it should revert
                │                       └── When the amount of redeemed tokens does not exceed the virtual issuance supply
                │                               ├── it should send the rest to the receiver    
                │                               ├── it should emit an event
                │                               ├── it should update the virtual token amount
                │                               ├── it should emit an event
                │                               ├── it should update the virtual collateral amount
                │                               └── it should emit an event
                └── when the fee is 0
                                ├── it should take the sell amount from the caller
                                ├── it should determine the redeem amount of the sent tokens 
                                ├── When there IS NOT enough collateral in the contract to cover the redeem amount
                                │        └── it should revert
                                └── When there IS enough collateral in the contract to cover the redeem amount
                                        ├── When the amount of redeemed tokens exceeds the virtual issuance supply
                                        │       └── it should revert
                                        └── When the amount of redeemed tokens does not exceed the virtual issuance supply
                                                ├── it should send the rest to the receiver    
                                                ├── it should emit an event
                                                ├── it should update the virtual token amount
                                                ├── it should emit an event
                                                ├── it should update the virtual collateral amount
                                                └── it should emit an event
    */

    function testSellOrder_FailsIfDepositAmountIsZero() public {
        // Test covered in RedeemingBondingCurveBase_v1
    }

    function testSellOrder_FailsIfBurnAmountExceedsVirtualIssuanceSupply(
        uint amount
    ) public {
        // Setup

        // We set a minimum high enough to discard most inputs that wouldn't mint at least 2 tokens (so the supply can be set to 1 below)
        // see comment in testBuyOrderWithZeroFee for information on the upper bound
        amount = _bound_for_decimal_conversion(
            amount,
            1e4,
            1e36,
            bondingCurveFundingManager.call_collateralTokenDecimals(),
            issuanceToken.decimals()
        );

        _token.mint(
            address(bondingCurveFundingManager), (type(uint).max - amount)
        );

        address seller = makeAddr("seller");
        _prepareSellConditions(seller, amount);

        uint userSellAmount = issuanceToken.balanceOf(seller);
        vm.assume(userSellAmount > 0); // we discard buy-ins so small they wouldn't cause underflow

        _closeCurveInteractions(); // Buy & sell needs to be closed to set supply
        // we set a virtual collateral supply that will not cover the amount to redeem
        vm.prank(admin_address);
        bondingCurveFundingManager.setVirtualIssuanceSupply(userSellAmount - 1);
        _openCurveInteractions(); // Open Buy & sell

        vm.startPrank(seller);
        {
            vm.expectRevert(); // The formula reverts
            bondingCurveFundingManager.sell(userSellAmount, userSellAmount);
        }
        vm.stopPrank();
    }

    function testSellOrder_FailsIfNotEnoughCollateralInContract(uint amount)
        public
    {
        // Setup

        // see comment in testBuyOrderWithZeroFee for information on the upper bound
        amount = _bound_for_decimal_conversion(
            amount,
            1e16,
            1e36,
            bondingCurveFundingManager.call_collateralTokenDecimals(),
            issuanceToken.decimals()
        );

        address seller = makeAddr("seller");
        _prepareSellConditions(seller, amount);

        // we simulate the fundingManager spending some funds. It can't cover full redemption anymore.
        _token.burn(address(bondingCurveFundingManager), 1);

        vm.startPrank(seller);
        {
            vm.expectRevert(); // The formula reverts
            bondingCurveFundingManager.sell(amount, amount);
        }
        vm.stopPrank();
    }

    function testSellOrderWithZeroFee(uint amountIn) public {
        // Setup

        // We set a minimum high enough to discard most inputs that wouldn't mint even 1 token
        amountIn = _bound_for_decimal_conversion(
            amountIn,
            100,
            1e36,
            bondingCurveFundingManager.call_collateralTokenDecimals(),
            issuanceToken.decimals()
        );
        // see comment in testBuyOrderWithZeroFee for information on the upper bound

        _token.mint(
            address(bondingCurveFundingManager), (type(uint).max - amountIn)
        ); // We mint all the other tokens to the fundingManager to make sure we'll have enough balance to pay out

        address seller = makeAddr("seller");

        uint userSellAmount = _prepareSellConditions(seller, amountIn);
        vm.assume(userSellAmount > 0); // we ensure we are discarding buy-ins so small they wouldn't cause minting

        // Set virtual supply to some number above the sell amount
        // Set virtual collateral to some number
        uint newVirtualIssuanceSupply = userSellAmount * 2;
        uint newVirtualCollateral = amountIn * 2;
        _closeCurveInteractions(); // Buy & sell needs to be closed to set supply
        vm.startPrank(admin_address);
        {
            bondingCurveFundingManager.setVirtualIssuanceSupply(
                newVirtualIssuanceSupply
            );
            bondingCurveFundingManager.setVirtualCollateralSupply(
                newVirtualCollateral
            );
        }
        vm.stopPrank();
        _openCurveInteractions(); // Open Buy & sell

        uint decimalConverted_userSellAmount = bondingCurveFundingManager
            .call_convertAmountToRequiredDecimal(
            userSellAmount, issuanceToken.decimals(), 18
        );
        // Use formula to get expected return values
        uint formulaReturn = bondingCurveFundingManager.formula()
            .calculateSaleReturn(
            bondingCurveFundingManager.call_getFormulaVirtualIssuanceSupply(),
            bondingCurveFundingManager.call_getFormulaVirtualCollateralSupply(),
            bondingCurveFundingManager.call_reserveRatioForSelling(),
            decimalConverted_userSellAmount
        );

        // normalize the formulaReturn. This is the amount in the context of the collateral token
        uint normalized_formulaReturn = bondingCurveFundingManager
            .call_convertAmountToRequiredDecimal(
            formulaReturn, 18, _token.decimals()
        );

        // Perform the sell
        vm.startPrank(seller);
        {
            vm.expectEmit(true, true, true, true, address(_token));
            emit Transfer(
                address(bondingCurveFundingManager),
                address(seller),
                normalized_formulaReturn
            );
            vm.expectEmit(
                true, true, true, true, address(bondingCurveFundingManager)
            );
            emit TokensSold(
                seller, userSellAmount, normalized_formulaReturn, seller
            );
            vm.expectEmit(
                true, true, true, true, address(bondingCurveFundingManager)
            );
            emit VirtualIssuanceAmountSubtracted(
                userSellAmount, newVirtualIssuanceSupply - userSellAmount
            );
            vm.expectEmit(
                true, true, true, true, address(bondingCurveFundingManager)
            );
            emit VirtualCollateralAmountSubtracted(
                normalized_formulaReturn,
                newVirtualCollateral - normalized_formulaReturn
            );
            bondingCurveFundingManager.sell(
                userSellAmount, normalized_formulaReturn
            );
        }
        vm.stopPrank();

        // Check real-world token/collateral balances
        assertEq(issuanceToken.balanceOf(seller), 0);
        assertEq(_token.balanceOf(seller), normalized_formulaReturn);
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManager)),
            (type(uint).max - normalized_formulaReturn)
        );

        // Check virtual token/collateral balances
        assertEq(
            bondingCurveFundingManager.getVirtualIssuanceSupply(),
            newVirtualIssuanceSupply - userSellAmount
        );
        assertEq(
            bondingCurveFundingManager.getVirtualCollateralSupply(),
            newVirtualCollateral - normalized_formulaReturn
        );
    }

    function testSellOrderWithFee(uint amountIn, uint fee) public {
        // Same as above, but substracting fees when checking actual amounts

        // Setup
        uint _bps = bondingCurveFundingManager.call_BPS();
        fee = bound(fee, 1, _bps - 1);

        // We set a minimum high enough to discard most inputs that wouldn't mint even 1 token
        amountIn = _bound_for_decimal_conversion(
            amountIn,
            1e16,
            1e36,
            bondingCurveFundingManager.call_collateralTokenDecimals(),
            issuanceToken.decimals()
        );
        // see comment in testBuyOrderWithZeroFee for information on the upper bound
        _token.mint(
            address(bondingCurveFundingManager), (type(uint).max - amountIn)
        ); // We mint all the other tokens to the fundingManager to make sure we'll have enough balance to pay out

        address seller = makeAddr("seller");
        uint userSellAmount = _prepareSellConditions(seller, amountIn);
        vm.assume(userSellAmount > 0); // we discard buy-ins so small they wouldn't cause underflow

        // Get virtual supplies before sell
        uint newVirtualIssuanceSupply =
            bondingCurveFundingManager.getVirtualIssuanceSupply();
        uint newVirtualCollateral =
            bondingCurveFundingManager.getVirtualCollateralSupply();
        // setSellFee
        vm.prank(admin_address);
        bondingCurveFundingManager.setSellFee(fee);

        // Use formula to get expected return values
        uint normalized_formulaReturn = bondingCurveFundingManager.formula()
            .calculateSaleReturn(
            bondingCurveFundingManager.call_convertAmountToRequiredDecimal(
                bondingCurveFundingManager.call_getFormulaVirtualIssuanceSupply(
                ),
                18,
                issuanceToken.decimals()
            ),
            bondingCurveFundingManager.call_convertAmountToRequiredDecimal(
                bondingCurveFundingManager
                    .call_getFormulaVirtualCollateralSupply(),
                18,
                _token.decimals()
            ),
            bondingCurveFundingManager.call_reserveRatioForSelling(),
            userSellAmount
        );

        // We calculate how much if the initial deposit we should get back based on the fee
        uint feeAmount = (normalized_formulaReturn * fee) / _bps;
        uint sellAmountMinusFee = normalized_formulaReturn - feeAmount;

        // Perform the sell
        vm.startPrank(seller);
        {
            vm.expectEmit(true, true, true, true, address(_token));
            emit Transfer(
                address(bondingCurveFundingManager),
                address(seller),
                sellAmountMinusFee
            );
            vm.expectEmit(
                true, true, true, true, address(bondingCurveFundingManager)
            );
            emit TokensSold(seller, userSellAmount, sellAmountMinusFee, seller);
            vm.expectEmit(
                true, true, true, true, address(bondingCurveFundingManager)
            );
            emit VirtualIssuanceAmountSubtracted(
                userSellAmount, newVirtualIssuanceSupply - userSellAmount
            );
            vm.expectEmit(
                true, true, true, true, address(bondingCurveFundingManager)
            );
            emit VirtualCollateralAmountSubtracted(
                normalized_formulaReturn,
                newVirtualCollateral - normalized_formulaReturn
            );
            bondingCurveFundingManager.sell(userSellAmount, sellAmountMinusFee);
        }
        vm.stopPrank();

        // Check real-world token/collateral balances
        assertEq(issuanceToken.balanceOf(seller), 0);
        assertEq(_token.balanceOf(seller), sellAmountMinusFee);
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManager)),
            (type(uint).max - sellAmountMinusFee)
        );

        // Check virtual token/collateral balances
        assertEq(
            bondingCurveFundingManager.getVirtualIssuanceSupply(),
            newVirtualIssuanceSupply - userSellAmount
        );
        assertEq(
            bondingCurveFundingManager.getVirtualCollateralSupply(),
            newVirtualCollateral - normalized_formulaReturn
        );
    }

    // test sellTo function
    //  - Both modifiers have been tested in the upstream tests
    //  - Sell order branches are tested in sell tests
    //  - The goal of this test is just to verify that the tokens get sent to a different receiver

    function testSellOrderFor(uint amountIn, address to) public {
        // Setup
        address seller = makeAddr("seller");
        vm.assume(
            to != address(0) && to != seller && to != address(this)
                && to != address(bondingCurveFundingManager)
        );

        // We set a minimum high enough to discard most inputs that wouldn't mint even 1 token
        amountIn = _bound_for_decimal_conversion(
            amountIn,
            100,
            1e36,
            bondingCurveFundingManager.call_collateralTokenDecimals(),
            issuanceToken.decimals()
        );
        // see comment in testBuyOrderWithZeroFee for information on the upper bound

        _token.mint(
            address(bondingCurveFundingManager), (type(uint).max - amountIn)
        ); // We mint all the other tokens to the fundingManager to make sure we'll have enough balance to pay out

        uint userSellAmount = _prepareSellConditions(seller, amountIn);
        vm.assume(userSellAmount > 0); // we discard buy-ins so small they wouldn't cause minting
        // Set virtual supply to some number above the sell amount
        // Set virtual collateral to some number
        uint newVirtualIssuanceSupply = userSellAmount * 2;
        uint newVirtualCollateral = amountIn * 2;
        _closeCurveInteractions(); // Buy & sell needs to be closed to set supply
        vm.startPrank(admin_address);
        {
            bondingCurveFundingManager.setVirtualIssuanceSupply(
                newVirtualIssuanceSupply
            );
            bondingCurveFundingManager.setVirtualCollateralSupply(
                newVirtualCollateral
            );
        }
        vm.stopPrank();
        _openCurveInteractions(); // Open Buy & sell

        uint decimalConverted_userSellAmount = bondingCurveFundingManager
            .call_convertAmountToRequiredDecimal(
            userSellAmount, issuanceToken.decimals(), 18
        );

        // Use formula to get expected return values
        uint formulaReturn = bondingCurveFundingManager.formula()
            .calculateSaleReturn(
            bondingCurveFundingManager.call_getFormulaVirtualIssuanceSupply(),
            bondingCurveFundingManager.call_getFormulaVirtualCollateralSupply(),
            bondingCurveFundingManager.call_reserveRatioForSelling(),
            decimalConverted_userSellAmount
        );

        // normalize the formulaReturn. This is the amount in the context of the collateral token
        uint normalized_formulaReturn = bondingCurveFundingManager
            .call_convertAmountToRequiredDecimal(
            formulaReturn, 18, _token.decimals()
        );

        // Perform the sell
        vm.startPrank(seller);
        {
            bondingCurveFundingManager.sellTo(
                to, userSellAmount, normalized_formulaReturn
            );
        }
        vm.stopPrank();

        // Check real-world token/collateral balances
        assertEq(issuanceToken.balanceOf(seller), 0);
        assertEq(_token.balanceOf(seller), 0);
        assertEq(_token.balanceOf(to), normalized_formulaReturn);
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManager)),
            (type(uint).max - normalized_formulaReturn)
        );

        // Check virtual token/collateral balances
        assertEq(
            bondingCurveFundingManager.getVirtualIssuanceSupply(),
            newVirtualIssuanceSupply - userSellAmount
        );
        assertEq(
            bondingCurveFundingManager.getVirtualCollateralSupply(),
            newVirtualCollateral - normalized_formulaReturn
        );
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /*
     Test token() getter
    */
    function testCollateralTokenGetter() public {
        address orchestratorToken =
            address(_orchestrator.fundingManager().token());
        assertEq(
            address(bondingCurveFundingManager.token()),
            orchestratorToken,
            "Token getter returns wrong address"
        );
    }

    /*
        Test getReserveRatioForBuying()
    */
    function testGetReserveRatioForBuying() public {
        assertEq(
            bondingCurveFundingManager.getReserveRatioForBuying(),
            bondingCurveFundingManager.call_reserveRatioForBuying()
        );
    }
    /*
        Test getReserveRatioForSelling()
    */

    function testGetReserveRatioForSelling() public {
        assertEq(
            bondingCurveFundingManager.getReserveRatioForSelling(),
            bondingCurveFundingManager.call_reserveRatioForSelling()
        );
    }

    /* Test getStaticPriceForBuying()
        ├── When calling for buying without fuzzing
            └── it should update return value after buying
    */

    function testStaticPriceForBuyingNonFuzzing() public {
        uint amountIn = 100e16;
        uint minAmountOut =
            bondingCurveFundingManager.calculatePurchaseReturn(amountIn);
        address buyer = makeAddr("buyer");
        _prepareBuyConditions(buyer, amountIn);

        // Get virtual supplies before buy
        uint _virtualIssuanceSupplyBeforeBuy =
            bondingCurveFundingManager.getVirtualIssuanceSupply();
        uint _virtualCollateralSupplyBeforeBuy =
            bondingCurveFundingManager.getVirtualCollateralSupply();

        // Calculate static price before buy
        uint staticPriceBeforeBuy =
            bondingCurveFundingManager.getStaticPriceForBuying();

        // Buy tokens
        vm.prank(buyer);
        bondingCurveFundingManager.buy(amountIn, minAmountOut);

        // Get virtual supplies after buy
        uint _virtualIssuanceSupplyAfterBuy =
            bondingCurveFundingManager.getVirtualIssuanceSupply();
        uint _virtualCollateralSupplyAfterBuy =
            bondingCurveFundingManager.getVirtualCollateralSupply();
        // Calculate static price after buy
        uint staticPriceAfterBuy =
            bondingCurveFundingManager.getStaticPriceForBuying();

        // Collateral has been added to the supply
        assertGt(
            _virtualCollateralSupplyAfterBuy, _virtualCollateralSupplyBeforeBuy
        );
        // Issuance has been added to the supply
        assertGt(
            _virtualIssuanceSupplyAfterBuy, _virtualIssuanceSupplyBeforeBuy
        );
        // Static price has increased after buy
        assertGt(staticPriceAfterBuy, staticPriceBeforeBuy);

        // Price has risen less than 1 * PPM
        assertApproxEqAbs(
            staticPriceAfterBuy,
            staticPriceBeforeBuy,
            1 * bondingCurveFundingManager.call_PPM()
        );
    }

    /* Test getStaticPriceForSelling() 
            ├── When calling for selling without fuzzing
                  └── it should update return value after selling
    */
    function testStaticPriceWithSellReserveRatioNonFuzzing() public {
        uint amountIn = 1000;
        address seller = makeAddr("seller");
        uint availableForSale = _prepareSellConditions(seller, amountIn); // Multiply amount to ensure that user has enough tokens, because return amount when buying less than amount
        // Set virtual supply to some number above _sellAmount
        // Set virtual collateral to some number
        uint newVirtualIssuanceSupply = availableForSale * 2;
        uint newVirtualCollateral = amountIn * 2;

        _token.mint(
            address(bondingCurveFundingManager), (type(uint).max - amountIn)
        ); // We mint all the other tokens to the fundingManager to make sure we'll have enough balance to pay out

        // Set virtual supplies
        _closeCurveInteractions(); // Buy & sell needs to be closed to set supply
        vm.startPrank(admin_address);
        {
            bondingCurveFundingManager.setVirtualIssuanceSupply(
                newVirtualIssuanceSupply
            );
            bondingCurveFundingManager.setVirtualCollateralSupply(
                newVirtualCollateral
            );
        }
        vm.stopPrank();
        _openCurveInteractions(); // Open Buy & sell

        // Calculate min amount out for selling
        uint minAmountOut =
            bondingCurveFundingManager.calculateSaleReturn(availableForSale);

        // Get virtual supplies before selling
        uint _virtualIssuanceSupplyBeforeSell =
            bondingCurveFundingManager.getVirtualIssuanceSupply();
        uint _virtualCollateralSupplyBeforeSell =
            bondingCurveFundingManager.getVirtualCollateralSupply();
        bondingCurveFundingManager.call_reserveRatioForSelling();

        // Calculate static price before selling
        uint staticPriceBeforeSell =
            bondingCurveFundingManager.getStaticPriceForSelling();

        // Sell tokens
        vm.prank(seller);
        bondingCurveFundingManager.sell(availableForSale, minAmountOut);

        // Get virtual supplies after selling
        uint _virtualIssuanceSupplyAfterSell =
            bondingCurveFundingManager.getVirtualIssuanceSupply();
        uint _virtualCollateralSupplyAfterSell =
            bondingCurveFundingManager.getVirtualCollateralSupply();

        // Calculate static price after selling
        uint staticPriceAfterSell =
            bondingCurveFundingManager.getStaticPriceForSelling();

        // Assert that supply has changed
        assertLt(
            _virtualIssuanceSupplyAfterSell, _virtualIssuanceSupplyBeforeSell
        );
        assertLt(
            _virtualCollateralSupplyAfterSell,
            _virtualCollateralSupplyBeforeSell
        );

        // Static price has decreased after sell
        assertLt(staticPriceAfterSell, staticPriceBeforeSell);
    }

    /* Test getVirtualCollateralSupply() */

    function testGetVirtualCollateralSupply(uint _supply) public {
        vm.assume(_supply > 0);

        _closeCurveInteractions(); // Buy & sell needs to be closed to set supply
        vm.prank(admin_address);
        bondingCurveFundingManager.setVirtualCollateralSupply(_supply);
        _openCurveInteractions(); // Open Buy & sell

        assertEq(
            _supply, bondingCurveFundingManager.getVirtualCollateralSupply()
        );
    }

    /* Test getVirtualIssuanceSupply() */

    function testGetVirtualIssuanceSupply(uint _supply) public {
        vm.assume(_supply > 10);

        _closeCurveInteractions(); // Buy & sell needs to be closed to set supply
        vm.prank(admin_address);
        bondingCurveFundingManager.setVirtualIssuanceSupply(_supply);
        _openCurveInteractions(); // Open Buy & sell

        assertEq(_supply, bondingCurveFundingManager.getVirtualIssuanceSupply());
    }

    //--------------------------------------------------------------------------
    // OnlyOrchestrator Functions

    /* Test setVirtualIssuanceSupply and _setVirtualIssuanceSupply function
        ├── given caller is not the Orchestrator_v1 admin
        │   └── when the function setVirtualIssuanceSupply() is called
        │       └── then it should revert (test modifier is in place. Modifier test itself is tested in base Module tests)
        └── given the caller is the Orchestrator_v1 admin
            ├── and the buy | sell curve are still open (modifier test)
            │   └── when the function_setVirtualIssuanceSupply() is called
            │       └── then it should revert
            ├── and the new token supply is zero
            │   └── when the function_setVirtualIssuanceSupply() is called
            │       └── then it should revert
            ├── and the new token supply is zero after decimal conversion
            │   └── when the function_setVirtualIssuanceSupply() is called
            │       └── then it should revert
            └── and the new token supply is > zero
                └── when the function setVirtualIssuanceSupply() is called
                    └── then it should set the new token supply
                        └── and it should emit an event
    */

    function testSetVirtualIssuanceSupply_WorksGivenOnlyOrchestratorAdminModifierInPlace(
        uint _newSupply
    ) public {
        vm.assume(_newSupply != 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                _authorizer.getAdminRole(),
                non_admin_address
            )
        );
        vm.prank(non_admin_address);
        bondingCurveFundingManager.setVirtualIssuanceSupply(_newSupply);
    }

    function testSetVirtualIssuanceSupply_WorksGivenOnlyWhenCurveInteractionsAreClosedModifierInPosition(
        uint _newSupply
    ) public callerIsOrchestratorAdmin {
        vm.assume(_newSupply != 0);
        vm.expectRevert(
            IFM_BC_Bancor_Redeeming_VirtualSupply_v1
                .Module__FM_BC_Bancor_Redeeming_VirtualSupply__CurveInteractionsMustBeClosed
                .selector
        );
        bondingCurveFundingManager.setVirtualIssuanceSupply(_newSupply);
    }

    function testInternalSetVirtualIssuanceSupply_RevertGivenIssuanceSupplyIsZero(
    ) public {
        uint _newSupply = 0;

        _closeCurveInteractions(); // Buy & sell needs to be closed to set supply
        vm.expectRevert(
            IVirtualIssuanceSupplyBase_v1
                .Module__VirtualIssuanceSupplyBase__VirtualSupplyCannotBeZero
                .selector
        );
        bondingCurveFundingManager.call_setVirtualIssuanceSupply(_newSupply);
    }

    function testInternalSetVirtualIssuanceSupply_RevertGivenAfterDecimalConversionIssuanceSupplyIsZero(
        uint _newSupply
    ) public {
        // vm.assume(_newSupply < 10 ** (DECIMALS - 18));
        _newSupply = bound(_newSupply, 0, 10 ** (DECIMALS - 18) - 1);
        _closeCurveInteractions(); // Buy & sell needs to be closed to set supply

        vm.expectRevert(
            IVirtualIssuanceSupplyBase_v1
                .Module__VirtualIssuanceSupplyBase__VirtualSupplyCannotBeZero
                .selector
        );
        bondingCurveFundingManager.call_setVirtualIssuanceSupply(_newSupply);
    }

    function testInternalSetVirtualIssuanceSupply_WorksGivenIssuanceSupplyBiggerThanZero(
        uint _newSupply
    ) public {
        vm.assume(_newSupply > 10);
        _closeCurveInteractions(); // Buy & sell needs to be closed to set supply
        vm.expectEmit(
            true, true, false, false, address(bondingCurveFundingManager)
        );
        emit VirtualIssuanceSupplySet(_newSupply, INITIAL_ISSUANCE_SUPPLY);
        bondingCurveFundingManager.call_setVirtualIssuanceSupply(_newSupply);
        assertEq(
            bondingCurveFundingManager.getVirtualIssuanceSupply(), _newSupply
        );
    }

    /* Test setVirtualCollateralSupply and _setVirtualCollateralSupply function
        ├── given caller is not the Orchestrator_v1 admin
        │   └── when the function setVirtualCollateralSupply() is called
        │       └── then it should revert (test modifier is in place. Modifier test itself is tested in base Module tests)
        └── given the caller is the Orchestrator_v1 admin
            ├── and the buy | sell curve are still open (modifier test)
            │   └── when the setVirtualCollateralSupply() is called
            │       └── then it should revert
            ├── and the new token supply is zero
            │   └── when the setVirtualCollateralSupply() is called
            │       └── then it should revert
            └── and the new token supply is > zero
                └── when the function setVirtualCollateralSupply() is called
                    └── then it should set the new token supply
                        └── and it should emit an event
    */

    function testSetVirtualCollateralSupply_WorksGivenOnlyOrchestratorAdminModifierInPlace(
        uint _newSupply
    ) public {
        vm.assume(_newSupply != 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                _authorizer.getAdminRole(),
                non_admin_address
            )
        );
        vm.prank(non_admin_address);
        bondingCurveFundingManager.setVirtualCollateralSupply(_newSupply);
    }

    function testSetVirtualCollateralSupply_WorksGivenOnlyWhenCurveInteractionsAreClosedModifierInPosition(
        uint _newSupply
    ) public callerIsOrchestratorAdmin {
        vm.assume(_newSupply != 0);
        vm.expectRevert(
            IFM_BC_Bancor_Redeeming_VirtualSupply_v1
                .Module__FM_BC_Bancor_Redeeming_VirtualSupply__CurveInteractionsMustBeClosed
                .selector
        );
        bondingCurveFundingManager.setVirtualCollateralSupply(_newSupply);
    }

    function testSetVirtualCollateralSupply_FailsIfZero()
        public
        callerIsOrchestratorAdmin
    {
        uint _newSupply = 0;

        _closeCurveInteractions(); // Buy & sell needs to be closed to set supply
        vm.expectRevert(
            IVirtualCollateralSupplyBase_v1
                .Module__VirtualCollateralSupplyBase__VirtualSupplyCannotBeZero
                .selector
        );
        bondingCurveFundingManager.setVirtualCollateralSupply(_newSupply);
    }

    function testSetVirtualCollateralSupply(uint _newSupply)
        public
        callerIsOrchestratorAdmin
    {
        vm.assume(_newSupply != 0);

        _closeCurveInteractions(); // Buy & sell needs to be closed to set supply
        vm.expectEmit(
            true, true, false, false, address(bondingCurveFundingManager)
        );
        emit VirtualCollateralSupplySet(_newSupply, INITIAL_COLLATERAL_SUPPLY);
        bondingCurveFundingManager.setVirtualCollateralSupply(_newSupply);
        assertEq(
            bondingCurveFundingManager.getVirtualCollateralSupply(), _newSupply
        );
    }

    /* Test setReserveRatioForBuying and _setReserveRatioForBuying function
        ├── when caller is not the Orchestrator_v1 admin
        │       └── it should revert (tested in base Module tests)
        └── when caller is the Orchestrator_v1 admin
                ├── when buy | sell is still open (modifier test)
                │       └── it should revert
                ├── when reserve ratio is  0% 
                │       └── it should revert
                ├── when reserve ratio is below 100%
                │       ├── it should set the new ratio
                │       └── it should emit an event
                ├── when reserve ratio is  100% 
                │       ├── it should set the new ratio 
                │       └── it should emit an event
                └──  when reserve ratio is over 100% 
                        └── it should revert
    */

    function testSetReserveRatioForBuying_WorksGivenOnlyWhenCurveInteractionsAreClosedModifierInPosition(
    ) public {
        vm.expectRevert(
            IFM_BC_Bancor_Redeeming_VirtualSupply_v1
                .Module__FM_BC_Bancor_Redeeming_VirtualSupply__CurveInteractionsMustBeClosed
                .selector
        );
        bondingCurveFundingManager.setReserveRatioForBuying(10);
    }

    function testSetReserveRatioForBuying_failsIfRatioIsZero()
        public
        callerIsOrchestratorAdmin
    {
        _closeCurveInteractions(); // Close interactions to enable setting of ratio
        vm.expectRevert(
            IFM_BC_Bancor_Redeeming_VirtualSupply_v1
                .Module__FM_BC_Bancor_Redeeming_VirtualSupply__InvalidReserveRatio
                .selector
        );
        bondingCurveFundingManager.setReserveRatioForBuying(0);
    }

    function testSetReserveRatioForBuying_failsIfRatioIsAboveMax(
        uint32 _newRatio
    ) public callerIsOrchestratorAdmin {
        vm.assume(_newRatio > bondingCurveFundingManager.call_PPM());
        _closeCurveInteractions(); // Close interactions to enable setting of ratio
        vm.expectRevert(
            IFM_BC_Bancor_Redeeming_VirtualSupply_v1
                .Module__FM_BC_Bancor_Redeeming_VirtualSupply__InvalidReserveRatio
                .selector
        );
        bondingCurveFundingManager.setReserveRatioForBuying(_newRatio);
    }

    function testSetReserveRatioForBuying(uint32 _newRatio)
        public
        callerIsOrchestratorAdmin
    {
        // manual bound for uint32
        _newRatio = (_newRatio % bondingCurveFundingManager.call_PPM()) + 1; // reserve ratio of 0% isn't allowed, 100% is (although it isn't really a curve anymore)
        _closeCurveInteractions(); // Close interactions to enable setting of ratio
        vm.expectEmit(
            true, true, false, false, address(bondingCurveFundingManager)
        );
        emit BuyReserveRatioSet(_newRatio, RESERVE_RATIO_FOR_BUYING);
        bondingCurveFundingManager.setReserveRatioForBuying(_newRatio);
        assertEq(
            bondingCurveFundingManager.call_reserveRatioForBuying(), _newRatio
        );
    }

    // Additional test:
    // Test reserve ratio changes

    /* Test setReserveRatioForSelling and _setReserveRatioForSelling function
        ├── when caller is not the Orchestrator_v1 admin
        │       └── it should revert (tested in base Module tests)
        └── when caller is the Orchestrator_v1 admin
                ├── when buy | sell is still open (modifier test)
                │       └── it should revert
                ├── when reserve ratio is  0% 
                │       └── it should revert
                ├── when reserve ratio is below 100%
                │       ├── it should set the new ratio
                │       └── it should emit an event
                ├── when reserve ratio is  100% 
                │       ├── it should set the new ratio 
                │       └── it should emit an event
                └──  when reserve ratio is over 100% 
                        └── it should revert
    */

    function testSetReserveRatioForSelling_WorksGivenOnlyWhenCurveInteractionsAreClosedModifierInPosition(
    ) public {
        vm.expectRevert(
            IFM_BC_Bancor_Redeeming_VirtualSupply_v1
                .Module__FM_BC_Bancor_Redeeming_VirtualSupply__CurveInteractionsMustBeClosed
                .selector
        );
        bondingCurveFundingManager.setReserveRatioForSelling(10);
    }

    function testSetReserveRatioForSelling_failsIfRatioIsZero()
        public
        callerIsOrchestratorAdmin
    {
        _closeCurveInteractions(); // Close interactions to enable setting of ratio
        vm.expectRevert(
            IFM_BC_Bancor_Redeeming_VirtualSupply_v1
                .Module__FM_BC_Bancor_Redeeming_VirtualSupply__InvalidReserveRatio
                .selector
        );
        bondingCurveFundingManager.setReserveRatioForSelling(0);
    }

    function testSetReserveRatioForSelling_failsIfRatioIsAboveMax(
        uint32 _newRatio
    ) public callerIsOrchestratorAdmin {
        vm.assume(_newRatio > bondingCurveFundingManager.call_PPM());
        _closeCurveInteractions(); // Close interactions to enable setting of ratio
        vm.expectRevert(
            IFM_BC_Bancor_Redeeming_VirtualSupply_v1
                .Module__FM_BC_Bancor_Redeeming_VirtualSupply__InvalidReserveRatio
                .selector
        );
        bondingCurveFundingManager.setReserveRatioForSelling(_newRatio);
    }

    function testSetReserveRatioForSelling(uint32 _newRatio)
        public
        callerIsOrchestratorAdmin
    {
        _closeCurveInteractions(); // Close interactions to enable setting of ratio
        // manual bound for uint32
        _newRatio = (_newRatio % bondingCurveFundingManager.call_PPM()) + 1; // reserve ratio of 0% isn't allowed, 100% is (although it isn't really a curve anymore)
        vm.expectEmit(
            true, true, false, false, address(bondingCurveFundingManager)
        );
        emit SellReserveRatioSet(_newRatio, RESERVE_RATIO_FOR_SELLING);
        bondingCurveFundingManager.setReserveRatioForSelling(_newRatio);
        assertEq(
            bondingCurveFundingManager.call_reserveRatioForSelling(), _newRatio
        );
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /* Test _setIssuanceToken function
        ├── When decimal is set to lower than seven
        |   └── it should revert
        ├── When decimal is set to more than the collateral decimals
        |   └── it should revert
        └── when decimal is between seven and the the collateral decimals
            ├── it should store the new decimal number 
            └── it should succeed
            */

    function testSetIssuanceToken_FailsIfTokenDecimalsLowerThanSeven(
        uint _newMaxSupply,
        uint8 _newDecimals
    ) public {
        vm.assume(_newDecimals < 7);
        vm.assume(_newMaxSupply != 0);

        string memory _name = "New Issuance Token";
        string memory _symbol = "NEW";

        ERC20Issuance_v1 newIssuanceToken = new ERC20Issuance_v1(
            _name, _symbol, _newDecimals, _newMaxSupply, address(this)
        );

        vm.expectRevert(
            IFM_BC_Bancor_Redeeming_VirtualSupply_v1
                .Module__FM_BC_Bancor_Redeeming_VirtualSupply__InvalidTokenDecimal
                .selector
        );
        // No authentication since it's an internal function exposed by the mock contract
        bondingCurveFundingManager.call_setIssuanceToken(
            address(newIssuanceToken)
        );
    }

    function testSetIssuanceToken_FailsIfLowerThanCollateralDecimals(
        uint _newMaxSupply,
        uint8 _newDecimals
    ) public {
        vm.assume(_newDecimals < _token.decimals());
        vm.assume(_newMaxSupply != 0);

        string memory _name = "New Issuance Token";
        string memory _symbol = "NEW";

        ERC20Issuance_v1 newIssuanceToken = new ERC20Issuance_v1(
            _name, _symbol, _newDecimals, _newMaxSupply, address(this)
        );

        vm.expectRevert(
            IFM_BC_Bancor_Redeeming_VirtualSupply_v1
                .Module__FM_BC_Bancor_Redeeming_VirtualSupply__InvalidTokenDecimal
                .selector
        );
        // No authentication since it's an internal function exposed by the mock contract
        bondingCurveFundingManager.call_setIssuanceToken(
            address(newIssuanceToken)
        );
    }

    function testSetIssuanceToken(uint _newMaxSupply, uint8 _newDecimals)
        public
    {
        vm.assume(_newDecimals >= 7 && _newDecimals >= _token.decimals());
        vm.assume(_newMaxSupply != 0);

        string memory _name = "New Issuance Token";
        string memory _symbol = "NEW";

        ERC20Issuance_v1 newIssuanceToken = new ERC20Issuance_v1(
            _name, _symbol, _newDecimals, _newMaxSupply, address(this)
        );

        // No authentication since it's an internal function exposed by the mock contract
        bondingCurveFundingManager.call_setIssuanceToken(
            address(newIssuanceToken)
        );

        ERC20Issuance_v1 issuanceTokenAfter =
            ERC20Issuance_v1(bondingCurveFundingManager.getIssuanceToken());

        assertEq(issuanceTokenAfter.name(), _name);
        assertEq(issuanceTokenAfter.symbol(), _symbol);
        assertEq(issuanceTokenAfter.decimals(), _newDecimals);
        assertEq(issuanceTokenAfter.cap(), _newMaxSupply);

        // we also check the decimals have been cached correctly

        assertEq(
            bondingCurveFundingManager.call_issuanceTokenDecimals(),
            _newDecimals
        );
    }

    /* Test _convertAmountToRequiredDecimal function
        ├── when the token decimals and the required decimals are the same
        │       └── it should return the amount without change
        ├── when the token decimals are higher than the required decimals
        │       └── it should cut the excess decimals from the amount and return it
        └── when caller is the Orchestrator_v1 admin
                └── it should pad the amount by the missing decimals and return it
        */

    function testConvertAmountToRequiredDecimals_whenEqual(
        uint _amount,
        uint8 _decimals
    ) public {
        assertEq(
            bondingCurveFundingManager.call_convertAmountToRequiredDecimal(
                _amount, _decimals, _decimals
            ),
            _amount
        );
    }

    function testConvertAmountToRequiredDecimals_whenAbove(
        uint _amount,
        uint8 _tokenDecimals,
        uint8 _requiredDecimals
    ) public {
        // Bounds necessary to avoid overflows:
        // amount < (1e78 (uint.max) - 1e36 (max decimals in test) - 1e5 (BPS))
        _amount = bound(_amount, 1, 1e41);
        _requiredDecimals = uint8(bound(_requiredDecimals, 1, 18));
        _tokenDecimals = uint8(bound(_tokenDecimals, _requiredDecimals + 1, 36));

        uint res = bondingCurveFundingManager
            .call_convertAmountToRequiredDecimal(
            _amount, _tokenDecimals, _requiredDecimals
        );
        uint factor = _tokenDecimals - _requiredDecimals;

        assertEq((_amount / (10 ** factor)), res);
    }

    function testConvertAmountToRequiredDecimals_whenBelow(
        uint _amount,
        uint8 _tokenDecimals,
        uint8 _requiredDecimals
    ) public {
        // Bounds necessary to avoid overflows:
        // amount < (1e78 (uint.max) - 1e36 (max decimals in test) - 1e5 (BPS))
        _amount = bound(_amount, 1, 1e41);
        _tokenDecimals = uint8(bound(_tokenDecimals, 1, 18));
        _requiredDecimals =
            uint8(bound(_requiredDecimals, _tokenDecimals + 1, 36));

        uint res = bondingCurveFundingManager
            .call_convertAmountToRequiredDecimal(
            _amount, _tokenDecimals, _requiredDecimals
        );
        uint factor = _requiredDecimals - _tokenDecimals;
        assertEq((res % (10 ** factor)), 0);
    }
    //--------------------------------------------------------------------------
    // OnlyOrchestrator Mutating Functions

    /* Test transferOrchestratorToken 
        ├── given the onlyPaymentClient modifier is set (individual modifier tests are done in Module_v1.t.sol)
        │   └── and the conditions of the modifier are not met
        │       └── when the function transferOrchestratorToken() gets called
        │           └── then it should revert
        └── given the caller is a PaymentClient module
                └── and the PaymentClient module is registered in the Orchestrator
                    ├── and the withdraw amount + project collateral fee > FM collateral token balance
                    │   └── when the function transferOrchestratorToken() gets called
                    │       └── then it should revert
                    └── and the FM has enough collateral token for amount to be transferred
                            when the function transferOrchestratorToken() gets called
                            └── then is should send the funds to the specified address
                                └── and it should emit an event
    */

    function testTransferOrchestratorToken_OnlyPaymentClientModifierSet(
        address caller,
        address to,
        uint amount
    ) public {
        _erc20PaymentClientMock = new ERC20PaymentClientBaseV1Mock();

        vm.prank(caller);
        vm.expectRevert(IModule_v1.Module__OnlyCallableByPaymentClient.selector);
        bondingCurveFundingManager.transferOrchestratorToken(to, amount);
    }

    function testTransferOrchestratorToken_FailsGivenNotEnoughCollateralInFM(
        address to,
        uint amount,
        uint projectCollateralFeeCollected
    ) public virtual {
        vm.assume(to != address(0) && to != address(bondingCurveFundingManager));

        amount = bound(amount, 1, type(uint128).max);
        projectCollateralFeeCollected =
            bound(projectCollateralFeeCollected, 1, type(uint128).max);

        // Add collateral fee collected to create fail scenario
        bondingCurveFundingManager.setProjectCollateralFeeCollectedHelper(
            projectCollateralFeeCollected
        );
        assertEq(
            bondingCurveFundingManager.projectCollateralFeeCollected(),
            projectCollateralFeeCollected
        );
        amount = amount + projectCollateralFeeCollected; // Withdraw amount which includes the fee

        _token.mint(address(bondingCurveFundingManager), amount);
        assertEq(_token.balanceOf(address(bondingCurveFundingManager)), amount);

        // Add logic module to workflow to pass modifier
        _erc20PaymentClientMock = new ERC20PaymentClientBaseV1Mock();
        _addLogicModuleToOrchestrator(address(_erc20PaymentClientMock));
        vm.startPrank(address(_erc20PaymentClientMock));
        {
            vm.expectRevert(
                IFM_BC_Bancor_Redeeming_VirtualSupply_v1
                    .Module__FM_BC_Bancor_Redeeming_VirtualSupply__InvalidOrchestratorTokenWithdrawAmount
                    .selector
            );
            bondingCurveFundingManager.transferOrchestratorToken(to, amount);
        }
        vm.stopPrank();
    }

    function testTransferOrchestratorToken_WorksGivenFunctionGetsCalled(
        address to,
        uint amount
    ) public virtual {
        vm.assume(to != address(0) && to != address(bondingCurveFundingManager));

        _token.mint(address(bondingCurveFundingManager), amount);

        assertEq(_token.balanceOf(to), 0);
        assertEq(_token.balanceOf(address(bondingCurveFundingManager)), amount);

        // Add logic module to workflow to pass modifier
        _erc20PaymentClientMock = new ERC20PaymentClientBaseV1Mock();
        _addLogicModuleToOrchestrator(address(_erc20PaymentClientMock));
        vm.startPrank(address(_erc20PaymentClientMock));
        {
            vm.expectEmit(true, true, true, true);
            emit TransferOrchestratorToken(to, amount);

            bondingCurveFundingManager.transferOrchestratorToken(to, amount);
        }
        vm.stopPrank();

        assertEq(_token.balanceOf(to), amount);
        assertEq(_token.balanceOf(address(bondingCurveFundingManager)), 0);
    }

    //--------------------------------------------------------------------------
    // Modifier test

    /* Test modifier onlyWhenCurveInteractionsAreClosed()
        ├── given buying and selling are open
        │   └── when a function with the modifier onlyWhenCurveInteractionsAreClosed() gets called
        │       └── then it should revert
        ├── given buying is open and selling is closed
        │   └── when a function with the modifier onlyWhenCurveInteractionsAreClosed() gets called
        │       └── then it should revert
        ├── given buying is closed and selling is open
        │   └── when a function with the modifier onlyWhenCurveInteractionsAreClosed() gets called
        │       └── then it should revert
        └── given buying is closed and selling is closed
            └── when a function with the modifier onlyWhenCurveInteractionsAreClosed() gets called
                └── then it should succeed
    */

    function testModifierOnlyWhenCurveInteractionsAreClosed_failsGivenBuyAndSellAreOpen(
    ) external {
        uint virtualSupply = 100e18;

        vm.expectRevert(
            IFM_BC_Bancor_Redeeming_VirtualSupply_v1
                .Module__FM_BC_Bancor_Redeeming_VirtualSupply__CurveInteractionsMustBeClosed
                .selector
        );
        bondingCurveFundingManager.setVirtualIssuanceSupply(virtualSupply);
    }

    function testModifierOnlyWhenCurveInteractionsAreClosed_failsGivenBuyisOpenAndSellIsClosed(
    ) external {
        uint virtualSupply = 100e18;
        bondingCurveFundingManager.closeSell();

        vm.expectRevert(
            IFM_BC_Bancor_Redeeming_VirtualSupply_v1
                .Module__FM_BC_Bancor_Redeeming_VirtualSupply__CurveInteractionsMustBeClosed
                .selector
        );
        bondingCurveFundingManager.setVirtualIssuanceSupply(virtualSupply);
    }

    function testModifierOnlyWhenCurveInteractionsAreClosed_failsGivenBuyisClosedAndSellIsOpen(
    ) external {
        uint virtualSupply = 100e18;
        bondingCurveFundingManager.closeBuy();

        vm.expectRevert(
            IFM_BC_Bancor_Redeeming_VirtualSupply_v1
                .Module__FM_BC_Bancor_Redeeming_VirtualSupply__CurveInteractionsMustBeClosed
                .selector
        );
        bondingCurveFundingManager.setVirtualIssuanceSupply(virtualSupply);
    }

    function testModifierOnlyWhenCurveInteractionsAreClosed_worksGivenBuyAndSellAreClosed(
    ) external {
        uint virtualSupply = 100e18;
        _closeCurveInteractions();
        bondingCurveFundingManager.setVirtualIssuanceSupply(virtualSupply);
    }

    // -------------------------------------------------------------------------
    // Internal Functions

    /*
    Test: _handleIssuanceTokensBeforeBuy
    └── When: the function _handleCollateralTokensBeforeBuy is called
        └── Then: it should transfer the correct amount of collateral tokens from the provider address to the bonding curve contract
    */

    function test_handleCollateralTokensBeforeBuy(
        address _provider,
        uint _amount
    ) public {
        // Setup
        vm.assume(
            _provider != address(0)
                && _provider != address(bondingCurveFundingManager)
        );
        vm.assume(_amount > 0);

        _token.mint(_provider, _amount);
        vm.prank(_provider);
        _token.approve(address(bondingCurveFundingManager), _amount);

        // Execute
        bondingCurveFundingManager.call_handleCollateralTokensBeforeBuy(
            _provider, _amount
        );

        // Assert
        assertEq(_token.balanceOf(address(bondingCurveFundingManager)), _amount);
    }

    /*
    Test: _handleIssuanceTokensAfterBuy
    └── When: the function _handleIssuanceTokensAfterBuy is called
        └── Then: it should mint the correct amount of tokens to the receiver address
    */

    function test_handleIssuanceTokensAfterBuy(
        address _receiver,
        uint _issuanceTokenAmount
    ) public {
        // Setup
        vm.assume(_receiver != address(0));
        vm.assume(_issuanceTokenAmount > 0);

        // Execute
        bondingCurveFundingManager.call_handleIssuanceTokensAfterBuy(
            _receiver, _issuanceTokenAmount
        );

        // Assert
        assertEq(issuanceToken.balanceOf(_receiver), _issuanceTokenAmount);
    }

    /*
    Test: _handleCollateralTokensAfterSell
    └── When: the function _handleCollateralTokensAfterSell is called
        └── Then: it should transfer the correct amount of tokens to the receiver address
    */

    function test_handleCollateralTokensAfterSell(
        address _receiver,
        uint _amount
    ) public {
        // Setup
        vm.assume(
            _receiver != address(0)
                && _receiver != address(bondingCurveFundingManager)
        );
        vm.assume(_amount > 0);

        _token.mint(address(bondingCurveFundingManager), _amount);

        // Execute
        bondingCurveFundingManager.call_handleCollateralTokensAfterSell(
            _receiver, _amount
        );

        // Assert
        assertEq(_token.balanceOf(_receiver), _amount);
        assertEq(_token.balanceOf(address(bondingCurveFundingManager)), 0);
    }

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

    function _closeCurveInteractions() internal {
        bondingCurveFundingManager.closeBuy();
        bondingCurveFundingManager.closeSell();
    }

    function _openCurveInteractions() internal {
        bondingCurveFundingManager.openBuy();
        bondingCurveFundingManager.openSell();
    }

    // Helper function that:
    //      - Mints collateral tokens to a seller and
    //      - Deposits them so they can later be sold.
    //      - Approves the BondingCurve contract to spend the receipt tokens
    // This function assumes that we are using the Mock with a 0% buy fee, so the user will receive as many tokens as they deposit
    function _prepareSellConditions(address seller, uint amount)
        internal
        returns (uint userSellAmount)
    {
        _token.mint(seller, amount);
        uint minAmountOut =
            bondingCurveFundingManager.calculatePurchaseReturn(amount);
        vm.startPrank(seller);
        {
            _token.approve(address(bondingCurveFundingManager), amount);
            bondingCurveFundingManager.buy(amount, minAmountOut);
            userSellAmount = issuanceToken.balanceOf(seller);

            issuanceToken.approve(
                address(bondingCurveFundingManager), userSellAmount
            );
        }
        vm.stopPrank();

        return userSellAmount;
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
