// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Internal
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "@unit/modules/ModuleTest.sol";
import {OZErrors} from "@tool/OZErrors.sol";
import {ERC20Mock} from "@mock/external/token/ERC20Mock.sol";

// External
import {Clones} from "@oz/proxy/Clones.sol";

// Tests and Mocks
import {
    IERC20PaymentClientBase_v2,
    ERC20PaymentClientBaseV2Mock,
    ERC20Mock
} from "@mock/modules/paymentClient/ERC20PaymentClientBaseV2Mock.sol";

// System under Test (SuT)
import {LM_PC_Template_v1_Exposed} from
    "src/templates/tests/unit/LM_PC_Template_v1_Exposed.sol";
import {ILM_PC_Template_v1} from "src/templates/modules/ILM_PC_Template_v1.sol";

/**
 * @title   Inverter Template Logic Module Payment Client Tests
 *
 * @notice  Tests for the template logic module payment client
 *
 * @dev     This test contract follows the standard testing pattern showing:
 *          - Initialization tests
 *          - External function tests
 *          - Internal function tests through exposed functions
 *          - Use of Gherkin for test documentation
 *
 * @author  Inverter Network
 */
contract LM_PC_Template_v1_Test is ModuleTest {
    // -------------------------------------------------------------------------
    // Constants

    bytes32 internal constant DEPOSIT_ADMIN_ROLE = "DEPOSIT_ADMIN";
    uint internal constant MAX_DEPOSIT_AMOUNT = 100 ether;

    // -------------------------------------------------------------------------
    // State

    // SuT
    LM_PC_Template_v1_Exposed paymentClient;

    // Mocks
    ERC20Mock paymentToken;

    // -------------------------------------------------------------------------
    // Setup

    function setUp() public {
        // Setup the payment token
        paymentToken = new ERC20Mock("Payment Token", "PT");

        // Deploy the SuT
        address impl = address(new LM_PC_Template_v1_Exposed());
        paymentClient = LM_PC_Template_v1_Exposed(Clones.clone(impl));

        // Setup the module to test
        _setUpOrchestrator(paymentClient);

        // Initiate the Logic Module with the metadata and config data
        paymentClient.init(
            _orchestrator, _METADATA, abi.encode(address(paymentToken))
        );

        // Every caller has permission for every premissioned function
        _authorizer.setAllAuthorized(true);
    }

    // -------------------------------------------------------------------------
    // Test: Initialization

    function testInit() public override(ModuleTest) {
        assertEq(address(paymentClient.orchestrator()), address(_orchestrator));
        assertEq(paymentClient.getPaymentToken(), address(paymentToken));
    }

    function testSupportsInterface() public override(ModuleTest) {
        assertTrue(
            paymentClient.supportsInterface(
                type(IERC20PaymentClientBase_v2).interfaceId
            )
        );
        assertTrue(
            paymentClient.supportsInterface(
                type(ILM_PC_Template_v1).interfaceId
            )
        );
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        paymentClient.init(_orchestrator, _METADATA, abi.encode(""));
    }

    // -------------------------------------------------------------------------
    // Test External (public + external)

    /* Test: deposit()
        ├── Given the user has a valid amount to deposit
        │   └── When the function deposit() is called
        │       ├── Then the deposit balance increases
        │       └── And tokens transfer to the contract
        ├── Given the user attempts to deposit a zero amount
        │   └── When the function deposit() is called
        │       └── Then it reverts with InvalidDepositAmount
        └── Given the user attempts to deposit an amount exceeding the maximum
            └── When the function deposit() is called
                └── Then it reverts with InvalidDepositAmount
    */
    function testDeposit_worksGivenValidAmount(uint validAmount_) public {
        // Setup
        validAmount_ =
            bound(validAmount_, 1, paymentClient.getMaxDepositAmount());
        paymentToken.mint(address(this), validAmount_);
        paymentToken.approve(address(paymentClient), validAmount_);

        // Test
        paymentClient.deposit(validAmount_);

        // Assert
        assertEq(paymentClient.getDepositedAmount(address(this)), validAmount_);
        assertEq(paymentToken.balanceOf(address(paymentClient)), validAmount_);
        assertEq(paymentToken.balanceOf(address(this)), 0);
    }

    function testDeposit_revertGivenAmountTooHigh(uint invalidAmount_) public {
        // Setup
        vm.assume(invalidAmount_ > paymentClient.getMaxDepositAmount());
        paymentToken.mint(address(this), invalidAmount_);
        paymentToken.approve(address(paymentClient), invalidAmount_);

        // Test
        vm.expectRevert(
            ILM_PC_Template_v1
                .Module__LM_PC_Template_InvalidDepositAmount
                .selector
        );
        paymentClient.deposit(invalidAmount_);
    }

    function testDeposit_revertGivenZeroAmount() public {
        // Test
        vm.expectRevert(
            ILM_PC_Template_v1
                .Module__LM_PC_Template_InvalidDepositAmount
                .selector
        );
        paymentClient.deposit(0);
    }

    /* Test: processDeposit()
        ├── Given the caller is not permissioned
        │   └── When the function processDeposit() is called
        │       └── Then it reverts (modifier in place)
        └── Given the caller is permissioned
            └── When the function processDeposit() is called
                ├── Then the deposit balance clears
                └── And the payment order processes

    */

    function testBuyFor_ModifierInPositionChecks() public {
        // permissioned

        // Turn off all adresses are permissioned to call all functions
        _authorizer.setAllAuthorized(false);
        vm.expectRevert(
            abi.encodeWithSelector(IModule_v1.Module__NotPermissioned.selector)
        );
        vm.prank(address(0xB0B));
        paymentClient.processDeposit(address(0), 0, 0, 0);
    }

    function testProcessDeposit_worksGivenDepositIsProcessed(
        uint depositAmount_
    ) public {
        // Setup
        depositAmount_ =
            bound(depositAmount_, 1, paymentClient.getMaxDepositAmount());

        paymentToken.mint(address(this), depositAmount_);
        paymentToken.approve(address(paymentClient), depositAmount_);

        uint start = block.timestamp;
        uint cliff = block.timestamp + 30 days;
        uint end = block.timestamp + 90 days;

        paymentClient.deposit(depositAmount_);

        // Test
        paymentClient.processDeposit(address(this), start, cliff, end);

        // Assert
        assertEq(paymentClient.getDepositedAmount(address(this)), 0);
    }

    /* Test: getDepositedAmount()
        ├── Given the user has no deposits
        │   └── When the function getDepositAmount() is called
        │       └── Then it returns 0
        └── Given the user has deposited
            └── When the function getDepositAmount() is called
                └── Then it returns the deposited amount
    */

    function testGetDepositedAmount_worksGivenReturnValueIsZero(address user_)
        public
    {
        vm.assume(user_ != address(0));
        assertEq(paymentClient.getDepositedAmount(user_), 0);
    }

    function testGetDepositedAmount_worksGivenReturnValueIsAmountDeposited(
        address user_,
        uint depositAmount_
    ) public {
        vm.assume(user_ != address(0));
        depositAmount_ =
            bound(depositAmount_, 1, paymentClient.getMaxDepositAmount());

        vm.startPrank(user_);
        paymentToken.mint(user_, depositAmount_);
        paymentToken.approve(address(paymentClient), depositAmount_);
        paymentClient.deposit(depositAmount_);
        vm.stopPrank();

        assertEq(paymentClient.getDepositedAmount(user_), depositAmount_);
    }

    /* Test: getPaymentToken()
        └── When the function getPaymentToken() is called
            └── Then it returns the payment token address
    */
    function testGetPaymentToken() public {
        assertEq(paymentClient.getPaymentToken(), address(paymentToken));
    }

    /* Test: getMaxDepositAmount()
        └── When the function getMaxDepositAmount() is called
            └── Then it returns the maximum deposit amount
    */
    function testGetMaxDepositAmount() public {
        assertEq(paymentClient.getMaxDepositAmount(), MAX_DEPOSIT_AMOUNT);
    }

    // -------------------------------------------------------------------------
    // Test: Internal Functions

    /* Test: _ensureValidDepositAmount()
        ├── Given the amount is zero
        │   └── When the function _ensureValidDepositAmount() is called
        │       └── Then it reverts with InvalidDepositAmount
        └──  Given the amount exceeds the maximum
            └── When the function _ensureValidDepositAmount() is called
                └── Then it reverts with InvalidDepositAmount
    */
    function testInternalEnsureValidDepositAmount_revertGivenZeroAmount()
        public
    {
        vm.expectRevert(
            ILM_PC_Template_v1
                .Module__LM_PC_Template_InvalidDepositAmount
                .selector
        );
        paymentClient.exposed_ensureValidDepositAmount(0);
    }

    function testInternalEnsureValidDepositAmount_revertGivenAmountTooHigh(
        uint invalidAmount_
    ) public {
        vm.assume(invalidAmount_ > paymentClient.getMaxDepositAmount());

        vm.expectRevert(
            ILM_PC_Template_v1
                .Module__LM_PC_Template_InvalidDepositAmount
                .selector
        );
        paymentClient.exposed_ensureValidDepositAmount(invalidAmount_);
    }
}
