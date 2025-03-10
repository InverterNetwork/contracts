// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Internal
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";
import {OZErrors} from "test/utils/errors/OZErrors.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

// External
import {Clones} from "@oz/proxy/Clones.sol";

// Tests and Mocks
import {LM_PC_Template_v1_Exposed} from
    "src/templates/tests/unit/LM_PC_Template_v1_Exposed.sol";
import {
    IERC20PaymentClientBase_v2,
    ERC20PaymentClientBaseV2Mock,
    ERC20Mock
} from "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV2Mock.sol";

// System under Test (SuT)
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
    }

    // -------------------------------------------------------------------------
    // Test: Initialization

    // Test if the orchestrator is correctly set
    function testInit() public override(ModuleTest) {
        assertEq(address(paymentClient.orchestrator()), address(_orchestrator));
    }

    // Test the interface support
    function testSupportsInterface() public {
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

    // Test the reinit function
    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        paymentClient.init(_orchestrator, _METADATA, abi.encode(""));
    }

    /* Test external deposit function
        ├── Given valid deposit amount
        │   └── When user deposits tokens
        │       ├── Then their deposit balance should increase
        │       └── Then tokens should be transferred to contract
        └── Given invalid deposit amount
            └── When user tries to deposit > maxDepositAmount
                └── Then it should revert with InvalidDepositAmount
    */
    function testDeposit() public {
        uint validAmount = 50 ether;
        
        paymentToken.mint(address(this), validAmount);
        paymentToken.approve(address(paymentClient), validAmount);

        paymentClient.deposit(validAmount);

        assertEq(paymentClient.getDepositedAmount(address(this)), validAmount);
        assertEq(paymentToken.balanceOf(address(paymentClient)), validAmount);
        assertEq(paymentToken.balanceOf(address(this)), 0);
    }

    function testDeposit_modifierInPlace() public {
        uint invalidAmount = 101 ether;

        paymentToken.mint(address(this), invalidAmount);
        paymentToken.approve(address(paymentClient), invalidAmount);

        vm.expectRevert(
            ILM_PC_Template_v1
                .Module__LM_PC_Template_InvalidDepositAmount
                .selector
        );
        paymentClient.deposit(invalidAmount);
    }

    /* Test external processDeposit function
        ├── Given caller has DEPOSIT_ADMIN_ROLE
        │   └── When processing a user's deposit
        │       ├── Then their deposit balance should be cleared
        │       └── Then a payment order should be created and processed
        └── Given caller doesn't have DEPOSIT_ADMIN_ROLE 
            └── When trying to process a deposit
                └── Then it should revert with CallerNotAuthorized (Modifier in place)
    */

    function testProcessDeposit() public {
        paymentClient.grantModuleRole(
            paymentClient.DEPOSIT_ADMIN_ROLE(), address(this)
        );

        address user = makeAddr("user");
        uint depositAmount = 50 ether;

        paymentToken.mint(user, depositAmount);
        vm.prank(user);
        paymentToken.approve(address(paymentClient), depositAmount);

        vm.prank(user);
        paymentClient.deposit(depositAmount);

        paymentClient.processDeposit(user);

        assertEq(paymentClient.getDepositedAmount(user), 0);
    }

    function testProcessDeposit_modifierInPlace() public {
        address user = makeAddr("user");
        uint depositAmount = 50 ether;
        vm.startPrank(user);
        paymentToken.mint(user, depositAmount);
        paymentToken.approve(address(paymentClient), depositAmount);

        paymentClient.deposit(depositAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                _orchestrator.authorizer().generateRoleId(
                    address(paymentClient), paymentClient.DEPOSIT_ADMIN_ROLE()
                ),
                user
            )
        );
        paymentClient.processDeposit(user);

        vm.stopPrank();
    }

    // Test external getDepositedAmount function

    // -------------------------------------------------------------------------
    // Test: Internal (tested through exposed_ functions)

    /* Test internal _ensureValidDepositAmount()
        ├── Given amount <= maxDepositAmount
        │   └── When validating the amount
        │       └── Then it should not revert (not done here)
        └── Given amount > maxDepositAmount
            └── When validating the amount
                └── Then it should revert with InvalidDepositAmount
    */
    function testEnsureValidDepositAmount_revertsWhenAmountTooHigh() public {
        uint invalidAmount = 101 ether;

        vm.expectRevert(
            ILM_PC_Template_v1
                .Module__LM_PC_Template_InvalidDepositAmount
                .selector
        );
        paymentClient.exposed_ensureValidDepositAmount(invalidAmount);
    }
}
