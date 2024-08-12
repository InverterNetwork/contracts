// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

// Scripts
import {TestnetDeploymentScript} from
    "script/deploymentScript/TestnetDeploymentScript.s.sol";

// Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {ILM_PC_PaymentRouter_v1} from
    "@lm/interfaces/ILM_PC_PaymentRouter_v1.sol";

// Dependencies
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract OrchestratorDeploymentScript is TestnetDeploymentScript {
    IOrchestrator_v1 public orchestrator;
    ERC20Mock public orchestratorToken;

    address public orchestratorAdmin;

    function run() public virtual override {
        // Run the superseeding run function from the TestnetDeploymentScript.
        super.run();

        // Set the orchestratorAdmin address, if env variable is set, otherwise we use
        // the deployer address.
        orchestratorAdmin = vm.envOr("ORCHESTRATOR_ADMIN_ADDRESS", deployer);

        // Setup the orchestrator.
        setupOrchestrator();
    }

    function setupOrchestrator() public {
        // First we deploy a mock ERC20 to act as the orchestrator token. It has a public mint function.
        vm.startBroadcast(deployerPrivateKey);
        {
            orchestratorToken = new ERC20Mock("Inverter USD", "iUSD");
        }
        vm.stopBroadcast();

        // ------------------------------------------------------------------------
        // Define Initial Configuration Data

        // General Workflow Configuration
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
        IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        // Funding Manager: metadata, token address
        IOrchestratorFactory_v1.ModuleConfig memory fundingManagerFactoryConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            depositVaultFundingManagerMetadata,
            abi.encode(address(orchestratorToken))
        );

        // Payment Processor: metadata
        IOrchestratorFactory_v1.ModuleConfig memory
            paymentProcessorFactoryConfig = IOrchestratorFactory_v1
                .ModuleConfig(simplePaymentProcessorMetadata, bytes(""));

        // Authorizer: metadata, initial authorized addresses
        IOrchestratorFactory_v1.ModuleConfig memory authorizerFactoryConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            roleAuthorizerMetadata, abi.encode(orchestratorAdmin)
        );

        // PaymentRouter: metadata
        IOrchestratorFactory_v1.ModuleConfig memory paymentRouterFactoryConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            paymentRouterMetadata, abi.encode("")
        );

        // Add the configuration for all the non-mandatory modules.
        // In this case only the LM_PC_PaymentRouter_v1 module.
        IOrchestratorFactory_v1.ModuleConfig[] memory additionalModuleConfig =
            new IOrchestratorFactory_v1.ModuleConfig[](1);
        additionalModuleConfig[0] = paymentRouterFactoryConfig;

        // ------------------------------------------------------------------------
        // Orchestrator_v1 Creation

        vm.startBroadcast(deployerPrivateKey);
        {
            orchestrator = IOrchestratorFactory_v1(orchestratorFactory)
                .createOrchestrator(
                workflowConfig,
                fundingManagerFactoryConfig,
                authorizerFactoryConfig,
                paymentProcessorFactoryConfig,
                additionalModuleConfig
            );
        }
        vm.stopBroadcast();

        // Now we need to find the PaymentRouter. ModuleManager has a function called `listModules` that returns a list of
        // active modules. Let's use that to get the address of the PaymentRouter.

        ILM_PC_PaymentRouter_v1 paymentRouter;

        bytes4 ILM_PC_PaymentRouter_v1_InterfaceId =
            type(ILM_PC_PaymentRouter_v1).interfaceId;
        address[] memory modulesList = orchestrator.listModules();
        for (uint i; i < modulesList.length; ++i) {
            if (
                ERC165Upgradeable(modulesList[i]).supportsInterface(
                    ILM_PC_PaymentRouter_v1_InterfaceId
                )
            ) {
                paymentRouter = ILM_PC_PaymentRouter_v1(modulesList[i]);
                break;
            }
        }

        console2.log();
        console2.log(
            "================================================================================"
        );
        console2.log("Start Orchestrator Deployment Script");
        console2.log(
            "================================================================================"
        );

        console2.log(
            "Orchestrator_v1 with id %s created at: %s ",
            orchestrator.orchestratorId(),
            address(orchestrator)
        );

        console2.log("  - Configuration");

        console2.log("\tOrchestrator Admin: %s", orchestratorAdmin);
        console2.log(
            "\tIndependent Updates: %s", workflowConfig.independentUpdates
        );

        console2.log("  - Modules");

        console2.log(
            "\tFundingManager deployed at: %s ",
            address(orchestrator.fundingManager())
        );
        console2.log(
            "\tAuthorizer deployed at: %s ", address(orchestrator.authorizer())
        );
        console2.log(
            "\tPaymentProcessor deployed at: %s ",
            address(orchestrator.paymentProcessor())
        );

        console2.log(
            "\tLM_PC_PaymentRouter_v1 deployed at: %s ", address(paymentRouter)
        );
        console2.log(
            "================================================================================"
        );
    }
}
