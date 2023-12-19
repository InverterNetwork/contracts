// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// SuT
import {
    IBancorVirtualSupplyBondingCurveFundingManager,
    BancorVirtualSupplyBondingCurveFundingManager,
    IFundingManager
} from
    "src/modules/fundingManager/bondingCurveFundingManager/BancorVirtualSupplyBondingCurveFundingManager.sol";

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
import {
    IRedeemingBondingCurveFundingManagerBase,
    IRedeemingBondingCurveFundingManagerBase
} from
    "src/modules/fundingManager/bondingCurveFundingManager/RedeemingBondingCurveFundingManagerBase.sol";
// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// Mocks
import {BancorVirtualSupplyBondingCurveFundingManagerMock} from
    "test/modules/fundingManager/bondingCurveFundingManager/marketMaker/utils/mocks/BancorVirtualSupplyBondingCurveFundingManagerMock.sol";

import {RedeemingBondingCurveFundingManagerBaseTest} from
    "test/modules/fundingManager/bondingCurveFundingManager/RedeemingB_CurveFundingManagerBase.t.sol";

/*     
    @NOTE: The functions:

    - deposit(uint amount) external {}
    - depositFor(address to, uint amount) external {}
    - withdraw(uint amount) external {}
    - withdrawTo(address to, uint amount) external {} 

    are not tested since they are empty and will be removed in the future.

    Also, since the following functions just wrap the Bancor formula contract, their content is assumed to be tested in the original formula tests, not here:

    - _issueTokensFormulaWrapper(uint _depositAmount)
    - _redeemTokensFormulaWrapper(uint _depositAmount)

    */

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

    BancorVirtualSupplyBondingCurveFundingManagerMock bondingCurveFundingManager;
    address formula;

    address owner_address = address(0xA1BA);
    address non_owner_address = address(0xB0B);

    event Transfer(address indexed from, address indexed to, uint value);

    event TokensBought(
        address indexed receiver,
        uint indexed depositAmount,
        uint indexed receivedAmount,
        address buyer
    );
    event VirtualCollateralAmountAdded(
        uint indexed amountAdded, uint indexed newSupply
    );
    event VirtualCollateralAmountSubtracted(
        uint indexed amountSubtracted, uint indexed newSupply
    );
    event VirtualTokenAmountSubtracted(
        uint indexed amountSubtracted, uint indexed newSupply
    );
    event VirtualTokenAmountAdded(
        uint indexed amountAdded, uint indexed newSupply
    );
    event TokensSold(
        address indexed receiver,
        uint indexed depositAmount,
        uint indexed receivedAmount,
        address seller
    );
    event BuyReserveRatioSet(
        uint32 indexed newBuyReserveRatio, uint32 indexed oldBuyReserveRatio
    );
    event SellReserveRatioSet(
        uint32 indexed newSellReserveRatio, uint32 indexed oldSellReserveRatio
    );
    event VirtualTokenSupplySet(uint indexed newSupply, uint indexed oldSupply);
    event VirtualCollateralSupplySet(
        uint indexed newSupply, uint indexed oldSupply
    );

    //--------------------------------------------------------------------------
    // Events
    event TransferOrchestratorToken(address indexed to, uint indexed amount);

    function setUp() public {
        // Deploy contracts
        IBancorVirtualSupplyBondingCurveFundingManager.IssuanceToken memory
            issuanceToken;
        IBancorVirtualSupplyBondingCurveFundingManager.BondingCurveProperties
            memory bc_properties;

        BancorFormula bancorFormula = new BancorFormula();
        formula = address(bancorFormula);

        issuanceToken.name = bytes32(abi.encodePacked(NAME));
        issuanceToken.symbol = bytes32(abi.encodePacked(SYMBOL));
        issuanceToken.decimals = uint8(18);

        bc_properties.formula = formula;
        bc_properties.reserveRatioForBuying = RESERVE_RATIO_FOR_BUYING;
        bc_properties.reserveRatioForSelling = RESERVE_RATIO_FOR_SELLING;
        bc_properties.buyFee = BUY_FEE;
        bc_properties.sellFee = SELL_FEE;
        bc_properties.buyIsOpen = BUY_IS_OPEN;
        bc_properties.sellIsOpen = SELL_IS_OPEN;
        bc_properties.initialTokenSupply = INITIAL_TOKEN_SUPPLY;
        bc_properties.initialCollateralSupply = INITIAL_COLLATERAL_SUPPLY;

        address impl =
            address(new BancorVirtualSupplyBondingCurveFundingManagerMock());

        bondingCurveFundingManager =
        BancorVirtualSupplyBondingCurveFundingManagerMock(Clones.clone(impl));

        _setUpOrchestrator(bondingCurveFundingManager);

        _authorizer.grantRole(_authorizer.getOwnerRole(), owner_address);

        // Init Module
        bondingCurveFundingManager.init(
            _orchestrator,
            _METADATA,
            abi.encode(
                issuanceToken,
                bc_properties,
                _token // fetching from ModuleTest.sol (specifically after the _setUpOrchestrator function call)
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
            //DECIMALS,
            18,
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
            bondingCurveFundingManager.getVirtualTokenSupply(),
            INITIAL_TOKEN_SUPPLY,
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
        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
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
        // Test covered in BondingCurveFundingManagerBase
    }

    function testBuyOrder_FailsIfDepositAmountOverflowsVirtualCollateralSupply(
        uint amount
    ) public {
        // Setup
        amount = bound(amount, 2, 1e38); // see comment in testBuyOrderWithZeroFee
        _token.mint(
            address(bondingCurveFundingManager), (type(uint).max - amount)
        );

        address buyer = makeAddr("buyer");
        _prepareBuyConditions(buyer, amount);

        // we set a virtual collateral supply that will not cover the amount to redeem
        vm.prank(owner_address);
        bondingCurveFundingManager.setVirtualCollateralSupply(
            type(uint).max - amount + 1
        );

        vm.startPrank(buyer);
        {
            vm.expectRevert(
                // This results in an overflow of the bonding curve math
            );
            bondingCurveFundingManager.buy(amount, amount);
        }
        vm.stopPrank();
    }

    function testBuyOrder_FailsIfMintAmountOverflowsVirtualTokenSupply(
        uint amount
    ) public {
        // Setup
        amount = bound(amount, 2, 1e38); // see comment in testBuyOrderWithZeroFee
        _token.mint(
            address(bondingCurveFundingManager), (type(uint).max - amount)
        );

        address buyer = makeAddr("buyer");
        _prepareBuyConditions(buyer, amount);

        // we set a virtual collateral supply that will not cover the amount to redeem
        vm.prank(owner_address);
        bondingCurveFundingManager.setVirtualTokenSupply(type(uint).max);

        vm.startPrank(buyer);
        {
            vm.expectRevert(
                // This results in an overflow of the bonding curve math
            );
            bondingCurveFundingManager.buy(amount, amount);
        }
        vm.stopPrank();
    }

    function testBuyOrderWithZeroFee(uint amount) public {
        // Setup
        // Above an amount of 1e38 the BancorFormula starts to revert.
        amount = bound(amount, 1, 1e38);

        address buyer = makeAddr("buyer");
        _prepareBuyConditions(buyer, amount);

        // Pre-checks
        uint balanceBefore =
            _token.balanceOf(address(bondingCurveFundingManager));
        assertEq(_token.balanceOf(buyer), amount);
        assertEq(bondingCurveFundingManager.balanceOf(buyer), 0);

        // Use formula to get expected return values
        uint formulaReturn = bondingCurveFundingManager.formula()
            .calculatePurchaseReturn(
            bondingCurveFundingManager.getVirtualTokenSupply(),
            bondingCurveFundingManager.getVirtualCollateralSupply(),
            bondingCurveFundingManager.call_reserveRatioForBuying(),
            amount
        );

        // Execution
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true, address(_token));
        emit Transfer(buyer, address(bondingCurveFundingManager), amount);
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit Transfer(address(0), buyer, formulaReturn);
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit TokensBought(buyer, amount, formulaReturn, buyer);
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit VirtualTokenAmountAdded(
            formulaReturn, (INITIAL_TOKEN_SUPPLY + formulaReturn)
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
        assertEq(bondingCurveFundingManager.balanceOf(buyer), formulaReturn);
    }

    function testBuyOrderWithFee(uint amount, uint fee) public {
        // Setup
        uint _bps = bondingCurveFundingManager.call_BPS();
        fee = bound(fee, 1, (_bps - 1)); // 100% buy fees are not allowed.

        amount = bound(amount, 1, 1e38); // see comment in testBuyOrderWithZeroFee

        vm.prank(owner_address);
        bondingCurveFundingManager.setBuyFee(fee);

        address buyer = makeAddr("buyer");
        _prepareBuyConditions(buyer, amount);

        // Pre-checks
        uint balanceBefore =
            _token.balanceOf(address(bondingCurveFundingManager));
        assertEq(_token.balanceOf(buyer), amount);
        assertEq(bondingCurveFundingManager.balanceOf(buyer), 0);

        // We calculate how much the real deposit amount will be after fees
        uint feeAmount = (amount * fee) / bondingCurveFundingManager.call_BPS();
        uint buyAmountMinusFee = amount - feeAmount;

        // Use formula to get expected return values
        uint formulaReturn = bondingCurveFundingManager.formula()
            .calculatePurchaseReturn(
            bondingCurveFundingManager.getVirtualTokenSupply(),
            bondingCurveFundingManager.getVirtualCollateralSupply(),
            bondingCurveFundingManager.call_reserveRatioForBuying(),
            buyAmountMinusFee
        );

        // Execution
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true, address(_token));
        emit Transfer(buyer, address(bondingCurveFundingManager), amount);
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit Transfer(address(0), buyer, formulaReturn);
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit TokensBought(buyer, buyAmountMinusFee, formulaReturn, buyer);
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit VirtualTokenAmountAdded(
            formulaReturn, (INITIAL_TOKEN_SUPPLY + formulaReturn)
        );
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit VirtualCollateralAmountAdded(
            buyAmountMinusFee, (INITIAL_TOKEN_SUPPLY + buyAmountMinusFee)
        );
        bondingCurveFundingManager.buy(amount, formulaReturn);

        // Post-checks
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManager)),
            (balanceBefore + amount)
        );
        assertEq(_token.balanceOf(buyer), 0);
        assertEq(bondingCurveFundingManager.balanceOf(buyer), formulaReturn);
    }

    // test buyFor function
    //  - Both modifiers have been tested in the upstream tests
    //  - Buy order branches are tested in sell tests
    //  - The goal of this test is just to verify that the tokens get sent to a different receiver

    function testBuyOrderFor(address to, uint amount) public {
        // Setup

        vm.assume(to != address(0));

        // Above an amount of 1e38 the BancorFormula starts to revert.
        amount = bound(amount, 1, 1e38);

        address buyer = makeAddr("buyer");
        assertNotEq(to, buyer);

        _prepareBuyConditions(buyer, amount);

        // Pre-checks
        uint balanceBefore =
            _token.balanceOf(address(bondingCurveFundingManager));
        assertEq(_token.balanceOf(buyer), amount);
        assertEq(bondingCurveFundingManager.balanceOf(buyer), 0);

        // Use formula to get expected return values
        uint formulaReturn = bondingCurveFundingManager.formula()
            .calculatePurchaseReturn(
            bondingCurveFundingManager.getVirtualTokenSupply(),
            bondingCurveFundingManager.getVirtualCollateralSupply(),
            bondingCurveFundingManager.call_reserveRatioForBuying(),
            amount
        );

        // Execution
        vm.prank(buyer);
        bondingCurveFundingManager.buyFor(to, amount, formulaReturn);

        // Post-checks
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManager)),
            (balanceBefore + amount)
        );
        assertEq(_token.balanceOf(buyer), 0);
        assertEq(bondingCurveFundingManager.balanceOf(buyer), 0);
        assertEq(bondingCurveFundingManager.balanceOf(to), formulaReturn);
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
                │                       ├── When the amount of redeemed tokens exceeds the virtual token supply
                │                       │       └── it should revert
                │                       └── When the amount of redeemed tokens does not exceed the virtual token supply
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
                                        ├── When the amount of redeemed tokens exceeds the virtual token supply
                                        │       └── it should revert
                                        └── When the amount of redeemed tokens does not exceed the virtual token supply
                                                ├── it should send the rest to the receiver    
                                                ├── it should emit an event
                                                ├── it should update the virtual token amount
                                                ├── it should emit an event
                                                ├── it should update the virtual collateral amount
                                                └── it should emit an event
    */

    function testSellOrder_FailsIfDepositAmountIsZero() public {
        // Test covered in RedeemingBondingCurveFundingManagerBase
    }

    function testSellOrder_FailsIfBurnAmountExceedsVirtualTokenSupply(
        uint amount
    ) public {
        // Setup
        amount = bound(amount, 100_000_000, 1e38); // see comment in testBuyOrderWithZeroFee
        _token.mint(
            address(bondingCurveFundingManager), (type(uint).max - amount)
        );

        address seller = makeAddr("seller");
        _prepareSellConditions(seller, amount);

        uint userSellAmount = bondingCurveFundingManager.balanceOf(seller);
        vm.assume(userSellAmount > 0); // we discard buy-ins so small they wouldn't cause underflow

        // we set a virtual collateral supply that will not cover the amount to redeem
        vm.prank(owner_address);
        bondingCurveFundingManager.setVirtualTokenSupply(userSellAmount - 1);

        vm.startPrank(seller);
        {
            vm.expectRevert(); //The formula reverts
            bondingCurveFundingManager.sell(userSellAmount, userSellAmount);
        }
        vm.stopPrank();
    }

    function testSellOrder_FailsIfNotEnoughCollateralInContract(uint amount)
        public
    {
        // Setup
        amount = bound(amount, 1, 1e38); // see comment in testBuyOrderWithZeroFee

        address seller = makeAddr("seller");
        _prepareSellConditions(seller, amount);

        // we simulate the fundingManager spending some funds. It can't cover full redemption anymore.
        _token.burn(address(bondingCurveFundingManager), 1);

        vm.startPrank(seller);
        {
            vm.expectRevert(); //The formula reverts
            bondingCurveFundingManager.sell(amount, amount);
        }
        vm.stopPrank();
    }

    function testSellOrderWithZeroFee(uint amountIn) public {
        // Setup

        // For sells, number above 1e26 start reverting!?
        amountIn = bound(amountIn, 1, 1e26); // see comment in testBuyOrderWithZeroFee
        _token.mint(
            address(bondingCurveFundingManager), (type(uint).max - amountIn)
        ); // We mint all the other tokens to the fundingManager to make sure we'll have enough balance to pay out

        address seller = makeAddr("seller");
        _prepareSellConditions(seller, amountIn);

        uint userSellAmount = bondingCurveFundingManager.balanceOf(seller);
        vm.assume(userSellAmount > 0); // we discard buy-ins so small they wouldn't cause underflow

        // Set virtual supply to some number above the sell amount
        // Set virtual collateral to some number
        uint newVirtualTokenSupply = userSellAmount * 2;
        uint newVirtualCollateral = amountIn * 2;
        vm.startPrank(owner_address);
        {
            bondingCurveFundingManager.setVirtualTokenSupply(
                newVirtualTokenSupply
            );
            bondingCurveFundingManager.setVirtualCollateralSupply(
                newVirtualCollateral
            );
        }
        vm.stopPrank();

        // Use formula to get expected return values
        uint formulaReturn = bondingCurveFundingManager.formula()
            .calculateSaleReturn(
            bondingCurveFundingManager.getVirtualTokenSupply(),
            bondingCurveFundingManager.getVirtualCollateralSupply(),
            bondingCurveFundingManager.call_reserveRatioForSelling(),
            userSellAmount
        );

        // Perform the sell
        vm.startPrank(seller);
        {
            vm.expectEmit(true, true, true, true, address(_token));
            emit Transfer(
                address(bondingCurveFundingManager),
                address(seller),
                formulaReturn
            );
            vm.expectEmit(
                true, true, true, true, address(bondingCurveFundingManager)
            );
            emit TokensSold(seller, userSellAmount, formulaReturn, seller);
            vm.expectEmit(
                true, true, true, true, address(bondingCurveFundingManager)
            );
            emit VirtualTokenAmountSubtracted(
                userSellAmount, newVirtualTokenSupply - userSellAmount
            );
            vm.expectEmit(
                true, true, true, true, address(bondingCurveFundingManager)
            );
            emit VirtualCollateralAmountSubtracted(
                formulaReturn, newVirtualCollateral - formulaReturn
            );
            bondingCurveFundingManager.sell(userSellAmount, formulaReturn);
        }
        vm.stopPrank();

        // Check real-world token/collateral balances
        assertEq(bondingCurveFundingManager.balanceOf(seller), 0);
        assertEq(_token.balanceOf(seller), formulaReturn);
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManager)),
            (type(uint).max - formulaReturn)
        );

        // Check virtual token/collateral balances
        assertEq(
            bondingCurveFundingManager.getVirtualTokenSupply(),
            newVirtualTokenSupply - userSellAmount
        );
        assertEq(
            bondingCurveFundingManager.getVirtualCollateralSupply(),
            newVirtualCollateral - formulaReturn
        );
    }

    function testSellOrderWithFee(uint amountIn, uint fee) public {
        // Same as above, but substracting fees when checking actual amounts

        // Setup
        uint _bps = bondingCurveFundingManager.call_BPS();
        fee = bound(fee, 1, _bps);

        //For sells, number above 1e26 start reverting!?
        amountIn = bound(amountIn, 1, 1e26); // see comment in testBuyOrderWithZeroFee
        _token.mint(
            address(bondingCurveFundingManager), (type(uint).max - amountIn)
        ); // We mint all the other tokens to the fundingManager to make sure we'll have enough balance to pay out

        address seller = makeAddr("seller");
        _prepareSellConditions(seller, amountIn);

        uint userSellAmount = bondingCurveFundingManager.balanceOf(seller);
        vm.assume(userSellAmount > 0); // we discard buy-ins so small they wouldn't cause underflow

        // Set sell Fee
        // Set virtual supply to some number above _sellAmount
        // Set virtual collateral to some number
        uint newVirtualTokenSupply = userSellAmount * 2;
        uint newVirtualCollateral = amountIn * 2;
        vm.startPrank(owner_address);
        {
            bondingCurveFundingManager.setSellFee(fee);
            bondingCurveFundingManager.setVirtualTokenSupply(
                newVirtualTokenSupply
            );
            bondingCurveFundingManager.setVirtualCollateralSupply(
                newVirtualCollateral
            );
        }
        vm.stopPrank();

        // Use formula to get expected return values
        uint formulaReturn = bondingCurveFundingManager.formula()
            .calculateSaleReturn(
            bondingCurveFundingManager.getVirtualTokenSupply(),
            bondingCurveFundingManager.getVirtualCollateralSupply(),
            bondingCurveFundingManager.call_reserveRatioForSelling(),
            userSellAmount
        );

        // We calculate how much if the initial deposit we should get back based on the fee
        uint feeAmount =
            (formulaReturn * fee) / bondingCurveFundingManager.call_BPS();
        uint sellAmountMinusFee = formulaReturn - feeAmount;

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
            emit VirtualTokenAmountSubtracted(
                userSellAmount, newVirtualTokenSupply - userSellAmount
            );
            vm.expectEmit(
                true, true, true, true, address(bondingCurveFundingManager)
            );
            emit VirtualCollateralAmountSubtracted(
                sellAmountMinusFee, newVirtualCollateral - sellAmountMinusFee
            );
            bondingCurveFundingManager.sell(userSellAmount, sellAmountMinusFee);
        }
        vm.stopPrank();

        // Check real-world token/collateral balances
        assertEq(bondingCurveFundingManager.balanceOf(seller), 0);
        assertEq(_token.balanceOf(seller), sellAmountMinusFee);
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManager)),
            (type(uint).max - sellAmountMinusFee)
        );

        // Check virtual token/collateral balances
        assertEq(
            bondingCurveFundingManager.getVirtualTokenSupply(),
            newVirtualTokenSupply - userSellAmount
        );
        assertEq(
            bondingCurveFundingManager.getVirtualCollateralSupply(),
            newVirtualCollateral - sellAmountMinusFee
        );
    }

    // test sellFor function
    //  - Both modifiers have been tested in the upstream tests
    //  - Sell order branches are tested in sell tests
    //  - The goal of this test is just to verify that the tokens get sent to a different receiver

    function testSellOrderFor(uint amountIn, address to) public {
        // Setup

        vm.assume(to != address(0));

        // For sells, number above 1e26 start reverting!?
        amountIn = bound(amountIn, 1, 1e26); // see comment in testBuyOrderWithZeroFee
        _token.mint(
            address(bondingCurveFundingManager), (type(uint).max - amountIn)
        ); // We mint all the other tokens to the fundingManager to make sure we'll have enough balance to pay out

        address seller = makeAddr("seller");
        assertNotEq(to, seller);

        _prepareSellConditions(seller, amountIn);

        uint userSellAmount = bondingCurveFundingManager.balanceOf(seller);
        vm.assume(userSellAmount > 0); // we discard buy-ins so small they wouldn't cause underflow

        // Set virtual supply to some number above the sell amount
        // Set virtual collateral to some number
        uint newVirtualTokenSupply = userSellAmount * 2;
        uint newVirtualCollateral = amountIn * 2;
        vm.startPrank(owner_address);
        {
            bondingCurveFundingManager.setVirtualTokenSupply(
                newVirtualTokenSupply
            );
            bondingCurveFundingManager.setVirtualCollateralSupply(
                newVirtualCollateral
            );
        }
        vm.stopPrank();

        // Use formula to get expected return values
        uint formulaReturn = bondingCurveFundingManager.formula()
            .calculateSaleReturn(
            bondingCurveFundingManager.getVirtualTokenSupply(),
            bondingCurveFundingManager.getVirtualCollateralSupply(),
            bondingCurveFundingManager.call_reserveRatioForSelling(),
            userSellAmount
        );

        // Perform the sell
        vm.startPrank(seller);
        {
            bondingCurveFundingManager.sellFor(
                to, userSellAmount, formulaReturn
            );
        }
        vm.stopPrank();

        // Check real-world token/collateral balances
        assertEq(bondingCurveFundingManager.balanceOf(seller), 0);
        assertEq(_token.balanceOf(seller), 0);
        assertEq(_token.balanceOf(to), formulaReturn);
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManager)),
            (type(uint).max - formulaReturn)
        );

        // Check virtual token/collateral balances
        assertEq(
            bondingCurveFundingManager.getVirtualTokenSupply(),
            newVirtualTokenSupply - userSellAmount
        );
        assertEq(
            bondingCurveFundingManager.getVirtualCollateralSupply(),
            newVirtualCollateral - formulaReturn
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

    /* Test getStaticPriceForBuying() */

    function testgetStaticPriceForBuying() public {
        uint returnValue = bondingCurveFundingManager.call_staticPricePPM(
            bondingCurveFundingManager.getVirtualTokenSupply(),
            bondingCurveFundingManager.getVirtualCollateralSupply(),
            bondingCurveFundingManager.call_reserveRatioForBuying()
        );
        assertEq(
            bondingCurveFundingManager.getStaticPriceForBuying(), returnValue
        );
    }
    /* Test getStaticPriceForSelling() */

    function testgetStaticPriceForSelling() public {
        uint returnValue = bondingCurveFundingManager.call_staticPricePPM(
            bondingCurveFundingManager.getVirtualTokenSupply(),
            bondingCurveFundingManager.getVirtualCollateralSupply(),
            bondingCurveFundingManager.call_reserveRatioForBuying()
        );
        assertEq(
            bondingCurveFundingManager.getStaticPriceForSelling(), returnValue
        );
    }

    /* Test calculatePurchaseReturn function
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
            IBancorVirtualSupplyBondingCurveFundingManager
                .BancorVirtualSupplyBondingCurveFundingManager__InvalidDepositAmount
                .selector
        );
        bondingCurveFundingManager.calculatePurchaseReturn(depositAmount);
    }

    function testCalculatePurchaseReturnWithZeroFee(uint _depositAmount)
        public
    {
        // Above an amount of 1e38 the BancorFormula starts to revert.
        _depositAmount = bound(_depositAmount, 1, 1e38);

        // Use formula to get expected return values
        uint formulaReturn = bondingCurveFundingManager.formula()
            .calculatePurchaseReturn(
            bondingCurveFundingManager.getVirtualTokenSupply(),
            bondingCurveFundingManager.getVirtualCollateralSupply(),
            bondingCurveFundingManager.call_reserveRatioForBuying(),
            _depositAmount
        );
        uint functionReturn =
            bondingCurveFundingManager.calculatePurchaseReturn(_depositAmount);
        assertEq(functionReturn, formulaReturn);
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

        // Use formula to get expected return values
        uint formulaReturn = bondingCurveFundingManager.formula()
            .calculatePurchaseReturn(
            bondingCurveFundingManager.getVirtualTokenSupply(),
            bondingCurveFundingManager.getVirtualCollateralSupply(),
            bondingCurveFundingManager.call_reserveRatioForBuying(),
            buyAmountMinusFee
        );
        uint functionReturn =
            bondingCurveFundingManager.calculatePurchaseReturn(_depositAmount);
        assertEq(functionReturn, formulaReturn);
    }

    /* Test calculateSaleReturn function
        ├── When deposit amount is 0
        │       └── it should revert 
        └── When deposit amount is not 0
                ├── when the fee is 0
                │       └── it should succeed 
                └── when the fee is not 0
                        └── it should succeed 
    */

    function testCalculateSaleReturn_FailsIfDepositAmountZero() public {
        uint depositAmount = 0;

        vm.expectRevert(
            IBancorVirtualSupplyBondingCurveFundingManager
                .BancorVirtualSupplyBondingCurveFundingManager__InvalidDepositAmount
                .selector
        );
        bondingCurveFundingManager.calculateSaleReturn(depositAmount);
    }

    function testCalculateSaleReturnWithZeroFee(uint _depositAmount) public {
        // Above an amount of 1e26 the BancorFormula starts to revert.
        _depositAmount = bound(_depositAmount, 1, 1e26);

        // Set virtual supply to some number above collateral supply
        // Set virtual collateral to some number
        uint newVirtualTokenSupply = _depositAmount * 4;
        uint newVirtualCollateral = _depositAmount * 2;
        vm.startPrank(owner_address);
        {
            bondingCurveFundingManager.setVirtualTokenSupply(
                newVirtualTokenSupply
            );
            bondingCurveFundingManager.setVirtualCollateralSupply(
                newVirtualCollateral
            );
        }
        vm.stopPrank();

        // Use formula to get expected return values
        uint formulaReturn = bondingCurveFundingManager.formula()
            .calculateSaleReturn(
            bondingCurveFundingManager.getVirtualTokenSupply(),
            bondingCurveFundingManager.getVirtualCollateralSupply(),
            bondingCurveFundingManager.call_reserveRatioForBuying(),
            _depositAmount
        );
        uint functionReturn =
            bondingCurveFundingManager.calculateSaleReturn(_depositAmount);
        assertEq(functionReturn, formulaReturn);
    }

    function testCalculateSaleReturnWithFee(uint _depositAmount, uint _fee)
        public
    {
        // Setup
        uint _bps = bondingCurveFundingManager.call_BPS();

        _fee = bound(_fee, 1, (_bps - 1)); // 100% buy fees are not allowed.
            // Above an amount of 1e26 the BancorFormula starts to revert.
        _depositAmount = bound(_depositAmount, 1, 1e26);

        // Set sell Fee
        // Set virtual supply to some number above collateral supply
        // Set virtual collateral to some number
        uint newVirtualTokenSupply = _depositAmount * 4;
        uint newVirtualCollateral = _depositAmount * 2;
        vm.startPrank(owner_address);
        {
            bondingCurveFundingManager.setSellFee(_fee);
            bondingCurveFundingManager.setVirtualTokenSupply(
                newVirtualTokenSupply
            );
            bondingCurveFundingManager.setVirtualCollateralSupply(
                newVirtualCollateral
            );
        }
        vm.stopPrank();

        // Use formula to get expected return values
        uint formulaReturn = bondingCurveFundingManager.formula()
            .calculateSaleReturn(
            bondingCurveFundingManager.getVirtualTokenSupply(),
            bondingCurveFundingManager.getVirtualCollateralSupply(),
            bondingCurveFundingManager.call_reserveRatioForSelling(),
            _depositAmount
        );

        // We calculate how much if the initial deposit we should get back based on the fee
        uint feeAmount =
            (formulaReturn * _fee) / bondingCurveFundingManager.call_BPS();
        uint sellAmountMinusFee = formulaReturn - feeAmount;

        uint functionReturn =
            bondingCurveFundingManager.calculateSaleReturn(_depositAmount);

        assertEq(functionReturn, sellAmountMinusFee);
    }

    //--------------------------------------------------------------------------
    // OnlyOrchestrator Functions

    /*   
        Test mintIssuanceTokenTo function
    */
    function testMintIssuanceTokenTo(uint amount)
        public
        callerIsOrchestratorOwner
    {
        assertEq(bondingCurveFundingManager.balanceOf(non_owner_address), 0);

        bondingCurveFundingManager.mintIssuanceTokenTo(
            non_owner_address, amount
        );

        assertEq(
            bondingCurveFundingManager.balanceOf(non_owner_address), amount
        );
    }

    /* Test setVirtualTokenSupply and _setVirtualTokenSupply function
        ├── when caller is not the Orchestrator owner
        │      └── it should revert (tested in base Module tests)
        └── when caller is the Orchestrator owner
                ├── when the new token supply is zero
                │   └── it should revert
                └── when the new token supply is above zero
                    ├── it should set the new token supply
                    └── it should emit an event

    */

    function testSetVirtualTokenSupply_FailsIfZero()
        public
        callerIsOrchestratorOwner
    {
        uint _newSupply = 0;

        vm.expectRevert(
            IVirtualTokenSupply
                .VirtualTokenSupply__VirtualSupplyCannotBeZero
                .selector
        );
        bondingCurveFundingManager.setVirtualTokenSupply(_newSupply);
    }

    function testSetVirtualTokenSupply(uint _newSupply)
        public
        callerIsOrchestratorOwner
    {
        vm.assume(_newSupply != 0);

        vm.expectEmit(
            true, true, false, false, address(bondingCurveFundingManager)
        );
        emit VirtualTokenSupplySet(_newSupply, INITIAL_TOKEN_SUPPLY);
        bondingCurveFundingManager.setVirtualTokenSupply(_newSupply);
        assertEq(bondingCurveFundingManager.getVirtualTokenSupply(), _newSupply);
    }

    /* Test setVirtualCollateralSupply and _ssetVirtualCollateralSupply function
        ├── when caller is not the Orchestrator owner
        │      └── it should revert (tested in base Module tests)
        └── when caller is the Orchestrator owner
                ├── when the new collateral supply is zero
                │   └── it should revert
                └── when the new collateral supply is above zero
                    ├── it should set the new collateral supply
                    └── it should emit an event

    */

    function testSetVirtualCollateralSupply_FailsIfZero()
        public
        callerIsOrchestratorOwner
    {
        uint _newSupply = 0;

        vm.expectRevert(
            IVirtualCollateralSupply
                .VirtualCollateralSupply__VirtualSupplyCannotBeZero
                .selector
        );
        bondingCurveFundingManager.setVirtualCollateralSupply(_newSupply);
    }

    function testSetVirtualCollateralSupply(uint _newSupply)
        public
        callerIsOrchestratorOwner
    {
        vm.assume(_newSupply != 0);

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
        ├── when caller is not the Orchestrator owner
        │       └── it should revert (tested in base Module tests)
        └── when caller is the Orchestrator owner
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
    function testSetReserveRatioForBuying_failsIfRatioIsZero()
        public
        callerIsOrchestratorOwner
    {
        vm.expectRevert(
            IBancorVirtualSupplyBondingCurveFundingManager
                .BancorVirtualSupplyBondingCurveFundingManager__InvalidReserveRatio
                .selector
        );
        bondingCurveFundingManager.setReserveRatioForBuying(0);
    }

    function testSetReserveRatioForBuying_failsIfRatioIsAboveMax(
        uint32 _newRatio
    ) public callerIsOrchestratorOwner {
        vm.assume(_newRatio > bondingCurveFundingManager.call_PPM());
        vm.expectRevert(
            IBancorVirtualSupplyBondingCurveFundingManager
                .BancorVirtualSupplyBondingCurveFundingManager__InvalidReserveRatio
                .selector
        );
        bondingCurveFundingManager.setReserveRatioForBuying(_newRatio);
    }

    function testSetReserveRatioForBuying(uint32 _newRatio)
        public
        callerIsOrchestratorOwner
    {
        //manual bound for uint32
        _newRatio = (_newRatio % bondingCurveFundingManager.call_PPM()) + 1; // reserve ratio of 0% isn't allowed, 100% is (although it isn't really a curve anymore)

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
        ├── when caller is not the Orchestrator owner
        │       └── it should revert (tested in base Module tests)
        └── when caller is the Orchestrator owner
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
    function testSetReserveRatioForSelling_failsIfRatioIsZero()
        public
        callerIsOrchestratorOwner
    {
        vm.expectRevert(
            IBancorVirtualSupplyBondingCurveFundingManager
                .BancorVirtualSupplyBondingCurveFundingManager__InvalidReserveRatio
                .selector
        );
        bondingCurveFundingManager.setReserveRatioForSelling(0);
    }

    function testSetReserveRatioForSelling_failsIfRatioIsAboveMax(
        uint32 _newRatio
    ) public callerIsOrchestratorOwner {
        vm.assume(_newRatio > bondingCurveFundingManager.call_PPM());
        vm.expectRevert(
            IBancorVirtualSupplyBondingCurveFundingManager
                .BancorVirtualSupplyBondingCurveFundingManager__InvalidReserveRatio
                .selector
        );
        bondingCurveFundingManager.setReserveRatioForSelling(_newRatio);
    }

    function testSetReserveRatioForSelling(uint32 _newRatio)
        public
        callerIsOrchestratorOwner
    {
        //manual bound for uint32
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

    /* Test _setDecimals function
        ├── When decimal is set to lower than seven
        |   └── it should revert
        └── when decimal is bequal or bigger than seven
            └── it should succeed
    */
    function testSetDecimals_FailsIfLowerThanSeven(uint8 _newDecimals) public {
        vm.assume(_newDecimals < 7);
        vm.expectRevert(
            IBancorVirtualSupplyBondingCurveFundingManager
                .BancorVirtualSupplyBondingCurveFundingManager__InvalidTokenDecimal
                .selector
        );
        // No authentication since it's an internal function exposed by the mock contract
        bondingCurveFundingManager.call_setDecimals(_newDecimals);
    }

    function testSetDecimals(uint8 _newDecimals) public {
        vm.assume(_newDecimals >= 7);
        // No authentication since it's an internal function exposed by the mock contract
        bondingCurveFundingManager.call_setDecimals(_newDecimals);

        assertEq(bondingCurveFundingManager.decimals(), _newDecimals);
    }

    /* Test _staticPricePPM function
        ├── When calling with reserve ratio for selling without fuzzing
        |   └── it should update return value after selling
        ├── When calling with reserve ratio for selling with fuzzing
        |   └── it should update return value after selling
        ├── When calling with reserve ratio for buying without fuzzing
        |   └── it should update return value after buying
        └── When calling with reserve ratio for buying with fuzzing
            └── it should update return value after buying
    */
    function testStaticPriceWithSellReserveRatioNonFuzzing() public {
        uint amount = 10;
        address seller = makeAddr("seller");
        _prepareSellConditions(seller, amount * 10); // Multiply amount to ensure that user has enough tokens, because return amount when buying less than amount
        // Set virtual supply to some number above _sellAmount
        // Set virtual collateral to some number
        uint newVirtualTokenSupply = amount * 2;
        uint newVirtualCollateral = amount * 2;

        // Set virtual supplies
        vm.startPrank(owner_address);
        {
            bondingCurveFundingManager.setVirtualTokenSupply(
                newVirtualTokenSupply
            );
            bondingCurveFundingManager.setVirtualCollateralSupply(
                newVirtualCollateral
            );
        }
        vm.stopPrank();

        // Calculate min amount out for selling
        uint minAmountOut =
            bondingCurveFundingManager.calculateSaleReturn(amount);

        // Get virtual supplies before selling
        uint _virtualTokenSupplyBeforeSell =
            bondingCurveFundingManager.getVirtualTokenSupply();
        uint _virtualCollateralSupplyBeforeSell =
            bondingCurveFundingManager.getVirtualCollateralSupply();
        uint32 _reserveRatioSelling =
            bondingCurveFundingManager.call_reserveRatioForSelling();

        // Calculate static price before selling
        uint staticPriceBeforeSell = bondingCurveFundingManager
            .call_staticPricePPM(
            _virtualTokenSupplyBeforeSell,
            _virtualCollateralSupplyBeforeSell,
            _reserveRatioSelling
        );

        // Sell tokens
        vm.prank(seller);
        bondingCurveFundingManager.sell(amount, minAmountOut);

        // Get virtual supplies after selling
        uint _virtualTokenSupplyAfterSell =
            bondingCurveFundingManager.getVirtualTokenSupply();
        uint _virtualCollateralSupplyAfterSell =
            bondingCurveFundingManager.getVirtualCollateralSupply();

        // Calculate static price after selling
        uint staticPriceAfterSell = bondingCurveFundingManager
            .call_staticPricePPM(
            _virtualTokenSupplyAfterSell,
            _virtualCollateralSupplyAfterSell,
            _reserveRatioSelling
        );
        // Static price has decreased after sell
        assertLt(staticPriceAfterSell, staticPriceBeforeSell);
    }

    function testStaticPriceWithSellReserveRatioWithFuzzing(
        uint _amount,
        uint _virtualTokenSupply,
        uint _virtualCollateralSupply,
        uint32 _reserveRatioForSelling
    ) public {
        uint amount = bound(_amount, 10, 1e26); // Large enough number to create variation, but not to high that the virtual supplies cause overflows
        address seller = makeAddr("seller");
        // Set virtual supply in range of amount such that the sell amount creates a change in static price.
        // If virtual supplies are to high in relation to sell amount than the static price change will be 0.
        // The lowest value != amount, because this would result in virtual supply being 0, which will revert.
        _virtualTokenSupply =
            bound(_virtualTokenSupply, amount + 1, amount * 10_000);
        _virtualCollateralSupply =
            bound(_virtualCollateralSupply, amount + 1, amount * 10_000);

        // reserve ratio of 0% isn't allowed, 100% is (although it isn't really a curve anymore)
        _reserveRatioForSelling = (
            _reserveRatioForSelling % bondingCurveFundingManager.call_PPM()
        ) + 1;
        _prepareSellConditions(seller, amount * 10);

        // Set virtual supply
        vm.startPrank(owner_address);
        {
            bondingCurveFundingManager.setReserveRatioForSelling(
                _reserveRatioForSelling
            );
            bondingCurveFundingManager.setVirtualTokenSupply(
                _virtualTokenSupply
            );
            bondingCurveFundingManager.setVirtualCollateralSupply(
                _virtualCollateralSupply
            );
        }
        vm.stopPrank();

        // Get minimum amount out for selling
        uint minAmountOut =
            bondingCurveFundingManager.calculateSaleReturn(amount);

        // Calculate static price before sell
        uint staticPriceBeforeSell = bondingCurveFundingManager
            .call_staticPricePPM(
            _virtualTokenSupply,
            _virtualCollateralSupply,
            _reserveRatioForSelling
        );

        // Buy tokens
        vm.prank(seller);
        bondingCurveFundingManager.sell(amount, minAmountOut);

        // Get virtual supply after sell
        uint _virtualTokenSupplyAfterSell =
            bondingCurveFundingManager.getVirtualTokenSupply();
        uint _virtualCollateralSupplyAfterSell =
            bondingCurveFundingManager.getVirtualCollateralSupply();

        // Calculate static price after sell
        uint staticPriceAfterSell = bondingCurveFundingManager
            .call_staticPricePPM(
            _virtualTokenSupplyAfterSell,
            _virtualCollateralSupplyAfterSell,
            _reserveRatioForSelling
        );

        // Static price has decreased after sell
        assertLt(staticPriceAfterSell, staticPriceBeforeSell);
    }

    function testStaticPriceWithBuyReserveRatioNonFuzzing() public {
        uint amount = 1;
        uint minAmountOut =
            bondingCurveFundingManager.calculatePurchaseReturn(amount);
        address buyer = makeAddr("buyer");
        _prepareBuyConditions(buyer, amount);

        // Get virtual supplies before buying
        uint _virtualTokenSupplyBeforeBuy =
            bondingCurveFundingManager.getVirtualTokenSupply();
        uint _virtualCollateralSupplyBeforeBuy =
            bondingCurveFundingManager.getVirtualCollateralSupply();
        uint32 _reserveRatioBuying =
            bondingCurveFundingManager.call_reserveRatioForBuying();
        // Calculate static price before buy
        uint staticPriceBeforeBuy = bondingCurveFundingManager
            .call_staticPricePPM(
            _virtualTokenSupplyBeforeBuy,
            _virtualCollateralSupplyBeforeBuy,
            _reserveRatioBuying
        );
        // Buy tokens
        vm.prank(buyer);
        bondingCurveFundingManager.buy(amount, minAmountOut);

        // Get virtual supply after buy
        uint _virtualTokenSupplyAfterBuy =
            bondingCurveFundingManager.getVirtualTokenSupply();
        uint _virtualCollateralSupplyAfterBuy =
            bondingCurveFundingManager.getVirtualCollateralSupply();
        // Calculate static price after buy
        uint staticPriceAfterBuy = bondingCurveFundingManager
            .call_staticPricePPM(
            _virtualTokenSupplyAfterBuy,
            _virtualCollateralSupplyAfterBuy,
            _reserveRatioBuying
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

    function testStaticPriceWithBuyReserveRatioWithFuzzing(
        uint _amount,
        uint _virtualTokenSupply,
        uint _virtualCollateralSupply,
        uint32 _reserveRatioForBuying
    ) public {
        uint amount = bound(_amount, 10, 1e26); // Large enough number to create variation, but not to high that the virtual supplies cause overflows
        address buyer = makeAddr("buyer");
        // Set virtual supply in range of amount such that the buy amount creates a change in static price.
        // If virtual supplies are to high in relation to buy amount than the static price change will be 0
        _virtualTokenSupply =
            bound(_virtualTokenSupply, amount, amount * 10_000);
        _virtualCollateralSupply =
            bound(_virtualCollateralSupply, amount, amount * 10_000);

        // reserve ratio of 0% isn't allowed, 100% is (although it isn't really a curve anymore)
        _reserveRatioForBuying =
            (_reserveRatioForBuying % bondingCurveFundingManager.call_PPM()) + 1;
        // Prepare buy conditions
        _prepareBuyConditions(buyer, amount);

        // Set virtual supply
        vm.startPrank(owner_address);
        {
            bondingCurveFundingManager.setReserveRatioForBuying(
                _reserveRatioForBuying
            );
            bondingCurveFundingManager.setVirtualTokenSupply(
                _virtualTokenSupply
            );
            bondingCurveFundingManager.setVirtualCollateralSupply(
                _virtualCollateralSupply
            );
        }
        vm.stopPrank();

        // Get minimum amount out for buying
        uint minAmountOut =
            bondingCurveFundingManager.calculatePurchaseReturn(amount);

        // Calculate static price before buy
        uint staticPriceBeforeBuy = bondingCurveFundingManager
            .call_staticPricePPM(
            _virtualTokenSupply,
            _virtualCollateralSupply,
            _reserveRatioForBuying
        );

        // Buy tokens
        vm.prank(buyer);
        bondingCurveFundingManager.buy(amount, minAmountOut);

        // Get virtual supply after buy
        uint _virtualTokenSupplyAfterBuy =
            bondingCurveFundingManager.getVirtualTokenSupply();
        uint _virtualCollateralSupplyAfterBuy =
            bondingCurveFundingManager.getVirtualCollateralSupply();

        // Calculate static price after buy
        uint staticPriceAfterBuy = bondingCurveFundingManager
            .call_staticPricePPM(
            _virtualTokenSupplyAfterBuy,
            _virtualCollateralSupplyAfterBuy,
            _reserveRatioForBuying
        );

        // Static price has increased after buy
        assertGt(staticPriceAfterBuy, staticPriceBeforeBuy);
    }
    /* Test _convertAmountToRequiredDecimal function
        ├── when the token decimals and the required decimals are the same
        │       └── it should return the amount without change
        ├── when the token decimals are higher than the required decimals
        │       └── it should cut the excess decimals from the amount and return it
        └── when caller is the Orchestrator owner
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
        // amount < (1e78 (uint.max) - 1e32 (max decimals in test) - 1e5 (BPS))
        _amount = bound(_amount, 1, 1e41);
        _requiredDecimals = uint8(bound(_requiredDecimals, 1, 18));
        _tokenDecimals = uint8(bound(_tokenDecimals, _requiredDecimals + 1, 32));

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
        // amount < (1e78 (uint.max) - 1e32 (max decimals in test) - 1e5 (BPS))
        _amount = bound(_amount, 1, 1e41);
        _tokenDecimals = uint8(bound(_tokenDecimals, 1, 18));
        _requiredDecimals =
            uint8(bound(_requiredDecimals, _tokenDecimals + 1, 32));

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
        ├── when caller is not the Orchestrator 
        │      └── it should revert (tested in base Module tests)
        └── when caller is the Orchestrator owner
                ├── it should send the funds to the specified address
                └── it should emit an event?
    */

    function testTransferOrchestratorToken(address to, uint amount) public {
        vm.assume(to != address(0));

        _token.mint(address(bondingCurveFundingManager), amount);

        assertEq(_token.balanceOf(to), 0);
        assertEq(_token.balanceOf(address(bondingCurveFundingManager)), amount);

        vm.startPrank(address(_orchestrator));
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

    // Helper function that:
    //      - Mints collateral tokens to a seller and
    //      - Deposits them so they can later be sold.
    //      - Approves the BondingCurve contract to spend the receipt tokens
    // @note This function assumes that we are using the Mock with a 0% buy fee, so the user will receive as many toknes as they deposit
    function _prepareSellConditions(address seller, uint amount) internal {
        _token.mint(seller, amount);
        uint minAmountOut =
            bondingCurveFundingManager.calculatePurchaseReturn(amount);
        vm.startPrank(seller);
        {
            _token.approve(address(bondingCurveFundingManager), amount);
            bondingCurveFundingManager.buy(amount, minAmountOut);
            uint userSellAmount = bondingCurveFundingManager.balanceOf(seller);

            bondingCurveFundingManager.approve(
                address(bondingCurveFundingManager), userSellAmount
            );
        }
        vm.stopPrank();
    }
}
