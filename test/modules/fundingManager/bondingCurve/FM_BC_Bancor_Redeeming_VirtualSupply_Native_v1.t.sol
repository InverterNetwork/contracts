// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {Clones} from "@oz/proxy/Clones.sol";
import {BancorFormula} from
    "src/modules/fundingManager/bondingCurve/formulas/BancorFormula.sol";
import {
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1,
    FM_BC_Bancor_Redeeming_VirtualSupply_v1,
    IFundingManager_v1
} from
    "src/modules/fundingManager/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";

import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";
import {OZErrors} from "test/utils/errors/OZErrors.sol";

import {IFM_BC_Bancor_Redeeming_VirtualSupply_Native_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_Native_v1.sol";
import {NativeIssuance_v1} from "@ex/token/NativeIssuance_v1.sol";
import {FM_BC_Bancor_Redeeming_VirtualSupply_Native_v1} from
    "@fm/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_Native_v1.sol";
import {FM_BC_Bancor_Redeeming_VirtualSupply_NativeV1Mock} from
    "./utils/mocks/FM_BC_Bancor_Redeeming_VirtualSupply_NativeV1Mock.sol";
import {NativeMinterMock} from "test/utils/mocks/external/NativeMinterMock.sol";

contract FM_BC_Bancor_Redeeming_VirtualSupply_NativeV1Test is ModuleTest {
    string internal constant NAME = "Native Issuance";
    string internal constant SYMBOL = "NATIVE";
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

    address admin_address = address(0xA1BA);
    address non_admin_address = address(0xB0B);

    NativeIssuance_v1 issuanceToken;
    FM_BC_Bancor_Redeeming_VirtualSupply_NativeV1Mock bondingCurveFundingManager;
    address formula;

    function setUp() public virtual {
        NativeMinterMock nativeMinter = new NativeMinterMock();
        vm.etch(
            0x0200000000000000000000000000000000000001,
            address(nativeMinter).code
        );
        vm.deal(0x0200000000000000000000000000000000000001, 1e38);

        issuanceToken = new NativeIssuance_v1(admin_address);
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

        address impl =
            address(new FM_BC_Bancor_Redeeming_VirtualSupply_NativeV1Mock());
        bondingCurveFundingManager =
        FM_BC_Bancor_Redeeming_VirtualSupply_NativeV1Mock(Clones.clone(impl));

        _setUpOrchestrator(bondingCurveFundingManager);

        _authorizer.grantRole(_authorizer.getAdminRole(), admin_address);

        bondingCurveFundingManager.init(
            _orchestrator,
            _METADATA,
            abi.encode(
                address(issuanceToken),
                bc_properties,
                _token // fetching from ModuleTest.sol (specifically after the _setUpOrchestrator function call)
            )
        );

        vm.prank(admin_address);
        issuanceToken.setMinter(address(bondingCurveFundingManager), true);
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

    /* Test `buy` function
        └── when the fee is 0
            ├── it should pull the buy amount from the caller
            ├── it should determine the mint amount of tokens to mint 
            ├── it should mint the tokens to the receiver        
    */

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
        _token.mint(buyer, amount);
        vm.prank(buyer);
        _token.approve(address(bondingCurveFundingManager), amount);

        // Pre-checks
        uint balanceBefore =
            _token.balanceOf(address(bondingCurveFundingManager));
        assertEq(_token.balanceOf(buyer), amount);
        assertEq(issuanceToken.balanceOf(buyer), 0);

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
        bondingCurveFundingManager.buy(amount, formulaReturn);
        // Post-checks
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManager)),
            (balanceBefore + amount)
        );
        assertEq(_token.balanceOf(buyer), 0);
        assertEq(issuanceToken.balanceOf(buyer), formulaReturn);
    }

    /* Test `sell` function
        ├── when the sell amount is 0 or msg.value is 0
        │       └── it should revert 
        └── when the sell amount is not 0
                └── when the fee is 0
                        ├── it should take the sell amount from the caller
                        ├── it should determine the redeem amount of the sent tokens 
                        └── When there IS enough collateral in the contract to cover the redeem amount
                                └── When the amount of redeemed tokens does not exceed the virtual issuance supply
                                        └── it should send the rest to the receiver    
    */
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
            bondingCurveFundingManager.sellNative{value: userSellAmount}(
                normalized_formulaReturn
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

    function testSellNativeRevertsWhenAmountIsZero() public {
        address seller = makeAddr("seller");
        vm.startPrank(seller);
        vm.expectRevert(
            IFM_BC_Bancor_Redeeming_VirtualSupply_Native_v1
                .IFM_BC_Bancor_Redeeming_VirtualSupply_Native_v1__InvalidDepositAmount
                .selector
        );
        bondingCurveFundingManager.sellNative{value: 0}(1);
        vm.stopPrank();
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
        }
        vm.stopPrank();

        return userSellAmount;
    }

    function _closeCurveInteractions() internal {
        bondingCurveFundingManager.closeBuy();
        bondingCurveFundingManager.closeSell();
    }

    function _openCurveInteractions() internal {
        bondingCurveFundingManager.openBuy();
        bondingCurveFundingManager.openSell();
    }
}
