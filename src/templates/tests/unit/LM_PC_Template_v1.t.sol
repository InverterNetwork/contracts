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
import {
    IERC20PaymentClientBase_v2,
    ERC20PaymentClientBaseV2Mock,
    ERC20Mock
} from "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV2Mock.sol";

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

    function testInit() public override(ModuleTest) {
        assertEq(address(paymentClient.orchestrator()), address(_orchestrator));
        assertEq(paymentClient.getPaymentToken(), address(paymentToken));
    }

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

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        paymentClient.init(_orchestrator, _METADATA, abi.encode(""));
    }

    /* Test: deposit()
        ├── Given the user has a valid amount to deposit
        │   └── When the user deposits the valid amount
        │       ├── Then the deposit balance increases
        │       └── And tokens transfer to the contract
        ├── Given the user attempts to deposit a zero amount
        │   └── When the deposit is attempted
        │       └── Then it reverts with InvalidDepositAmount
        └── Given the user attempts to deposit an amount exceeding the maximum
            └── When the deposit is attempted
                └── Then it reverts with InvalidDepositAmount
    */
    function testDeposit_worksGivenValidAmount() public {
        uint validAmount = 50 ether;

        paymentToken.mint(address(this), validAmount);
        paymentToken.approve(address(paymentClient), validAmount);

        paymentClient.deposit(validAmount);

        assertEq(paymentClient.getDepositedAmount(address(this)), validAmount);
        assertEq(paymentToken.balanceOf(address(paymentClient)), validAmount);
        assertEq(paymentToken.balanceOf(address(this)), 0);
    }

    function testDeposit_revertGivenAmountTooHigh() public {
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

    function testDeposit_revertGivenZeroAmount() public {
        vm.expectRevert(
            ILM_PC_Template_v1
                .Module__LM_PC_Template_InvalidDepositAmount
                .selector
        );
        paymentClient.deposit(0);
    }

    /* Test: processDeposit()
        ├── Given the caller has DEPOSIT_ADMIN_ROLE
        │   └── When the deposit is processed
        │       ├── Then the deposit balance clears
        │       └── And the payment order processes
        └── Given the caller lacks DEPOSIT_ADMIN_ROLE
            └── When the deposit is processed
                └── Then it reverts with CallerNotAuthorized
    */
    function testProcessDeposit_worksGivenAdminRole() public {
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

    function testProcessDeposit_revertGivenNotAdmin() public {
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

    // -------------------------------------------------------------------------
    // Test: Internal Functions

    /* Test: _ensureValidDepositAmount()
        ├── Given the amount is zero
        │   └── When the amount is validated
        │       └── Then it reverts with InvalidDepositAmount
        ├── Given the amount exceeds the maximum
        │   └── When the amount is validated
        │       └── Then it reverts with InvalidDepositAmount
        └── Given the amount is valid
            └── When the amount is validated
                └── Then validation succeeds
    */
    function testEnsureValidDepositAmount_revertGivenZeroAmount() public {
        vm.expectRevert(
            ILM_PC_Template_v1
                .Module__LM_PC_Template_InvalidDepositAmount
                .selector
        );
        paymentClient.exposed_ensureValidDepositAmount(0);
    }

    function testEnsureValidDepositAmount_revertGivenAmountTooHigh() public {
        uint invalidAmount = 101 ether;

        vm.expectRevert(
            ILM_PC_Template_v1
                .Module__LM_PC_Template_InvalidDepositAmount
                .selector
        );
        paymentClient.exposed_ensureValidDepositAmount(invalidAmount);
    }

    /* Test: getDepositedAmount()
        ├── Given the user has no deposits
        │   └── When the deposited amount is queried
        │       └── Then it returns 0
        └── Given the user has deposited
            └── When the deposited amount is queried
                └── Then it returns the deposited amount
    */
    function testGetDepositedAmount_returnsZeroGivenNoDeposits() public {
        address user = makeAddr("user");
        assertEq(paymentClient.getDepositedAmount(user), 0);
    }

    function testGetDepositedAmount_returnsAmountGivenDeposited() public {
        address user = makeAddr("user");
        uint depositAmount = 50 ether;

        vm.startPrank(user);
        paymentToken.mint(user, depositAmount);
        paymentToken.approve(address(paymentClient), depositAmount);
        paymentClient.deposit(depositAmount);
        vm.stopPrank();

        assertEq(paymentClient.getDepositedAmount(user), depositAmount);
    }

    /* Test: getPaymentToken()
        └── When queried
            └── Then it returns the payment token address
    */
    function testGetPaymentToken() public {
        assertEq(paymentClient.getPaymentToken(), address(paymentToken));
    }
}
