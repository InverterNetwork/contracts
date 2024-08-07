// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Script Dependencies
import {TestnetDeploymentScript} from
    "script/deploymentScript/TestnetDeploymentScript.s.sol";

// Internal InterfacesF
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {ILM_PC_PaymentRouter_v1} from
    "@lm/interfaces/ILM_PC_PaymentRouter_v1.sol";

// External Dependencies
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract OrchestratorDeploymentScript is TestnetDeploymentScript {
    //-------------------------------------------------------------------------
    // Storage

    ERC20Mock public orchestratorToken;
    IOrchestrator_v1 public test_orchestrator;

    address[] initialAuthorizedAddresses;

    function run() public virtual override {
        super.run();

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

        // Orchestrator_v1
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
        IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        // Funding Manager: Metadata, token address //@todo wait for DepositVault
        IOrchestratorFactory_v1.ModuleConfig memory fundingManagerFactoryConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            depositVaultFundingManagerMetadata,
            abi.encode(address(orchestratorToken))
        );

        // Payment Processor: only Metadata
        IOrchestratorFactory_v1.ModuleConfig memory
            paymentProcessorFactoryConfig = IOrchestratorFactory_v1
                .ModuleConfig(simplePaymentProcessorMetadata, bytes(""));

        // Authorizer: Metadata, initial authorized addresses
        IOrchestratorFactory_v1.ModuleConfig memory authorizerFactoryConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            roleAuthorizerMetadata,
            abi.encode(deployer) //@todo Admin address?
        );

        // PaymentRouter: Metadata, salary precision, fee percentage, fee treasury address
        IOrchestratorFactory_v1.ModuleConfig memory paymentRouterFactoryConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            paymentRouterMetadata, abi.encode("")
        );

        // Add the configuration for all the non-mandatory modules. In this case only the LM_PC_Bounties_v1.
        IOrchestratorFactory_v1.ModuleConfig[] memory additionalModuleConfig =
            new IOrchestratorFactory_v1.ModuleConfig[](1);
        additionalModuleConfig[0] = paymentRouterFactoryConfig;

        // ------------------------------------------------------------------------
        // Orchestrator_v1 Creation

        vm.startBroadcast(deployerPrivateKey);
        {
            test_orchestrator = IOrchestratorFactory_v1(orchestratorFactory)
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
        // active modules, let's use that to get the address of the PaymentRouter.

        ILM_PC_PaymentRouter_v1 paymentRouter;

        bytes4 ILM_PC_PaymentRouter_v1InterfaceId =
            type(ILM_PC_PaymentRouter_v1).interfaceId;
        address[] memory modulesList = test_orchestrator.listModules();
        for (uint i; i < modulesList.length; ++i) {
            if (
                ERC165Upgradeable(modulesList[i]).supportsInterface(
                    ILM_PC_PaymentRouter_v1InterfaceId
                )
            ) {
                paymentRouter = ILM_PC_PaymentRouter_v1(modulesList[i]);
                break;
            }
        }

        console2.log("\n\n");
        console2.log(
            "=================================================================================="
        );
        console2.log(
            "Orchestrator_v1 with Id %s created at address: %s ",
            test_orchestrator.orchestratorId(),
            address(test_orchestrator)
        );
        console2.log(
            "\t-FundingManager deployed at address: %s ",
            address(test_orchestrator.fundingManager())
        );
        console2.log(
            "\t-Authorizer deployed at address: %s ",
            address(test_orchestrator.authorizer())
        );
        console2.log(
            "\t-PaymentProcessor deployed at address: %s ",
            address(test_orchestrator.paymentProcessor())
        );

        console2.log(
            "\t-LM_PC_PaymentRouter_v1 deployed at address: %s ",
            address(paymentRouter)
        );
        console2.log(
            "=================================================================================="
        );
    }
}
