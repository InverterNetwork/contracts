// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "../../deployment/DeploymentScript.s.sol";

//import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {IModule_v1, ERC165} from "src/modules/base/Module_v1.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IOrchestrator_v1} from "src/orchestrator/Orchestrator_v1.sol";
import {
    LM_PC_PaymentRouter_v1,
    ILM_PC_PaymentRouter_v1
} from "@lm/LM_PC_PaymentRouter_v1.sol";

import {
    FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1,
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1
} from "@fm/bondingCurve/FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.sol";

import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";

import {BancorFormula} from "@fm/bondingCurve/formulas/BancorFormula.sol";

import {ERC20} from "@oz/token/ERC20/ERC20.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract SetupQuadraticAcceleratorWorkflow is Test, DeploymentScript {
    //ScriptConstants scriptConstants = new ScriptConstants();

    // ========================================================================
    // ENVIRONMENT VARIABLES OR CONSTANTS

    uint orchestratorOwnerPrivateKey =
        vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address orchestratorOwner = vm.addr(orchestratorOwnerPrivateKey);

    // NOTE: In case the script should be run on a chain WITHOUT an already deployed formula or collateral token,
    //       comment the following lines and uncomment the pre-steps in the run() function

    address collateralTokenAddress =
        vm.envAddress("BONDING_CURVE_COLLATERAL_TOKEN");
    ERC20 collateralToken = ERC20(collateralTokenAddress);

    address bancorFormulaAddress = vm.envAddress("BANCOR_FORMULA_ADDRESS");
    BancorFormula formula = BancorFormula(bancorFormulaAddress);

    // ========================================================================
    // BONDING CURVE PARAMETERS

    string CURVE_TOKEN_NAME = "Project Issuance Token";
    string CURVE_TOKEN_SYMBOL = "QACC";
    uint8 CURVE_TOKEN_DECIMALS = 18;

    uint32 RESERVE_RATIO_FOR_BUYING = 333_333;
    uint32 RESERVE_RATIO_FOR_SELLING = 333_333;
    uint BUY_FEE = 0;
    uint SELL_FEE = 100;
    bool BUY_IS_OPEN = true;
    bool SELL_IS_OPEN = false;
    uint INITIAL_ISSUANCE_SUPPLY = 100;
    uint INITIAL_COLLATERAL_SUPPLY = 33;

    // ========================================================================

    //-------------------------------------------------------------------------
    // Storage

    IOrchestrator_v1 _orchestrator;
    address[] initialAuthorizedAddresses;

    //-------------------------------------------------------------------------
    // Script

    function run() public override returns (address deployedOrchestrator) {
        // ------------------------------------------------------------------------
        // OPTIONAL PRE-STEPS

        //If the factories aren't deployed on the target chain, we can run the deployment script to deploy the factories, implementations and Beacons.
        address orchestratorFactory = DeploymentScript.run();

        //If there's no formula or token deployment on the chain, we deploy them
        vm.startBroadcast(orchestratorOwnerPrivateKey);
        {
            formula = new BancorFormula();
            console2.log(
                "\t-Bancor Bonding Curve Formula deployed at address: %s ",
                address(formula)
            );
            //!!!! This is not a real ERC20 implementation. Before going into production change this deployment!!!!
            collateralToken = new ERC20Mock("Inverter USD", "iUSD");
            console2.log(
                "\t-Inverter Mock USD Deployed at address: %s ",
                address(collateralToken)
            );
        }
        vm.stopBroadcast();

        // ------------------------------------------------------------------------
        // Setup

        // ------------------------------------------------------------------------
        // Define Initial Configuration Data

        // Orchestrator: Owner, funding token
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
        IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        IBondingCurveBase_v1.IssuanceToken memory buf_issuanceToken =
        IBondingCurveBase_v1.IssuanceToken({
            name: CURVE_TOKEN_NAME,
            symbol: CURVE_TOKEN_SYMBOL,
            decimals: CURVE_TOKEN_DECIMALS,
            maxSupply: type(uint).max
        });

        IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties memory
            buf_bondingCurveProperties =
            IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties({
                formula: address(formula),
                reserveRatioForBuying: RESERVE_RATIO_FOR_BUYING,
                reserveRatioForSelling: RESERVE_RATIO_FOR_SELLING,
                buyFee: BUY_FEE,
                sellFee: SELL_FEE,
                buyIsOpen: BUY_IS_OPEN,
                sellIsOpen: SELL_IS_OPEN,
                initialIssuanceSupply: INITIAL_ISSUANCE_SUPPLY,
                initialCollateralSupply: INITIAL_COLLATERAL_SUPPLY
            });

        // Funding Manager: Virtual Supply Bonding Curve Funding Manager
        IOrchestratorFactory_v1.ModuleConfig memory
            bondingCurveFundingManagerConfig = IOrchestratorFactory_v1
                .ModuleConfig(
                restrictedBancorVirtualSupplyBondingCurveFundingManagerMetadata,
                abi.encode(
                    buf_issuanceToken,
                    orchestratorOwner,
                    buf_bondingCurveProperties,
                    address(collateralToken)
                )
            );

        // Payment Processor: only Metadata
        IOrchestratorFactory_v1.ModuleConfig memory
            paymentProcessorFactoryConfig = IOrchestratorFactory_v1
                .ModuleConfig(streamingPaymentProcessorMetadata, bytes(""));

        // Authorizer: Metadata, initial authorized addresses
        IOrchestratorFactory_v1.ModuleConfig memory authorizerFactoryConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            roleAuthorizerMetadata,
            abi.encode(orchestratorOwner, orchestratorOwner)
        );

        // Bounty Manager:
        IOrchestratorFactory_v1.ModuleConfig memory paymentRouterFactoryConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            paymentRouterMetadata, abi.encode("")
        );

        // Add the configuration for all the non-mandatory modules. In this case only the LM_PC_Bounties_v1.
        IOrchestratorFactory_v1.ModuleConfig[] memory additionalModuleConfig =
            new IOrchestratorFactory_v1.ModuleConfig[](1);
        additionalModuleConfig[0] = paymentRouterFactoryConfig;

        // ------------------------------------------------------------------------
        // Orchestrator Creation

        vm.startBroadcast(orchestratorOwnerPrivateKey);
        {
            _orchestrator = IOrchestratorFactory_v1(orchestratorFactory)
                .createOrchestrator(
                workflowConfig,
                bondingCurveFundingManagerConfig,
                authorizerFactoryConfig,
                paymentProcessorFactoryConfig,
                additionalModuleConfig
            );
        }
        vm.stopBroadcast();

        // Check if the orchestrator has been created correctly.

        assert(address(_orchestrator) != address(0));

        address orchestratorToken =
            address(IOrchestrator_v1(_orchestrator).fundingManager().token());
        assertEq(orchestratorToken, address(collateralToken));

        // Now we need to find the PaymentRouter. ModuleManager has a function called `listModules` that returns a list of
        // active modules, let's use that to get the address of the BountyManager.

        LM_PC_PaymentRouter_v1 orchestratorCreatedPaymentRouter;

        address[] memory modulesList = _orchestrator.listModules();
        for (uint i; i < modulesList.length; ++i) {
            if (
                ERC165(modulesList[i]).supportsInterface(
                    type(ILM_PC_PaymentRouter_v1).interfaceId
                )
            ) {
                orchestratorCreatedPaymentRouter =
                    LM_PC_PaymentRouter_v1(modulesList[i]);
                break;
            }
        }
        assertEq(
            address(orchestratorCreatedPaymentRouter.orchestrator()),
            address(_orchestrator)
        );

        assertEq(formula.version(), "0.3");

        console2.log("\n\n");
        console2.log(
            "=================================================================================="
        );
        console2.log(
            "Orchestrator with Id %s created at address: %s ",
            _orchestrator.orchestratorId(),
            address(_orchestrator)
        );
        console2.log(
            "\t-RestrictedBondingCurveFundingManager deployed at address: %s ",
            address(_orchestrator.fundingManager())
        );
        console2.log(
            "\t-Authorizer deployed at address: %s ",
            address(_orchestrator.authorizer())
        );
        console2.log(
            "\t-StreamingPaymentProcessor deployed at address: %s ",
            address(_orchestrator.paymentProcessor())
        );

        console2.log(
            "\t-LM_PC_PaymentRouter_v1 deployed at address: %s ",
            address(orchestratorCreatedPaymentRouter)
        );
        console2.log(
            "=================================================================================="
        );

        // ------------------------------------------------------------------------

        vm.startBroadcast(orchestratorOwnerPrivateKey);
        {
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 bondingCurveFM =
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(
                address(_orchestrator.fundingManager())
            );
            // Whitelist owner to interact with the bonding curve bounties
            bondingCurveFM.grantModuleRole(
                bondingCurveFM.CURVE_INTERACTION_ROLE(), orchestratorOwner
            );

            // Whitelist owner to push payments to the payment router
            orchestratorCreatedPaymentRouter.grantModuleRole(
                orchestratorCreatedPaymentRouter.PAYMENT_PUSHER_ROLE(),
                orchestratorOwner
            );
        }
        vm.stopBroadcast();

        console2.log("\t - Initial Roles assigned.");

        console2.log(
            "=================================================================================="
        );
        console2.log("\n\n");

        return address(_orchestrator);
    }
}
