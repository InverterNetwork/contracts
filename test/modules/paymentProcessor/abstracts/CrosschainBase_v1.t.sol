//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

//Internal Dependencies
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";
import {OZErrors} from "test/utils/errors/OZErrors.sol";
import {ICrossChainBase_v1} from
    "src/modules/paymentProcessor/interfaces/ICrosschainBase_v1.sol";
import {CrosschainBase_v1} from
    "src/modules/paymentProcessor/abstracts/CrosschainBase_v1.sol";
//External Dependencies
import {Clones} from "@oz/proxy/Clones.sol";

//Tests and Mocks
// import cr
import {
    IERC20PaymentClientBase_v2,
    ERC20PaymentClientBaseV2Mock,
    ERC20Mock
} from "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV2Mock.sol";
//import exposed
import {CrosschainBase_v1_Exposed} from "./CrosschainBase_v1_Exposed.sol";

//System under test (SuT)
// import {
//     IPP_CrossChain_v1,
//     PP_CrossChain_v1,
//     IPaymentProcessor_v2
// } from "src/templates/modules/PP_Template_v1.sol";
import {IPaymentProcessor_v2} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {ICrossChainBase_v1} from
    "src/modules/paymentProcessor/interfaces/ICrosschainBase_v1.sol";

/**
 * @title   Inverter Template Payment Processor
 *
 * @notice  Basic template payment processor used to showcase the unit testing setup
 *
 * @dev     Not all functions are tested in this template. Placeholders of the functions that are not tested are added
 *          into the contract. This test showcases the following:
 *          - Inherit from the ModuleTest contract to enable interaction with the Inverter workflow.
 *          - Showcases the setup of the workflow, uses in test unit tests.
 *          - Pre-defined layout for all setup and functions to be tested.
 *          - Shows the use of Gherkin for documenting the testing. VS Code extension used for formatting is recommended.
 *          - Shows the use of the modifierInPlace pattern to test the modifier placement.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 */
contract CrosschainBase_v1_Test is ModuleTest {
    //--------------------------------------------------------------------------
    //Constants
    //--------------------------------------------------------------------------
    //State

    //Mocks
    ERC20PaymentClientBaseV2Mock paymentClient;

    //System under test (SuT)
    CrosschainBase_v1 public paymentProcessor;
    //PP_CrossChain_v1_Exposed public paymentProcessor;

    //--------------------------------------------------------------------------
    //Setup
    function setUp() public {}

    //--------------------------------------------------------------------------
    //Test: Initialization

    //Test if the orchestrator is correctly set
    function testInit() public override(ModuleTest) {}

    //Test the interface support
    function testSupportsInterface() public {}

    //Test the reinit function
    function testReinitFails() public override(ModuleTest) {}
}
