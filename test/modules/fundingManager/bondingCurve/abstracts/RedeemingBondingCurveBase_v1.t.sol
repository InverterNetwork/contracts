// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";

import {ERC20Issuance_v1} from "@fm/bondingCurve/tokens/ERC20Issuance_v1.sol";

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

    address owner_address = address(0xA1BA);
    address non_owner_address = address(0xB0B);

    event SellingEnabled();
    event SellingDisabled();
    event SellFeeUpdated(uint indexed newSellFee, uint indexed oldSellFee);
    event TokensSold(
        address indexed receiver,
        uint indexed depositAmount,
        uint indexed receivedAmount,
        address seller
    );

    function setUp() public {
        // Deploy contracts
        address impl = address(new RedeemingBondingCurveBaseV1Mock());

        bondingCurveFundingManager =
            RedeemingBondingCurveBaseV1Mock(Clones.clone(impl));

        formula = address(new BancorFormula());

        issuanceToken = new ERC20Issuance_v1();
        issuanceToken.init(
            NAME,
            SYMBOL,
            DECIMALS,
            type(uint).max,
            address(this),
            address(bondingCurveFundingManager)
        );

        _setUpOrchestrator(bondingCurveFundingManager);

        _authorizer.grantRole(_authorizer.getOwnerRole(), owner_address);

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

    //This function also tests all the getters
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
        vm.prank(owner_address);
        bondingCurveFundingManager.closeSell();

        vm.prank(non_owner_address);
        vm.expectRevert(
            IRedeemingBondingCurveBase_v1
                .Module__RedeemingBondingCurveBase__SellingFunctionaltiesClosed
                .selector
        );
        bondingCurveFundingManager.sellFor(non_owner_address, 100, 100);
    }

    // test modifier on sellFor function

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
        bondingCurveFundingManager.sellFor(receiver, sellAmount, sellAmount);

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
        vm.startPrank(non_owner_address);
        {
            vm.expectRevert(
                IRedeemingBondingCurveBase_v1
                    .Module__RedeemingBondingCurveBase__InvalidDepositAmount
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
            IRedeemingBondingCurveBase_v1
                .Module__RedeemingBondingCurveBase__InsufficientOutputAmount
                .selector
        );
        bondingCurveFundingManager.sell(amount, minAmountOut);
    }

    function testSellOrderWithZeroFee(uint amount) public {
        // Setup
        vm.assume(amount > 0);

        address seller = makeAddr("seller");
        _prepareSellConditions(seller, amount);

        // Pre-checks
        uint bondingCurveCollateralBalanceBefore =
            _token.balanceOf(address(bondingCurveFundingManager));
        uint totalIssuanceSupplyBefore =
            bondingCurveFundingManager.totalSupply();
        assertEq(_token.balanceOf(seller), 0);

        // Emit event
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit TokensSold(seller, amount, amount, seller);

        // Execution
        vm.prank(seller);
        bondingCurveFundingManager.sell(amount, amount);

        // Post-checks
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManager)),
            (bondingCurveCollateralBalanceBefore - amount)
        );
        assertEq(_token.balanceOf(seller), amount);
        assertEq(bondingCurveFundingManager.balanceOf(seller), 0);
        assertEq(
            bondingCurveFundingManager.totalSupply(),
            totalIssuanceSupplyBefore - amount
        );
    }

    function testSellOrderWithFee(uint amount, uint fee) public {
        // Setup
        uint _bps = bondingCurveFundingManager.call_BPS();
        vm.assume(fee < _bps);

        uint maxAmount = type(uint).max / _bps; // to prevent overflows
        amount = bound(amount, 1, maxAmount);

        vm.prank(owner_address);
        bondingCurveFundingManager.setSellFee(fee);
        assertEq(bondingCurveFundingManager.sellFee(), fee);

        address seller = makeAddr("seller");
        _prepareSellConditions(seller, amount);

        // Pre-checks
        uint bondingCurveCollateralBalanceBefore =
            _token.balanceOf(address(bondingCurveFundingManager));
        uint totalIssuanceSupplyBefore =
            bondingCurveFundingManager.totalSupply();
        assertEq(_token.balanceOf(seller), 0);

        // Calculate receive amount
        uint amountMinusFee =
            amount - ((amount * fee) / bondingCurveFundingManager.call_BPS());

        // Emit event
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit TokensSold(seller, amount, amountMinusFee, seller);

        // Execution
        vm.prank(seller);
        bondingCurveFundingManager.sell(amount, amountMinusFee);

        // Post-checks
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManager)),
            (bondingCurveCollateralBalanceBefore - amountMinusFee)
        );
        assertEq(_token.balanceOf(seller), amountMinusFee);
        assertEq(bondingCurveFundingManager.balanceOf(seller), 0);
        assertEq(
            bondingCurveFundingManager.totalSupply(),
            totalIssuanceSupplyBefore - amount
        );
    }

    /* Test openSell and _openSell function
        ├── when caller is not the Orchestrator_v1 owner
        │      └── it should revert (tested in base Module modifier tests)
        └── when caller is the Orchestrator_v1 owner
               └── when sell functionality is already open
                │      └── it should revert
                └── when sell functionality is not open
                        ├── it should open the sell functionality
                        └── it should emit an event
    */
    function testOpenSell_FailsIfAlreadyOpen()
        public
        callerIsOrchestratorOwner
    {
        vm.expectRevert(
            IRedeemingBondingCurveBase_v1
                .Module__RedeemingBondingCurveBase__SellingAlreadyOpen
                .selector
        );
        bondingCurveFundingManager.openSell();
    }

    function testOpenSell() public callerIsOrchestratorOwner {
        assertEq(bondingCurveFundingManager.sellIsOpen(), true);

        bondingCurveFundingManager.closeSell();

        assertEq(bondingCurveFundingManager.sellIsOpen(), false);

        vm.expectEmit(address(bondingCurveFundingManager));
        emit SellingEnabled();

        bondingCurveFundingManager.openSell();

        assertEq(bondingCurveFundingManager.sellIsOpen(), true);
    }

    /* Test closeSell and _closeSell function
        ├── when caller is not the Orchestrator_v1 owner
        │      └── it should revert (tested in base Module tests)
        └── when caller is the Orchestrator_v1 owner
               └── when sell functionality is already closed
                │      └── it should revert -> 
                └── when sell functionality is not closed
                        ├── it should close the sell functionality
                        └── it should emit an event
    */

    function testCloseSell_FailsIfAlreadyClosed()
        public
        callerIsOrchestratorOwner
    {
        bondingCurveFundingManager.closeSell();

        vm.expectRevert(
            IRedeemingBondingCurveBase_v1
                .Module__RedeemingBondingCurveBase__SellingAlreadyClosed
                .selector
        );
        bondingCurveFundingManager.closeSell();
    }

    function testCloseSell() public callerIsOrchestratorOwner {
        assertEq(bondingCurveFundingManager.sellIsOpen(), true);

        vm.expectEmit(address(bondingCurveFundingManager));
        emit SellingDisabled();
        bondingCurveFundingManager.closeSell();

        assertEq(bondingCurveFundingManager.sellIsOpen(), false);
    }

    /* Test setSellFee and _setSellFee function
        ├── when caller is not the Orchestrator_v1 owner
        │      └── it should revert (tested in base Module tests)
        └── when caller is the Orchestrator_v1 owner
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
        callerIsOrchestratorOwner
    {
        vm.assume(_fee > bondingCurveFundingManager.call_BPS());
        vm.expectRevert(
            IRedeemingBondingCurveBase_v1
                .Module__RedeemingBondingCurveBase__InvalidFeePercentage
                .selector
        );
        bondingCurveFundingManager.setSellFee(_fee);
    }

    function testSetSellFee(uint _fee) public callerIsOrchestratorOwner {
        vm.assume(_fee <= bondingCurveFundingManager.call_BPS());

        uint oldSellFee = bondingCurveFundingManager.sellFee();

        vm.expectEmit(
            true, true, false, false, address(bondingCurveFundingManager)
        );
        emit SellFeeUpdated(_fee, oldSellFee);
        bondingCurveFundingManager.setSellFee(_fee);

        assertEq(bondingCurveFundingManager.sellFee(), _fee);
    }

    //--------------------------------------------------------------------------
    // Helper functions

    // Modifier to ensure the caller has the owner role
    modifier callerIsOrchestratorOwner() {
        _authorizer.grantRole(_authorizer.getOwnerRole(), owner_address);
        vm.startPrank(owner_address);
        _;
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
            _token.approve(address(bondingCurveFundingManager), amount);
            bondingCurveFundingManager.buy(amount, amount);

            issuanceToken.approve(address(bondingCurveFundingManager), amount);
        }
        vm.stopPrank();
    }
}
