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
    RedeemingBondingCurveFundingManagerMock,
    IRedeemingBondingCurveFundingManagerBase
} from
    "test/modules/fundingManager/bondingCurveFundingManager/marketMaker/utils/mocks/RedeemingBondingCurveFundingManagerMock.sol";

contract RedeemingBondingCurveFundingManagerBaseTest is ModuleTest {
    string private constant NAME = "Bonding Curve Token";
    string private constant SYMBOL = "BCT";
    uint8 private constant DECIMALS = 18;
    uint private constant BUY_FEE = 0;
    uint private constant SELL_FEE = 0;
    bool private constant BUY_IS_OPEN = true;
    bool private constant SELL_IS_OPEN = true;

    RedeemingBondingCurveFundingManagerMock bondingCurveFundingManger;
    address formula;

    address owner_address = address(0xA1BA);
    address non_owner_address = address(0xB0B);

    function setUp() public {
        // Deploy contracts
        address impl = address(new RedeemingBondingCurveFundingManagerMock());

        bondingCurveFundingManger =
            RedeemingBondingCurveFundingManagerMock(Clones.clone(impl));

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

    /* Test sellingIsEnabled modifier
        ├── when sell is not open
        │       └── it should revert
        └── when sell is open
                └── it should not revert (tested in sellOrder tests)

    */
    function testSellingIsEnabled_FailsIfSellNotOpen() public {
        vm.prank(owner_address);
        bondingCurveFundingManger.closeSell();

        vm.prank(non_owner_address);
        vm.expectRevert(
            IRedeemingBondingCurveFundingManagerBase
                .RedeemingBondingCurveFundingManager__SellingFunctionaltiesClosed
                .selector
        );
        bondingCurveFundingManger.sellOrderFor(non_owner_address, 100);
    }

    // test modifier on sellOrderFor function

    function testPassingModifiersOnSellOrderFor(uint sellAmount) public {
        // Setup
        vm.assume(sellAmount > 0);

        address seller = makeAddr("seller");
        address receiver = makeAddr("receiver");

        _prepareSellConditions(seller, sellAmount);

        // Pre-checks
        uint bondingCurveBalanceBefore =
            _token.balanceOf(address(bondingCurveFundingManger));
        uint receiverBalanceBefore = _token.balanceOf(receiver);
        assertEq(_token.balanceOf(seller), 0);
        assertEq(_token.balanceOf(receiver), 0);
        assertEq(bondingCurveFundingManger.balanceOf(seller), sellAmount);

        // Execution
        vm.prank(seller);
        bondingCurveFundingManger.sellOrderFor(receiver, sellAmount);

        // Post-checks
        uint redeemAmount = _token.balanceOf(receiver) - receiverBalanceBefore;
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManger)),
            (bondingCurveBalanceBefore - redeemAmount)
        );
        assertEq(bondingCurveFundingManger.balanceOf(seller), 0);
        assertEq(_token.balanceOf(seller), 0);
    }

    /* Test sellOrder and _sellOrder function
        ├── when the sell amount is 0
        │       └── it should revert 
        └── when the sell amount is not 0
                ├── when the fee is higher than 0
                │       └── it should substract the fee from the reddemed amount
                │               ├── it should take the sell amount from the caller
                │               ├── it should determine the redeem amount of the sent tokens 
                │               ├── it should substract the fee from the redeem amount
                │               ├── it should send the rest to the receiver    
                │               └── it should emit an event? @todo
                └── when the fee is 0
                                ├── it should take the sell amount from the caller
                                ├── it should determine the redeem amount of the sent tokens 
                                ├── it should send the rest to the receiver    
                                └── it should emit an event? @todo
    */

    function testSellOrder_FailsIfDepositAmountIsZero() public {
        vm.startPrank(non_owner_address);

        vm.expectRevert(
            IRedeemingBondingCurveFundingManagerBase
                .RedeemingBondingCurveFundingManager__InvalidDepositAmount
                .selector
        );
        bondingCurveFundingManger.sellOrder(0);
    }

    function testSellOrderWithZeroFee(uint amount) public {
        // Setup
        vm.assume(amount > 0);

        address seller = makeAddr("seller");
        _prepareSellConditions(seller, amount);

        // Pre-checks
        uint bondingCurveCollateralBalanceBefore =
            _token.balanceOf(address(bondingCurveFundingManger));
        assertEq(_token.balanceOf(seller), 0);
        //uint userTokenBalanceBefore = bondingCurveFundingManger.balanceOf(seller);

        // Execution
        vm.prank(seller);
        bondingCurveFundingManger.sellOrder(amount);

        // Post-checks
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManger)),
            (bondingCurveCollateralBalanceBefore - amount)
        );
        assertEq(_token.balanceOf(seller), amount);
        assertEq(bondingCurveFundingManger.balanceOf(seller), 0);
    }

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

    /* Test openSell and _openSell function
        ├── when caller is not the Orchestrator owner
        │      └── it should revert (tested in base Module modifier tests)
        └── when caller is the Orchestrator owner
               └── when sell functionality is already open
                │      └── it should revert  -> sure? idempotence @review
                └── when sell functionality is not open
                        ├── it should open the sell functionality
                        └── it should emit an event? @todo
    */
    function testOpenSell_FailsIfAlreadyOpen()
        public
        callerIsOrchestratorOwner
    {
        vm.expectRevert(
            IRedeemingBondingCurveFundingManagerBase
                .RedeemingBondingCurveFundingManager__SellingAlreadyOpen
                .selector
        );
        bondingCurveFundingManger.openSell();
    }

    function testOpenSell() public callerIsOrchestratorOwner {
        assertEq(bondingCurveFundingManger.sellIsOpen(), true);

        bondingCurveFundingManger.closeSell();

        assertEq(bondingCurveFundingManger.sellIsOpen(), false);

        bondingCurveFundingManger.openSell();

        assertEq(bondingCurveFundingManger.sellIsOpen(), true);
    }

    /* Test closeSell and _closeSell function
        ├── when caller is not the Orchestrator owner
        │      └── it should revert (tested in base Module tests)
        └── when caller is the Orchestrator owner
               └── when sell functionality is already closed
                │      └── it should revert ->  sure? idempotence @review
                └── when sell functionality is not closed
                        ├── it should close the sell functionality
                        └── it should emit an event? @todo
    */

    function testCloseSell_FailsIfAlreadyClosed()
        public
        callerIsOrchestratorOwner
    {
        bondingCurveFundingManger.closeSell();

        vm.expectRevert(
            IRedeemingBondingCurveFundingManagerBase
                .RedeemingBondingCurveFundingManager__SellingAlreadyClosed
                .selector
        );
        bondingCurveFundingManger.closeSell();
    }

    function testCloseSell() public callerIsOrchestratorOwner {
        assertEq(bondingCurveFundingManger.sellIsOpen(), true);

        bondingCurveFundingManger.closeSell();

        assertEq(bondingCurveFundingManger.sellIsOpen(), false);
    }

    /* Test setSellFee and _setSellFee function
        ├── when caller is not the Orchestrator owner
        │      └── it should revert (tested in base Module tests)
        └── when caller is the Orchestrator owner
               └── when fee is over 100% 
                │      └── it should revert
                ├── when fee is  100% 
                │       ├── it should set the new fee (it's basically a burn function))
                │       └── it should emit an event? @todo
                └── when fee is below 100%
                        ├── it should set the new fee
                        └── it should emit an event? @todo
    */

    function testSetSellFee_FailsIfFeeIsOver100Percent(uint _fee)
        public
        callerIsOrchestratorOwner
    {
        vm.assume(_fee > bondingCurveFundingManger.call_BPS());
        vm.expectRevert(
            IRedeemingBondingCurveFundingManagerBase
                .RedeemingBondingCurveFundingManager__InvalidFeePercentage
                .selector
        );
        bondingCurveFundingManger.setSellFee(_fee);
    }

    function testSetSellFee(uint _fee) public callerIsOrchestratorOwner {
        vm.assume(_fee <= bondingCurveFundingManger.call_BPS());

        bondingCurveFundingManger.setSellFee(_fee);

        assertEq(bondingCurveFundingManger.sellFee(), _fee);
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
            _token.approve(address(bondingCurveFundingManger), amount);
            bondingCurveFundingManger.buyOrder(amount);

            bondingCurveFundingManger.approve(
                address(bondingCurveFundingManger), amount
            );
        }
        vm.stopPrank();
    }
}
