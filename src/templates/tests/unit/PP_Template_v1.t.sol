// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Internal
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// External
import {Clones} from "@oz/proxy/Clones.sol";

// Tests and Mocks
import {PP_Template_v1_Exposed} from
    "src/templates/tests/unit/PP_Template_v1_Exposed.sol";
import {
    IERC20PaymentClientBase_v1,
    ERC20PaymentClientBaseV1Mock,
    ERC20Mock
} from "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV1Mock.sol";

// System under Test (SuT)
import {
    IPP_Template_v1,
    IPaymentProcessor_v1
} from "src/templates/modules/PP_Template_v1.sol";

/**
 * @title   Inverter Template Payment Processor Tests
 *
 * @notice  Basic template payment processor used to showcase the unit testing
 *          setup
 *
 * @dev     Not all functions are tested in this template. Placeholders of the
 *          functions that are not tested are added into the contract. This test
 *          showcases the following:
 *          - Inherit from the ModuleTest contract to enable interaction with
 *            the Inverter workflow.
 *          - Showcases the setup of the workflow, uses in test unit tests.
 *          - Pre-defined layout for all setup and functions to be tested.
 *          - Shows the use of Gherkin for documenting the testing. VS Code
 *            extension used for formatting is recommended.
 *          - Shows the use of the modifierInPlace pattern to test the modifier
 *            placement.
 *
 * @author  Inverter Network
 */
contract PP_Template_v1_Test is ModuleTest {
    //--------------------------------------------------------------------------
    // Constants
    uint internal constant _payoutAmountMultiplier = 2;

    //--------------------------------------------------------------------------
    // State

    // System under test (SuT)
    PP_Template_v1_Exposed paymentProcessor;
    // Mocks
    ERC20PaymentClientBaseV1Mock paymentClient;

    //--------------------------------------------------------------------------
    // Setup
    function setUp() public {
        // This function is used to setup the unit test
        // Deploy the SuT
        address impl = address(new PP_Template_v1_Exposed());
        paymentProcessor = PP_Template_v1_Exposed(Clones.clone(impl));

        // Setup the module to test
        _setUpOrchestrator(paymentProcessor);

        // General setup for other contracts in the workflow
        _authorizer.setIsAuthorized(address(this), true);

        // Initiate the PP with the medata and config data
        paymentProcessor.init(
            _orchestrator, _METADATA, abi.encode(_payoutAmountMultiplier)
        );

        // Setup other modules needed in the unit tests.
        // In this case a payment client is needed to test the PP_Template_v1.
        impl = address(new ERC20PaymentClientBaseV1Mock());
        paymentClient = ERC20PaymentClientBaseV1Mock(Clones.clone(impl));
        // Adding the payment client is done through a timelock mechanism
        _orchestrator.initiateAddModuleWithTimelock(address(paymentClient));
        vm.warp(block.timestamp + _orchestrator.MODULE_UPDATE_TIMELOCK());
        _orchestrator.executeAddModule(address(paymentClient));
        // Init payment client
        paymentClient.init(_orchestrator, _METADATA, bytes(""));
        paymentClient.setIsAuthorized(address(paymentProcessor), true);
        paymentClient.setToken(_token);
    }

    //--------------------------------------------------------------------------
    // Test: Initialization

    // Test if the orchestrator is correctly set
    function testInit() public override(ModuleTest) {
        assertEq(
            address(paymentProcessor.orchestrator()), address(_orchestrator)
        );
    }

    // Test the interface support
    function testSupportsInterface() public {
        assertTrue(
            paymentProcessor.supportsInterface(
                type(IPaymentProcessor_v1).interfaceId
            )
        );
        assertTrue(
            paymentProcessor.supportsInterface(
                type(IPP_Template_v1).interfaceId
            )
        );
    }

    // Test the reinit function
    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        paymentProcessor.init(
            _orchestrator, _METADATA, abi.encode(_payoutAmountMultiplier)
        );
    }

    //--------------------------------------------------------------------------
    // Test: Modifiers

    /* Test validClient modifier in place (extensive testing done through internal modifier functions)
        └── Given the modifier is in place
            └── When the function processPayment() is called
                └── Then it should revert
    */
    function testProcessPayments_modifierInPlace() public {
        ERC20PaymentClientBaseV1Mock nonRegisteredClient =
            new ERC20PaymentClientBaseV1Mock();

        vm.expectRevert(
            IPP_Template_v1.Module__PP_Template__ClientNotValid.selector
        );
        paymentProcessor.processPayments(nonRegisteredClient);
    }

    //--------------------------------------------------------------------------
    // Test: External (public & external)

    // Test external processPayments() function

    // Test external cancelRunningPayments() function

    // Test external unclaimable() function

    // Test external claimPreviouslyUnclaimable() function

    // Test external validPaymentOrder() function

    //--------------------------------------------------------------------------
    // Test: Internal (tested through exposed_functions)

    /*  test internal _setPayoutAmountMultiplier()
        ├── Given the newPayoutAmount == 0
        │   └── When the function _setPayoutAmountMultiplier() is called
        │       └── Then it should revert
        └── Given the newPayoutAmount != 0
            └── When the function _setPayoutAmountMultiplier() is called
                └── Then it should emit the event
                    └── And it should set the state correctly
    */

    function testInternalSetPayoutAmountMultiplier_FailsGivenZero() public {
        vm.expectRevert(
            IPP_Template_v1.Module__PP_Template_InvalidAmount.selector
        );
        paymentProcessor.exposed_setPayoutAmountMultiplier(0);
    }

    function testInternalSetPayoutAmountMultiplier_FailsGivenZeroAfter(
        uint newPayoutAmountMultiplier_
    ) public {
        // Set up assumption
        vm.assume(newPayoutAmountMultiplier_ > 0);

        // Check initial state
        assertEq(
            paymentProcessor.getPayoutAmountMultiplier(),
            _payoutAmountMultiplier
        );

        // Test internal function through mock exposed function
        vm.expectEmit(true, true, true, true);
        emit IPP_Template_v1.NewPayoutAmountMultiplierSet(
            _payoutAmountMultiplier, newPayoutAmountMultiplier_
        );
        paymentProcessor.exposed_setPayoutAmountMultiplier(
            newPayoutAmountMultiplier_
        );

        // Test final state
        assertEq(
            paymentProcessor.getPayoutAmountMultiplier(),
            newPayoutAmountMultiplier_
        );
    }

    // Test the internal _validPaymentReceiver() function

    // Test the internal _validClientModifier() function

    //--------------------------------------------------------------------------
    // Helper Functions
}
