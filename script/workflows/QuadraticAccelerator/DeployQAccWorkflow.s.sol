// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

// Script Dependencies
import {TestnetDeploymentScript} from
    "script/deploymentScript/TestnetDeploymentScript.s.sol";
import {
    AccessDeploymentStateVariables,
    DeploymentState
} from "script/workflows/AccessDeploymentStateVariables.s.sol";
import {MetadataCollection_v1} from
    "script/deploymentSuite/MetadataCollection_v1.s.sol";

// Internal Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {ILM_PC_PaymentRouter_v1} from
    "@lm/interfaces/ILM_PC_PaymentRouter_v1.sol";

import {IFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {IRedeemingBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IRedeemingBondingCurveBase_v1.sol";

import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Dependencies
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";

import {
    IRestricted_PIM_Factory_v1,
    Restricted_PIM_Factory_v1
} from "src/factories/workflow-specific/Restricted_PIM_Factory_v1.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract DeployQAccWorkflow is MetadataCollection_v1, Script {
    //NOTE: This script assumes an exisiting orchestratorFactory. If there is none, it will create a testnetDeployment first

    //-------------------------------------------------------------------------
    // Storage

    uint private deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address public deployer = vm.addr(deployerPrivateKey);

    DeploymentState chain_addresses;

    ERC20Mock public orchestratorToken;
    ERC20Issuance_v1 public issuanceToken;
    IOrchestrator_v1 public orchestrator;

    function run() public virtual {
        AccessDeploymentStateVariables fetchState =
            new AccessDeploymentStateVariables();

        chain_addresses = fetchState.createTestnetDeploymentAndReturnState();

        orchestratorToken = ERC20Mock(chain_addresses.mockUSDToken);

        setupOrchestrator_withrestrictedPimFactory();
    }

    function setupOrchestrator() public {
        // ------------------------------------------------------------------------
        // Define Initial Configuration Data

        console.log("\n\n");
        console.log(
            "--------------------------------------------------------------------------------"
        );
        console.log("\tSTARTING Q/ACC WORKFLOW DEPLOYMENT");
        console.log(
            "--------------------------------------------------------------------------------"
        );

        // Deploy the issacne token  and set it up
        vm.startBroadcast(deployerPrivateKey);
        {
            issuanceToken = new ERC20Issuance_v1(
                "QAcc Project Token",
                "QACC",
                18,
                type(uint).max - 1,
                address(this) // assigns owner role to itself initially to manage minting rights temporarily
            );
        }
        vm.stopBroadcast();

        //mint deployer lots of tokens to test
        orchestratorToken.mint(deployer, 100e18);
        uint initialBuyAmount = 10e18;

        // Define bondign curve properties:
        IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties memory
            bc_properties = IFM_BC_Bancor_Redeeming_VirtualSupply_v1
                .BondingCurveProperties({
                formula: address(chain_addresses.formula),
                reserveRatioForBuying: 160_000,
                reserveRatioForSelling: 160_000,
                buyFee: 0,
                sellFee: 0,
                buyIsOpen: true,
                sellIsOpen: true,
                initialIssuanceSupply: 122_727_272_727_272_727_272_727,
                initialCollateralSupply: 3_163_408_614_166_851_161
            });

        // define token to be used as collateral
        orchestratorToken = ERC20Mock(chain_addresses.mockUSDToken);

        // Orchestrator_v1
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
        IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        // Funding Manager: Metadata, token address
        IOrchestratorFactory_v1.ModuleConfig memory fundingManagerFactoryConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            MetadataCollection_v1
                .restrictedBancorRedeemingVirtualSupplyFundingManagerMetadata,
            abi.encode(address(issuanceToken), bc_properties, orchestratorToken)
        );

        // Payment Processor: only Metadata
        IOrchestratorFactory_v1.ModuleConfig memory
            paymentProcessorFactoryConfig = IOrchestratorFactory_v1
                .ModuleConfig(streamingPaymentProcessorMetadata, bytes(""));

        // Authorizer: Metadata, initial authorized addresses
        IOrchestratorFactory_v1.ModuleConfig memory authorizerFactoryConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            roleAuthorizerMetadata,
            abi.encode(deployer) //@todo Admin address?
        );

        // PaymentRouter: none
        IOrchestratorFactory_v1.ModuleConfig memory paymentRouterFactoryConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            paymentRouterMetadata, abi.encode("")
        );

        // Add the configuration for all the non-mandatory modules. In this case only the PaymentRouter.
        IOrchestratorFactory_v1.ModuleConfig[] memory additionalModuleConfig =
            new IOrchestratorFactory_v1.ModuleConfig[](1);
        additionalModuleConfig[0] = paymentRouterFactoryConfig;

        // ------------------------------------------------------------------------
        // Orchestrator_v1 Creation

        vm.startBroadcast(deployerPrivateKey);
        {
            orchestrator = IOrchestratorFactory_v1(
                chain_addresses.orchestratorFactory
            ).createOrchestrator(
                workflowConfig,
                fundingManagerFactoryConfig,
                authorizerFactoryConfig,
                paymentProcessorFactoryConfig,
                additionalModuleConfig
            );
        }
        vm.stopBroadcast();

        // Now we need to find the BountyManager. ModuleManager has a function called `listModules` that returns a list of
        // active modules, let's use that to get the address of the BountyManager.

        ILM_PC_PaymentRouter_v1 paymentRouter;

        bytes4 ILM_PC_PaymentRouter_v1InterfaceId =
            type(ILM_PC_PaymentRouter_v1).interfaceId;
        address[] memory modulesList = orchestrator.listModules();
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
            orchestrator.orchestratorId(),
            address(orchestrator)
        );
        console2.log(
            "\t-FundingManager deployed at address: %s ",
            address(orchestrator.fundingManager())
        );
        console2.log(
            "\t-Authorizer deployed at address: %s ",
            address(orchestrator.authorizer())
        );
        console2.log(
            "\t-PaymentProcessor deployed at address: %s ",
            address(orchestrator.paymentProcessor())
        );

        console2.log(
            "\t-LM_PC_PaymentRouter_v1 deployed at address: %s ",
            address(paymentRouter)
        );
        console2.log(
            "=================================================================================="
        );

        console.log("\n\n");
        console.log(
            "--------------------------------------------------------------------------------"
        );
        console.log("Perfoming setup steps for qAcc round initialization");

        // get bonding curve / funding manager
        address fundingManager = address(orchestrator.fundingManager());

        // enable bonding curve to mint issuance token
        console.log("\t-Giving minting rights to the bonding curve");

        issuanceToken.setMinter(fundingManager, true);
        console.log("\t-Giving minting rights to the deployer");
        issuanceToken.setMinter(deployer, true);

        // we mint the initial supply as deployer
        console.log("\t-Minting initial issuance supply to deployer");
        issuanceToken.mint(deployer, bc_properties.initialIssuanceSupply);

        // give allowance to the bonding curve to spend deployer funds
        vm.startBroadcast(deployerPrivateKey);
        {
            //Allow the deployer to buy tokens
            console.log("\t-Granting CURVE_INTERACTION_ROLE to deployer");
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(fundingManager)
                .grantModuleRole(
                FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(
                    fundingManager
                ).CURVE_INTERACTION_ROLE(),
                deployer
            );

            // Set up initial supply and balance
            console.log(
                "\t-Transferring initial collateral supply to the bonding curve"
            );
            orchestratorToken.transfer(
                fundingManager, bc_properties.initialCollateralSupply
            );

            // Performt the initial buy
            console.log("\t-Performing initial buy");
            orchestratorToken.approve(address(fundingManager), initialBuyAmount);
            IBondingCurveBase_v1(fundingManager).buyFor(
                deployer, initialBuyAmount, 1
            );
        }
        vm.stopBroadcast();

        console.log("\t-Revoking minting rights from the deployer");
        // From now on only the curve has minting rights
        issuanceToken.setMinter(deployer, false);

        // The deployer is the owner of the issuance token

        console.log(
            "\t-Transferring ownership of the issuance token to the deployer"
        );
        issuanceToken.transferOwnership(deployer);
    }

    function setupOrchestrator_withrestrictedPimFactory() public {
        // ------------------------------------------------------------------------
        // Define Initial Configuration Data

        console.log("\n\n");
        console.log(
            "--------------------------------------------------------------------------------"
        );
        console.log("\tSTARTING Q/ACC WORKFLOW DEPLOYMENT - PIM FACTORY");
        console.log(
            "--------------------------------------------------------------------------------"
        );

        // Deploy the PIM Factory
        Restricted_PIM_Factory_v1 restrictedPimFactory;

        vm.startBroadcast(deployerPrivateKey);
        {
            restrictedPimFactory = new Restricted_PIM_Factory_v1(
                chain_addresses.orchestratorFactory, chain_addresses.forwarder
            );
            console2.log(
                "\t-Deployed PIM Factory at address: %s",
                address(restrictedPimFactory)
            );
        }
        vm.stopBroadcast();

        vm.startBroadcast(deployerPrivateKey);
        {
            console.log(
                "\t-Minting and approving initial collateralto deployer"
            );
            // mint collateral token to deployer
            orchestratorToken.mint(deployer, 100e18);

            //give allowance to the PIM factory to spend deployer funds
            orchestratorToken.approve(address(restrictedPimFactory), 100e18);
        }
        vm.stopBroadcast();

        // Configs
        // Orchestrator_v1
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
        IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        // Define bondign curve properties:
        IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties memory
            bc_properties = IFM_BC_Bancor_Redeeming_VirtualSupply_v1
                .BondingCurveProperties({
                formula: address(chain_addresses.formula),
                reserveRatioForBuying: 160_000,
                reserveRatioForSelling: 160_000,
                buyFee: 0,
                sellFee: 0,
                buyIsOpen: true,
                sellIsOpen: true,
                initialIssuanceSupply: 122_727_272_727_272_727_272_727,
                initialCollateralSupply: 3_163_408_614_166_851_161
            });

        // Funding Manager: Metadata, token address
        IOrchestratorFactory_v1.ModuleConfig memory fundingManagerFactoryConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            MetadataCollection_v1
                .restrictedBancorRedeemingVirtualSupplyFundingManagerMetadata,
            abi.encode(address(issuanceToken), bc_properties, orchestratorToken)
        );

        // Payment Processor: only Metadata
        IOrchestratorFactory_v1.ModuleConfig memory
            paymentProcessorFactoryConfig = IOrchestratorFactory_v1
                .ModuleConfig(streamingPaymentProcessorMetadata, bytes(""));

        // Authorizer: Metadata, initial authorized addresses
        IOrchestratorFactory_v1.ModuleConfig memory authorizerFactoryConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            roleAuthorizerMetadata,
            abi.encode(deployer) //@todo Admin address?
        );

        // PaymentRouter: none
        IOrchestratorFactory_v1.ModuleConfig memory paymentRouterFactoryConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            paymentRouterMetadata, abi.encode("")
        );

        // Add the configuration for all the non-mandatory modules. In this case only the PaymentRouter.
        IOrchestratorFactory_v1.ModuleConfig[] memory additionalModuleConfig =
            new IOrchestratorFactory_v1.ModuleConfig[](1);
        additionalModuleConfig[0] = paymentRouterFactoryConfig;

        // Issuance Token

        IBondingCurveBase_v1.IssuanceToken memory issuanceTokenParams =
        IBondingCurveBase_v1.IssuanceToken({
            name: "Bonding Curve Token",
            symbol: "BCT",
            decimals: 18,
            maxSupply: type(uint).max - 1
        });

        IOrchestrator_v1 orchestrator;
        ERC20Issuance_v1 issuanceToken;

        vm.startBroadcast(deployerPrivateKey);
        {
            console.log("\t-Creating PIM workflow");
            (orchestrator, issuanceToken) = restrictedPimFactory
                .createPIMWorkflow(
                workflowConfig,
                fundingManagerFactoryConfig,
                authorizerFactoryConfig,
                paymentProcessorFactoryConfig,
                additionalModuleConfig,
                issuanceTokenParams
            );
        }
        vm.stopBroadcast();

        console.log(
            "\t-Deployed orchestrator with id %s at address: %s",
            orchestrator.orchestratorId(),
            address(orchestrator)
        );
        console.log(
            "\t-Deployed issuance token at address: %s", address(issuanceToken)
        );
        console.log("Deployment complete");

        address fundingManager = address(orchestrator.fundingManager());

        vm.startBroadcast(deployerPrivateKey);
        {
            //give allowance to the Bonding Curve to spend deployer funds
            orchestratorToken.approve(fundingManager, 100e18);

            uint estimatedAmountOut = IBondingCurveBase_v1(fundingManager)
                .calculatePurchaseReturn(10e18);

            IBondingCurveBase_v1(fundingManager).buy(10e18, 1);
            console.log("Amount to sell: %s", estimatedAmountOut);

            IRedeemingBondingCurveBase_v1(fundingManager).sell(
                estimatedAmountOut, 1
            );
        }
        vm.stopBroadcast();
    }
}
