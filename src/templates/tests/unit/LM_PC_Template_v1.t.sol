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

contract LM_PC_Template_v1_Test is ModuleTest {
    // SuT
    LM_PC_Template_v1_Exposed paymentClient;

    // Mocks
    ERC20Mock paymentToken;

    //--------------------------------------------------------------------------
    // Setup
    function setUp() public {
        // Setup the payment token
        paymentToken = new ERC20Mock("Payment Token", "PT");

        // This function is used to setup the unit test
        // Deploy the SuT
        address impl = address(new LM_PC_Template_v1_Exposed());
        paymentClient = LM_PC_Template_v1_Exposed(Clones.clone(impl));

        // Setup the module to test
        _setUpOrchestrator(paymentClient);

        // Initiate the PP with the medata and config data
        paymentClient.init(
            _orchestrator, _METADATA, abi.encode(address(paymentToken))
        );
    }

    //--------------------------------------------------------------------------
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

    //--------------------------------------------------------------------------
    // Test: Modifiers

    /* Test validDepositAmount modifier in place (extensive testing done through internal modifier functions)
        └── Given the modifier is in place
            └── When the function deposit() is called with amount > 100 ether
                └── Then it should revert
    */
    function testDeposit_modifierInPlace() public {
        uint invalidAmount = 101 ether;

        // Mint tokens to test address
        paymentToken.mint(address(this), invalidAmount);
        // Approve payment client to spend tokens
        paymentToken.approve(address(paymentClient), invalidAmount);

        vm.expectRevert(
            ILM_PC_Template_v1
                .Module__LM_PC_Template_InvalidDepositAmount
                .selector
        );
        paymentClient.deposit(invalidAmount);
    }

    function testProcessDeposit() public {
        // Grant DEPOSIT_ADMIN_ROLE to this test contract
        bytes32 roleId = _authorizer.generateRoleId(
            address(paymentClient),
            paymentClient.DEPOSIT_ADMIN_ROLE()
        );
        _authorizer.grantRole(roleId, address(this));

        // Setup
        address user = makeAddr("user");
        uint depositAmount = 50 ether;
        
        // Mint and approve tokens
        paymentToken.mint(user, depositAmount);
        vm.prank(user);
        paymentToken.approve(address(paymentClient), depositAmount);
        
        // Make deposit
        vm.prank(user);
        paymentClient.deposit(depositAmount);
        
        // Process deposit (no need for vm.prank since test contract has the role)
        paymentClient.processDeposit(user);
        
        // Verify deposit was processed
        assertEq(paymentClient.getDepositedAmount(user), 0);
    }
}
