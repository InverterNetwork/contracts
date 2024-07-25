// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "../deployment/DeploymentScript.s.sol";

import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {
    FM_BC_Bancor_Redeeming_VirtualSupply_v1,
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1
} from "@fm/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";

import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";

import {BancorFormula} from "@fm/bondingCurve/formulas/BancorFormula.sol";

import {IModule_v1, ERC165Upgradeable} from "src/modules/base/Module_v1.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IOrchestrator_v1} from "src/orchestrator/Orchestrator_v1.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {
    LM_PC_Bounties_v1, ILM_PC_Bounties_v1
} from "@lm/LM_PC_Bounties_v1.sol";
import {ScriptConstants} from "../script-constants.sol";

contract SetupToyOrchestratorScript is Test, DeploymentScript {
    ScriptConstants scriptConstants = new ScriptConstants();

    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint orchestratorAdminPrivateKey =
        vm.envUint("ORCHESTRATOR_ADMIN_PRIVATE_KEY");
    address orchestratorAdmin = vm.addr(orchestratorAdminPrivateKey);

    //-------------------------------------------------------------------------
    // Mock Funder and Contributor information

    // Since this is a demo deployment, we will use the same address for the admin and the funder.
    uint funder1PrivateKey = orchestratorAdminPrivateKey;
    address funder1 = orchestratorAdmin;

    //-------------------------------------------------------------------------
    // Storage

    ERC20Mock token;
    IOrchestrator_v1 test_orchestrator;

    BancorFormula formula;
    // ========================================================================
    // BONDING CURVE PARAMETERS

    string CURVE_TOKEN_NAME = "Bonding Curve Issuance Token";
    string CURVE_TOKEN_SYMBOL = "BCRG";
    uint8 CURVE_TOKEN_DECIMALS = 18;

    uint32 RESERVE_RATIO_FOR_BUYING = 333_333;
    uint32 RESERVE_RATIO_FOR_SELLING = 333_333;
    uint INITIAL_ISSUANCE_SUPPLY = 100;
    uint INITIAL_COLLATERAL_SUPPLY = 33;

    //-------------------------------------------------------------------------
    // Script

    function run() public override returns (address) {
        // ------------------------------------------------------------------------
        // Setup

        // If there's no formula or token deployment on the chain, we deploy them
        vm.startBroadcast(orchestratorAdminPrivateKey);
        {
            formula = new BancorFormula();
            console2.log(
                "\t-Bancor Bonding Curve Formula deployed at address: %s ",
                address(formula)
            );
            //!!!! This is not a real ERC20 implementation. Before going into production change this deployment!!!!
            token = new ERC20Mock("Inverter USD", "iUSD");
            console2.log(
                "\t-Inverter Mock USD Deployed at address: %s ", address(token)
            );
        }
        vm.stopBroadcast();
        // token = ERC20Mock(0x5eb14c2e7D0cD925327d74ae4ce3fC692ff8ABEF);

        // Then, we run the deployment script to deploy the factories, implementations and Beacons.
        address orchestratorFactory = DeploymentScript.run();

        // We use the exisiting orchestratorFactory address
        // address orchestratorFactory = 0x690d5000D278f90B167354975d019c747B78032e;

        // ------------------------------------------------------------------------
        // Define Initial Configuration Data

        // Orchestrator_v1
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
        IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        // Funding Manager: Issunaance Token, Bonding Curve Metadata, collateral token address
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
                buyFee: 0,
                sellFee: 100,
                buyIsOpen: true,
                sellIsOpen: false,
                initialIssuanceSupply: INITIAL_ISSUANCE_SUPPLY,
                initialCollateralSupply: INITIAL_COLLATERAL_SUPPLY
            });

        // Funding Manager: Virtual Supply Bonding Curve Funding Manager
        IOrchestratorFactory_v1.ModuleConfig memory
            bondingCurveFundingManagerConfig = IOrchestratorFactory_v1
                .ModuleConfig(
                bancorVirtualSupplyBondingCurveFundingManagerMetadata,
                abi.encode(
                    buf_issuanceToken,
                    orchestratorAdmin,
                    buf_bondingCurveProperties,
                    address(token)
                )
            );

        // Payment Processor: only Metadata
        IOrchestratorFactory_v1.ModuleConfig memory
            paymentProcessorFactoryConfig = IOrchestratorFactory_v1
                .ModuleConfig(simplePaymentProcessorMetadata, bytes(""));

        // Authorizer: Metadata, initial authorized addresses
        IOrchestratorFactory_v1.ModuleConfig memory authorizerFactoryConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            roleAuthorizerMetadata, abi.encode(orchestratorAdmin)
        );

        // BountyManager: Metadata, salary precision, fee percentage, fee treasury address
        IOrchestratorFactory_v1.ModuleConfig memory bountyManagerFactoryConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            bountyManagerMetadata, abi.encode("")
        );

        // Add the configuration for all the non-mandatory modules. In this case only the LM_PC_Bounties_v1.
        IOrchestratorFactory_v1.ModuleConfig[] memory additionalModuleConfig =
            new IOrchestratorFactory_v1.ModuleConfig[](1);
        additionalModuleConfig[0] = bountyManagerFactoryConfig;

        // ------------------------------------------------------------------------
        // Orchestrator_v1 Creation

        vm.startBroadcast(orchestratorAdminPrivateKey);
        {
            test_orchestrator = IOrchestratorFactory_v1(orchestratorFactory)
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

        assert(address(test_orchestrator) != address(0));

        address orchestratorToken = address(
            IOrchestrator_v1(test_orchestrator).fundingManager().token()
        );
        assertEq(orchestratorToken, address(token));

        // Now we need to find the BountyManager. ModuleManager has a function called `listModules` that returns a list of
        // active modules, let's use that to get the address of the BountyManager.

        LM_PC_Bounties_v1 orchestratorCreatedBountyManager;

        bytes4 LM_PC_Bounties_v1InterfaceId =
            type(ILM_PC_Bounties_v1).interfaceId;
        address[] memory modulesList = test_orchestrator.listModules();
        for (uint i; i < modulesList.length; ++i) {
            if (
                ERC165Upgradeable(modulesList[i]).supportsInterface(
                    LM_PC_Bounties_v1InterfaceId
                )
            ) {
                orchestratorCreatedBountyManager =
                    LM_PC_Bounties_v1(modulesList[i]);
                break;
            }
        }

        assertEq(
            address(orchestratorCreatedBountyManager.orchestrator()),
            address(test_orchestrator)
        );

        assertFalse(
            orchestratorCreatedBountyManager.isExistingBountyId(0),
            "Error in the LM_PC_Bounties_v1"
        );
        assertFalse(
            orchestratorCreatedBountyManager.isExistingBountyId(type(uint).max),
            "Error in the LM_PC_Bounties_v1"
        );

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
            "\t-LM_PC_Bounties_v1 deployed at address: %s ",
            address(orchestratorCreatedBountyManager)
        );
        console2.log(
            "=================================================================================="
        );

        // ------------------------------------------------------------------------
        // Initialize FundingManager

        // IMPORTANT
        // =========
        // Due to how the underlying rebase mechanism works, it is necessary
        // to always have some amount of tokens in the orchestrator.
        // It's best, if the admin deposits them right after deployment.

        // Initial Deposit => 10e18;
        FM_BC_Bancor_Redeeming_VirtualSupply_v1 fundingManager =
        FM_BC_Bancor_Redeeming_VirtualSupply_v1(
            address(test_orchestrator.fundingManager())
        );

        vm.startBroadcast(orchestratorAdminPrivateKey);
        {
            token.mint(
                address(orchestratorAdmin),
                scriptConstants.orchestratorTokenDepositAmount()
            );

            token.approve(
                address(fundingManager),
                scriptConstants.orchestratorTokenDepositAmount()
            );

            fundingManager.buy(
                scriptConstants.orchestratorTokenDepositAmount(), 1
            );
        }
        vm.stopBroadcast();
        console2.log("\t -Initialization Funding Done");

        // Mint some tokens for the funder and deposit them
        vm.startBroadcast(funder1PrivateKey);
        {
            token.mint(funder1, scriptConstants.funder1TokenDepositAmount());
            token.approve(
                address(fundingManager),
                scriptConstants.funder1TokenDepositAmount()
            );
            fundingManager.buy(scriptConstants.funder1TokenDepositAmount(), 1);
        }
        vm.stopBroadcast();
        console2.log("\t -Funder 1: Deposit Performed");

        // ------------------------------------------------------------------------

        // Create a Bounty
        vm.startBroadcast(orchestratorAdminPrivateKey);

        // Whitelist admin to create bounties
        orchestratorCreatedBountyManager.grantModuleRole(
            orchestratorCreatedBountyManager.BOUNTY_ISSUER_ROLE(),
            orchestratorAdmin
        );

        // Whitelist admin to post claims
        orchestratorCreatedBountyManager.grantModuleRole(
            orchestratorCreatedBountyManager.CLAIMANT_ROLE(), orchestratorAdmin
        );
        // Whitelist admin to verify claims
        orchestratorCreatedBountyManager.grantModuleRole(
            orchestratorCreatedBountyManager.VERIFIER_ROLE(), orchestratorAdmin
        );

        uint bountyId = orchestratorCreatedBountyManager.addBounty(
            scriptConstants.addBounty_minimumPayoutAmount(),
            scriptConstants.addBounty_maximumPayoutAmount(),
            "TEST BOUNTY"
        );

        vm.stopBroadcast();

        console2.log("\t -Bounty Created. Id: ", bountyId);

        console2.log(
            "=================================================================================="
        );
        console2.log("\n\n");

        return address(test_orchestrator);
    }
}
