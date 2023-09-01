// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// SuT

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

// Internal Dependencies
import {ModuleTest, IModule, IOrchestrator} from "test/modules/ModuleTest.sol";
import {BancorFormula} from
    "src/modules/fundingManager/bondingCurveFundingManager/formula/BancorFormula.sol";
import {IVirtualTokenSupply} from
    "src/modules/fundingManager/bondingCurveFundingManager/marketMaker/IVirtualTokenSupply.sol";
import {IVirtualCollateralSupply} from
    "src/modules/fundingManager/bondingCurveFundingManager/marketMaker/IVirtualCollateralSupply.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// Mocks
import {
    BancorVirtualSupplyBondingCurveFundingManagerMock,
    IBancorVirtualSupplyBondingCurveFundingManager
} from
    "test/modules/fundingManager/bondingCurveFundingManager/marketMaker/utils/mocks/BancorVirtualSupplyBondingCurveFundingManagerMock.sol";

import { 
    RedeemingBondingCurveFundingManagerBaseTest
} from     "test/modules/fundingManager/bondingCurveFundingManager/RedeemingB_CurveFundingManagerBase.t.sol";

contract BancorVirtualSupplyBondingCurveFundingManagerTest is ModuleTest {
    string private constant NAME = "Bonding Curve Token";
    string private constant SYMBOL = "BCT";
    //uint8 private constant DECIMALS = 18; // hardcoded for now @review
    uint private constant INITIAL_TOKEN_SUPPLY = 100;
    uint private constant INITIAL_COLLATERAL_SUPPLY = 100;
    uint32 private constant RESERVE_RATIO_FOR_BUYING = 200_000;
    uint32 private constant RESERVE_RATIO_FOR_SELLING = 200_000;
    uint private constant BUY_FEE = 0;
    uint private constant SELL_FEE = 0;
    bool private constant BUY_IS_OPEN = true;
    bool private constant SELL_IS_OPEN = true;

    BancorVirtualSupplyBondingCurveFundingManagerMock bondingCurveFundingManger;
    address formula;

    address owner_address = address(0xA1BA);
    address non_owner_address = address(0xB0B);
 
    function setUp() public  {
        // Deploy contracts
        address impl = address(new BancorVirtualSupplyBondingCurveFundingManagerMock());

        bondingCurveFundingManger =
            BancorVirtualSupplyBondingCurveFundingManagerMock(Clones.clone(impl));

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
                //DECIMALS,  @todo see BancorBondingCurveContract
                formula,
                INITIAL_TOKEN_SUPPLY,
                INITIAL_COLLATERAL_SUPPLY,
                RESERVE_RATIO_FOR_BUYING,
                RESERVE_RATIO_FOR_SELLING,
                BUY_FEE,
                SELL_FEE,
                BUY_IS_OPEN,
                SELL_IS_OPEN
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
            //DECIMALS,
            18,
            "Decimals has not been set correctly"
        );
        assertEq(
            address(bondingCurveFundingManger.formula()),
            formula,
            "Formula has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManger.getVirtualTokenSupply(),
            INITIAL_TOKEN_SUPPLY,
            "Virtual token supply has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManger.getVirtualCollateralSupply(),
            INITIAL_COLLATERAL_SUPPLY,
            "Virtual collateral supply has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManger.call_reserveRatioForBuying(),
            RESERVE_RATIO_FOR_BUYING,
            "Reserve ratio for buying has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManger.call_reserveRatioForSelling(),
            RESERVE_RATIO_FOR_SELLING,
            "Reserve ratio for selling has not been set correctly"
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
        assertEq(
            bondingCurveFundingManger.buyFee(),
            SELL_FEE,
            "Sell fee has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManger.buyIsOpen(),
            SELL_IS_OPEN,
            "Sell-is-open has not been set correctly"
        );
    } 

        function testReinitFails() public override {
        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        bondingCurveFundingManger.init(_orchestrator, _METADATA, abi.encode());
    }


     //--------------------------------------------------------------------------
    // Public Functions

    // TODO expand for virtual supply
    // test buyOrderFor function
    //  - Both modifiers have been tested in the upstream tests
    //  - The goal of this test is just to verify that the tokens get sent to a different receiver


    // TODO expand for virtual supply
    /* Test buyOrder and _virtualSupplyBuyOrder function
        ├── when the deposit amount is 0
        │       └── it should revert 
        └── when the deposit amount is not 0
                ├── when the fee is higher than 0
                │       └── it should substract the fee from the deposit amount
                │               ├── it should pull the buy amount from the caller  
                │               ├── it should take the fee out from the pulled amount 
                │               ├── it should determine the mint amount of tokens to mint from the rest
                │               ├── it should mint the tokens to the receiver 
                │               ├── it should emit an event? @todo  
                │               ├── it should update the virtual token amount
                │               ├── it should emit an event? @todo 
                │               ├── it should update the virtual collateral amount
                │               └── it should emit an event? @todo             
                └── when the fee is 0
                                ├── it should pull the buy amount from the caller  
                                ├── it should determine the mint amount of tokens to mint 
                                ├── it should mint the tokens to the receiver 
                                ├── it should emit an event? @todo  
                                ├── it should update the virtual token amount
                                ├── it should emit an event? @todo 
                                ├── it should update the virtual collateral amount
                                └── it should emit an event? @todo       
        
    */
    function testBuyOrder_FailsIfDepositAmountIsZero() public {
        // Test covered in BondingCurveFundingManagerBase
    }

     function testBuyOrderWithZeroFee(uint amount) public {
        // Setup
        // Above an amount of 1e38 the BancorFormula starts to revert. Assuming a token with 18 decimals or less, this value should cover most realistic usecases. 
        // @question @review should we add an explicit check in the deposit code?
        amount = bound(amount, 1, 1e38); 

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
        //assertEq(bondingCurveFundingManger.balanceOf(buyer), amount);
        //TODO get the expected amount to receive and control for it
    }


    function testBuyOrderWithFee(uint amount, uint fee) public {
        // Setup
        uint _bps = bondingCurveFundingManger.call_BPS();
        vm.assume(fee < _bps);

        amount = bound(amount, 1, 1e38); // see comment in testBuyOrderWithZeroFee

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
        //uint amountMinusFee =
        //    amount - (amount * fee / bondingCurveFundingManger.call_BPS());
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManger)),
            (balanceBefore + amount)
        );
        assertEq(_token.balanceOf(buyer), 0);
        //assertEq(bondingCurveFundingManger.balanceOf(buyer), amountMinusFee);
        //TODO get the expected amount to receive and control for it
    }
 


 
    // test sellOrderFor function
    //  - Both modifiers have been tested in the upstream tests
    //  - The goal of this test is just to verify that the tokens get sent to a different receiver



    /* Test sellOrder and _virtualSupplySellOrder function
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
                │                       ├── When the amount of redeemed tokens exceeds the virtual token supply
                │                       │       └── it should revert
                │                       └── When the amount of redeemed tokens does not exceed the virtual token supply
                │                               ├── When the amount  of extracted collateral exceeds the virtual token supply
                │                               │       └── it should revert
                │                               └── When the amount of extracted collateral does not exceed the virtual collateral supply
                │                                       ├── it should send the rest to the receiver    
                │                                       ├── it should emit an event? @todo
                │                                       ├── it should update the virtual token amount
                │                                       ├── it should emit an event? @todo 
                │                                       ├── it should update the virtual collateral amount
                │                                       └── it should emit an event? @todo 
                └── when the fee is 0
                                ├── it should take the sell amount from the caller
                                ├── it should determine the redeem amount of the sent tokens 
                                ├── When there IS NOT enough collateral in the contract to cover the redeem amount
                                │        └── it should revert
                                └── When there IS enough collateral in the contract to cover the redeem amount
                                        ├── When the amount of redeemed tokens exceeds the virtual token supply
                                        │       └── it should revert
                                        └── When the amount of redeemed tokens does not exceed the virtual token supply
                                                ├── When the amount  of extracted collateral exceeds the virtual token supply
                                                │       └── it should revert
                                                └── When the amount of extracted collateral does not exceed the virtual collateral supply
                                                        ├── it should send the rest to the receiver    
                                                        ├── it should emit an event? @todo
                                                        ├── it should update the virtual token amount
                                                        ├── it should emit an event? @todo 
                                                        ├── it should update the virtual collateral amount
                                                        └── it should emit an event? @todo 
            */


    function testSellOrder_FailsIfDepositAmountIsZero() public {
        // Test covered in RedeemingBondingCurveFundingManagerBase
    }

    function testSellOrder_FailsIfRedeemAmountExceedsVirtualCollateralSupply(uint amount) public {
        // Setup
        amount = bound(amount, 1, 1e38); // see comment in testBuyOrderWithZeroFee
        _token.mint(address(bondingCurveFundingManager), (type(uint).max - amount));

        address seller = makeAddr("seller");
        _prepareSellConditions(seller, amount);

        // we set a virtual collateral supply that will not cover the amount to redeem
        vm.prank(owner_address);
        bondingCurveFundingManger.setVirtualCollateralSupply(1);
        
        vm.startPrank(seller);
        {
            vm.expectRevert(
                IVirtualCollateralSupply.VirtualCollateralSupply__SubtractResultsInUnderflow.selector
            );
            bondingCurveFundingManger.sellOrder(amount);
        }
        vm.stopPrank();
    }

    function testSellOrder_FailsIfBurnAmountExceedsVirtualTokenSupply() public {
        // TODO
    }

    function testSellOrder_FailsIfNotEnoughCollateralInContract(uint amount)
        public
    {
        // Setup
        amount = bound(amount, 1, 1e38); // see comment in testBuyOrderWithZeroFee


        address seller = makeAddr("seller");
        _prepareSellConditions(seller, amount);

        // we simulate the fundingManager spending some funds. It can't cover full redemption anymore.
        _token.burn(address(bondingCurveFundingManger), 1);

        vm.startPrank(seller);
        {
            vm.expectRevert(
            );
            bondingCurveFundingManger.sellOrder(amount);
        }
        vm.stopPrank();
    } 

//TODO
        function testSellOrderWithZeroFee(uint _sellAmount) public {
        // Setup
        _sellAmount = bound(_sellAmount, 1, 1e38); // see comment in testBuyOrderWithZeroFee

        // In this test we are going to use the fact that we are using virtual balances to our advantage

        // mint _sellAmount of receipt tokens to the seller
        // mint uint.max() amount of collateral tokens to the bondingCurveFundingManger

        // set virtual supply to some number above _sellAmount
        // use the formula to get the corresponding "ideal" collateral given reserve ratio

        // perform the sell

        // check real-world token/collateral balances
        // check virtual token/collateral balances


/*         address seller = makeAddr("seller");
        _prepareSellConditions(seller, amount);

        // Pre-checks
        uint bondingCurveCollateralBalanceBefore =
            _token.balanceOf(address(bondingCurveFundingManger));
        assertEq(_token.balanceOf(seller), 0);
        uint userSellAmount = bondingCurveFundingManger.balanceOf(seller);

        // Execution
        vm.prank(seller);
        bondingCurveFundingManger.sellOrder(userSellAmount);

        // Post-checks
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManger)),
            (bondingCurveCollateralBalanceBefore - amount)
        );
        assertEq(_token.balanceOf(seller), amount);
        assertEq(bondingCurveFundingManger.balanceOf(seller), 0); */
    }
/*
    //TODO
    function testSellOrderWithFee(uint amount, uint fee) public {
        // Setup
        uint _bps = bondingCurveFundingManger.call_BPS();
        vm.assume(fee < _bps);

        uint maxAmount = type(uint).max / _bps; // to prevent overflows
        amount = bound(amount, 1, maxAmount);

        vm.prank(owner_address);
        bondingCurveFundingManger.setSellFee(fee);
        assertEq(bondingCurveFundingManger.sellFee(), fee);

        address seller = makeAddr("seller");
        _prepareSellConditions(seller, amount);

        // Pre-checks
        uint bondingCurveCollateralBalanceBefore =
            _token.balanceOf(address(bondingCurveFundingManger));
        assertEq(_token.balanceOf(seller), 0);

        // Execution
        vm.prank(seller);
        bondingCurveFundingManger.sellOrder(amount);

        // Post-checks
        uint amountMinusFee =
            amount - ((amount * fee) / bondingCurveFundingManger.call_BPS());
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManger)),
            (bondingCurveCollateralBalanceBefore - amountMinusFee)
        );
        assertEq(_token.balanceOf(seller), amountMinusFee);
        assertEq(bondingCurveFundingManger.balanceOf(seller), 0);
    }
 */
    //--------------------------------------------------------------------------
    // Public Mutating Functions

    // test token() getter
    function testCollateralTokenGetter() public {
        address orchestratorToken = address(_orchestrator.token());
        assertEq(
            address(bondingCurveFundingManger.token()),
            orchestratorToken,
            "Token getter returns wrong address"
        );
    }

    // No need to test these four:
    /*     
    function deposit(uint amount) external {}
    function depositFor(address to, uint amount) external {}
    function withdraw(uint amount) external {}
    function withdrawTo(address to, uint amount) external {} 
    */

    //--------------------------------------------------------------------------
    // OnlyOrchestrator Functions

 
/*   
     // Probably bug and tested in VirtualTokenSupplyBase tests?
    function mintIssuanceTokenTo(address _receiver, uint _amount)
        external
        onlyOrchestratorOwner
        validReceiver(_receiver)
 */

    /* Test setVirtualTokenSupply and _setVirtualTokenSupply function
        ├── when caller is not the Orchestrator owner
        │      └── it should revert (tested in base Module tests)
        └── when caller is the Orchestrator owner
                ├── it should set the new token supply
                └── it should emit an event? @todo

    */
    function testSetVirtualTokenSupply(uint _newSupply) public callerIsOrchestratorOwner() {
        bondingCurveFundingManger.setVirtualTokenSupply(_newSupply);
        assertEq(
            bondingCurveFundingManger.getVirtualTokenSupply(),
            _newSupply
        );
    }

    /* Test setVirtualCollateralSupply and _ssetVirtualCollateralSupply function
        ├── when caller is not the Orchestrator owner
        │      └── it should revert (tested in base Module tests)
        └── when caller is the Orchestrator owner
                ├── it should set the new collateral supply
                └── it should emit an event? @todo

    */

   function testSetVirtualCollateralSupply(uint _newSupply) public callerIsOrchestratorOwner {
        bondingCurveFundingManger.setVirtualCollateralSupply(_newSupply);
        assertEq(
            bondingCurveFundingManger.getVirtualCollateralSupply(),
            _newSupply
        );
    }


    /* Test setReserveRatioForBuying and _setReserveRatioForBuying function
        ├── when caller is not the Orchestrator owner
        │       └── it should revert (tested in base Module tests)
        └── when caller is the Orchestrator owner
                ├── when reserve ratio is  0% 
                │       └── it should revert
                ├── when reserve ratio is below 100%
                │       ├── it should set the new ratio
                │       └── it should emit an event? @todo
                ├── when reserve ratio is  100% 
                │       ├── it should set the new ratio 
                │       └── it should emit an event? @todo
                └──  when reserve ratio is over 100% 
                        └── it should revert
    */
    function testSetReserveRatioForBuying_failsIfRatioIsZero() public callerIsOrchestratorOwner {
        vm.expectRevert(IBancorVirtualSupplyBondingCurveFundingManager.BancorVirtualSupplyBondingCurveFundingManager__InvalidReserveRatio.selector);
        bondingCurveFundingManger.setReserveRatioForBuying(0);
    }

    function testSetReserveRatioForBuying_failsIfRatioIsAboveMax(uint32 _newRatio) public callerIsOrchestratorOwner {
        vm.assume(_newRatio > bondingCurveFundingManger.call_PPM());
        vm.expectRevert(IBancorVirtualSupplyBondingCurveFundingManager.BancorVirtualSupplyBondingCurveFundingManager__InvalidReserveRatio.selector);
        bondingCurveFundingManger.setReserveRatioForBuying(_newRatio);
    }

    function testSetReserveRatioForBuying(uint32 _newRatio) public callerIsOrchestratorOwner {
        //manual bound for uint32
        _newRatio = _newRatio % bondingCurveFundingManger.call_PPM(); // @todo check what happens when ratio is 100%
        vm.assume(_newRatio > 0);

        bondingCurveFundingManger.setReserveRatioForBuying(_newRatio);
        assertEq(
            bondingCurveFundingManger.call_reserveRatioForBuying(),
            _newRatio
        );
    }
    
    /* Test setReserveRatioForSelling and _setReserveRatioForSelling function
        ├── when caller is not the Orchestrator owner
        │       └── it should revert (tested in base Module tests)
        └── when caller is the Orchestrator owner
                ├── when reserve ratio is  0% 
                │       └── it should revert
                ├── when reserve ratio is below 100%
                │       ├── it should set the new ratio
                │       └── it should emit an event? @todo
                ├── when reserve ratio is  100% 
                │       ├── it should set the new ratio 
                │       └── it should emit an event? @todo
                └──  when reserve ratio is over 100% 
                        └── it should revert
    */
    function testSetReserveRatioForSelling_failsIfRatioIsZero() public callerIsOrchestratorOwner {
        vm.expectRevert(IBancorVirtualSupplyBondingCurveFundingManager.BancorVirtualSupplyBondingCurveFundingManager__InvalidReserveRatio.selector);
        bondingCurveFundingManger.setReserveRatioForSelling(0);
    }

    function testSetReserveRatioForSelling_failsIfRatioIsAboveMax(uint32 _newRatio) public callerIsOrchestratorOwner {
        vm.assume(_newRatio > bondingCurveFundingManger.call_PPM());
        vm.expectRevert(IBancorVirtualSupplyBondingCurveFundingManager.BancorVirtualSupplyBondingCurveFundingManager__InvalidReserveRatio.selector);
        bondingCurveFundingManger.setReserveRatioForSelling(_newRatio);
    }

    function testSetReserveRatioForSelling(uint32 _newRatio) public callerIsOrchestratorOwner {
        //manual bound for uint32
        _newRatio = _newRatio % bondingCurveFundingManger.call_PPM(); // @todo check what happens when ratio is 100%
        vm.assume(_newRatio > 0);
        
        bondingCurveFundingManger.setReserveRatioForSelling(_newRatio);
        assertEq(
            bondingCurveFundingManger.call_reserveRatioForSelling(),
            _newRatio
        );
    }

    //--------------------------------------------------------------------------
    // Upstream Function Implementations

/*     function _issueTokensFormulaWrapper(uint _depositAmount)
        internal
        view
        override(BondingCurveFundingManagerBase)
        returns (uint mintAmount)
 */
/* 
    function _redeemTokensFormulaWrapper(uint _depositAmount)
        internal
        view
        override(RedeemingBondingCurveFundingManagerBase)
        returns (uint redeemAmount)

 */
    //--------------------------------------------------------------------------
    // Internal Functions

    /* Test _convertAmountToRequiredDecimal function
        ├── when the token decimals and the required decimals are the same
        │       └── it should return the amount without change
        ├── when the token decimals are higher than the required decimals
        │       └── it should cut the excess decimals from the amount and return it
        └── when caller is the Orchestrator owner
                └── it should pad the amount by the missing decimals and return it

        */
    function testConvertAmountToRequiredDecimals_whenEqual(uint _amount, uint8 _decimals) public {
        assertEq(
            bondingCurveFundingManger.call_convertAmountToRequiredDecimal(_amount, _decimals, _decimals),
            _amount
        );
    }

    function testConvertAmountToRequiredDecimals_whenAbove(uint _amount, uint8 _decimals) public {
        //TODO
    }

    function testConvertAmountToRequiredDecimals_whenBelow(uint _amount, uint8 _decimals) public {
        //TODO
    }
    //--------------------------------------------------------------------------
    // OnlyOrchestrator Mutating Functions

/*     function transferOrchestratorToken(address to, uint amount)
        external
        onlyOrchestrator
 */

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
        _token.approve(address(bondingCurveFundingManger), amount);
    }

    // Helper function that:
    //      - Mints collateral tokens to a seller and
    //      - Deposits them so they can later be sold.
    //      - Approves the BondingCurve contract to spend the receipt tokens
    // @note This function assumes that we are using the Mock with a 0% buy fee, so the user will receive as many toknes as they deposit
    function _prepareSellConditions(address seller, uint amount) internal {
        _token.mint(seller, amount);

        vm.startPrank(seller);
        {
            _token.approve(address(bondingCurveFundingManger), amount);
            bondingCurveFundingManger.buyOrder(amount);

            bondingCurveFundingManger.approve(
                address(bondingCurveFundingManger), amount
            );
        }
        vm.stopPrank();
    }

}