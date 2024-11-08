// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Internal
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";
import {OZErrors} from "test/utils/errors/OZErrors.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";

// External
import {Clones} from "@oz/proxy/Clones.sol";

// Tests and Mocks
import {FM_Template_v1_Exposed} from
    "src/templates/tests/unit/FM_Template_v1_Exposed.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {
    IERC20PaymentClientBase_v1,
    ERC20PaymentClientBaseV1Mock
} from "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV1Mock.sol";

// System under Test (SuT)
import {IFM_Template_v1} from "src/templates/modules/IFM_Template_v1.sol";

/**
 * @title   Inverter Template Funding Manager Tests
 *
 * @notice  Basic template funding manager used to showcase the unit testing
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
contract FM_Template_v1_Test is ModuleTest {
    // =========================================================================
    // Constants

    // =========================================================================
    // State
    FM_Template_v1_Exposed fundingManager;

    // Mocks
    ERC20Mock orchestratorToken;
    ERC20PaymentClientBaseV1Mock paymentClient;

    // =========================================================================
    // Setup
    function setUp() public {
        // This function is used to setup the unit test
        // Deploy the SuT
        address impl = address(new FM_Template_v1_Exposed());
        fundingManager = FM_Template_v1_Exposed(Clones.clone(impl));

        orchestratorToken = new ERC20Mock("Orchestrator Token", "OTK");

        // Setup the module to test
        _setUpOrchestrator(fundingManager);

        // General setup for other contracts in the workflow
        _authorizer.setIsAuthorized(address(this), true);

        // Initialize the funding manager with metadata and config data
        fundingManager.init(
            _orchestrator, _METADATA, abi.encode(address(orchestratorToken))
        );

        // Setup other modules needed in the unit tests.
        // In this case a payment client is needed to test the FM_Template_v1.
        paymentClient = new ERC20PaymentClientBaseV1Mock();
        _addLogicModuleToOrchestrator(address(paymentClient));
    }

    // =========================================================================
    // Test: Initialization

    // Test if the orchestrator is correctly set up after initialization
    function testInit() public override(ModuleTest) {
        assertEq(address(fundingManager.orchestrator()), address(_orchestrator));
    }

    // Test the reinit function
    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        fundingManager.init(
            _orchestrator, _METADATA, abi.encode(address(orchestratorToken))
        );
    }

    // Test the interface support
    function testSupportsInterface() public {
        assertTrue(
            fundingManager.supportsInterface(
                type(IFundingManager_v1).interfaceId
            )
        );
        assertTrue(
            fundingManager.supportsInterface(type(IFM_Template_v1).interfaceId)
        );
    }

    // =========================================================================
    // Test: External (public & external) functions

    // Test external deposit function

    // Test external transferOrchestratorToken function

    // Test external getDepositedAmount function

    // Test external token function

    // =========================================================================
    // Test: Internal (tested through exposed_ functions)

    /* test internal _validateOrchestratorTokenTransfer()
        ├── Given zero address receipent
        │   └── When the function is called with zero address receipent
        │       └── Then the function should revert with Module__FM_Template__ReceiverNotValid error
        ├── Given zero amount
        │   └── When the function is called with zero amount
        │       └── Then the function should revert with Module__FM_Template__AmountNotValid error
        └── Given valid receipent and amount but not enough balance
            └── When the function is called with valid receipent and amount but not enough balance
                └── Then the function should revert with Module__FM_Template_InvalidAmount error
    */
    function testInternalValidateOrchestratorTokenTransfer_FailsZeroAddressReceipent(
    ) public {
        vm.expectRevert(
            IFM_Template_v1.Module__FM_Template__ReceiverNotValid.selector
        );
        fundingManager.exposed_validateOrchestratorTokenTransfer(
            address(0), 1e18
        );
    }

    function testInternalValidateOrchestratorTokenTransfer_FailsZeroAmount()
        public
    {
        vm.expectRevert(
            IFM_Template_v1.Module__FM_Template_InvalidAmount.selector
        );
        fundingManager.exposed_validateOrchestratorTokenTransfer(
            address(this), 0
        );
    }

    function testInternalValidateOrchestratorTokenTransfer_FailsNotEnoughBalance(
    ) public {
        orchestratorToken.mint(address(1), 1 ether);

        vm.startPrank(address(1));
        {
            orchestratorToken.approve(address(fundingManager), 1 ether);
            fundingManager.deposit(1 ether);
        }
        vm.stopPrank();

        vm.expectRevert(
            IFM_Template_v1.Module__FM_Template_InvalidAmount.selector
        );
        fundingManager.exposed_validateOrchestratorTokenTransfer(
            address(1), 10 ether
        );
    }
}
