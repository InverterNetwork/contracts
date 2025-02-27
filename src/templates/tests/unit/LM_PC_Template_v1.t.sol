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

    //--------------------------------------------------------------------------
    // Setup
    function setUp() public {
        // This function is used to setup the unit test
        // Deploy the SuT
        address impl = address(new LM_PC_Template_v1_Exposed());
        paymentClient = LM_PC_Template_v1_Exposed(Clones.clone(impl));

        // Setup the module to test
        _setUpOrchestrator(paymentClient);

        // Initiate the PP with the medata and config data
        paymentClient.init(_orchestrator, _METADATA, abi.encode(""));
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
}
