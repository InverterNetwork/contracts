// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "../../deployment/DeploymentScript.s.sol";

import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IOrchestrator_v1} from "src/orchestrator/Orchestrator_v1.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {
    LM_PC_Bounties_v1, ILM_PC_Bounties_v1
} from "@lm/LM_PC_Bounties_v1.sol";
import {AUT_TokenGated_Roles_v1} from "@aut/role/AUT_TokenGated_Roles_v1.sol";
import {ScriptConstants} from "../../script-constants.sol";
import {FM_Rebasing_v1} from "@fm/rebasing/FM_Rebasing_v1.sol";

contract DeployBloomNetworkScript is Test, DeploymentScript {
    ScriptConstants scriptConstants = new ScriptConstants();
    bool hasDependency;
    string[] dependencies = new string[](0);

    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint orchestratorOwnerPrivateKey =
        vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address orchestratorOwner = vm.addr(orchestratorOwnerPrivateKey);

    //-------------------------------------------------------------------------
    // Mock Funder and Contributor information

    //Since this is a demo deployment, we will use the same address for the owner and the funder.
    uint funder1PrivateKey = orchestratorOwnerPrivateKey;
    address funder1 = orchestratorOwner;

    //-------------------------------------------------------------------------
    // Storage

    ERC20Mock token;
    IOrchestrator_v1 test_orchestrator;

    address[] initialAuthorizedAddresses;

    //-------------------------------------------------------------------------
    // Script

    function run() public override returns (address deployedOrchestrator) {
        // ------------------------------------------------------------------------
        // Setup

        // First we deploy a mock ERC20 to act as funding token for the orchestrator. It has a public mint function.
        vm.startBroadcast(orchestratorOwnerPrivateKey);
        {
            token = new ERC20Mock("Bloom Token", "BLOOM");
            //token = ERC20Mock(0x5eb14c2e7D0cD925327d74ae4ce3fC692ff8ABEF);

            token.mint(
                address(orchestratorOwner),
                scriptConstants.orchestratorTokenDepositAmount()
            );
        }
        vm.stopBroadcast();

        // Then, we run the deployment script to deploy the factories, implementations and Beacons.
        address orchestratorFactory = DeploymentScript.run();

        //We use the exisiting orchestratorFactory address
        //address orchestratorFactory = 0x690d5000D278f90B167354975d019c747B78032e;

        // ------------------------------------------------------------------------
        // Define Initial Configuration Data

        // Orchestrator_v1: Owner, funding token
        IOrchestratorFactory_v1.OrchestratorConfig memory orchestratorConfig =
        IOrchestratorFactory_v1.OrchestratorConfig({
            owner: orchestratorOwner,
            token: token
        });

        // Funding Manager: Metadata, token address
        IOrchestratorFactory_v1.ModuleConfig memory fundingManagerFactoryConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            rebasingFundingManagerMetadata,
            abi.encode(address(token)),
            abi.encode(hasDependency, dependencies)
        );

        // Payment Processor: only Metadata
        IOrchestratorFactory_v1.ModuleConfig memory
            paymentProcessorFactoryConfig = IOrchestratorFactory_v1
                .ModuleConfig(
                simplePaymentProcessorMetadata,
                bytes(""),
                abi.encode(hasDependency, dependencies)
            );

        // Authorizer: Metadata, initial authorized addresses
        IOrchestratorFactory_v1.ModuleConfig memory authorizerFactoryConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            tokenGatedRoleAuthorizerMetadata,
            abi.encode(orchestratorOwner, orchestratorOwner),
            abi.encode(hasDependency, dependencies)
        );

        // MilestoneManager: Metadata, salary precision, fee percentage, fee treasury address
        IOrchestratorFactory_v1.ModuleConfig memory bountyManagerFactoryConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            bountyManagerMetadata,
            abi.encode(""),
            abi.encode(true, dependencies)
        );

        // Add the configuration for all the non-mandatory modules. In this case only the LM_PC_Bounties_v1.
        IOrchestratorFactory_v1.ModuleConfig[] memory additionalModuleConfig =
            new IOrchestratorFactory_v1.ModuleConfig[](1);
        additionalModuleConfig[0] = bountyManagerFactoryConfig;

        // ------------------------------------------------------------------------
        // Orchestrator_v1 Creation

        vm.startBroadcast(orchestratorOwnerPrivateKey);
        {
            test_orchestrator = IOrchestratorFactory_v1(orchestratorFactory)
                .createOrchestrator(
                orchestratorConfig,
                fundingManagerFactoryConfig,
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

        // Now we need to find the MilestoneManager. ModuleManagerBase_v1 has a function called `listModules` that returns a list of
        // active modules, let's use that to get the address of the MilestoneManager.

        // TODO: Ideally this would be substituted by a check that that all mandatory modules implement their corresponding interfaces + the same for MilestoneManager

        address[] memory moduleAddresses =
            IOrchestrator_v1(test_orchestrator).listModules();
        //uint lenModules = moduleAddresses.length;
        address orchestratorCreatedBountyManagerAddress;

        for (uint i; i < moduleAddresses.length;) {
            try ILM_PC_Bounties_v1(moduleAddresses[i]).isExistingBountyId(0)
            returns (bool) {
                orchestratorCreatedBountyManagerAddress = moduleAddresses[i];
                break;
            } catch {
                i++;
            }
        }

        LM_PC_Bounties_v1 orchestratorCreatedBountyManager =
            LM_PC_Bounties_v1(orchestratorCreatedBountyManagerAddress);

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
        // It's best, if the owner deposits them right after deployment.

        // Initial Deposit => 10e18;
        FM_Rebasing_v1 fundingManager =
            FM_Rebasing_v1(address(test_orchestrator.fundingManager()));

        vm.startBroadcast(orchestratorOwnerPrivateKey);
        {
            token.approve(
                address(fundingManager),
                scriptConstants.orchestratorTokenDepositAmount()
            );
            fundingManager.deposit(
                scriptConstants.orchestratorTokenDepositAmount()
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
            fundingManager.deposit(scriptConstants.funder1TokenDepositAmount());
        }
        vm.stopBroadcast();
        console2.log("\t -Funder 1: Deposit Performed");

        // OPTIONAL
        // ===============================================================================================================
        // Make the Roles Token-Gated
        // ===============================================================================================================

        // ===============================================================================================================
        // Introduce authentication conditions here:
        //      - Address of the token to be used
        //      - Minimum amount of tokens needed by the caller
        // ===============================================================================================================

        uint thresholdAmount = 1;

        AUT_TokenGated_Roles_v1 deployedAuthorizer =
            AUT_TokenGated_Roles_v1(address(test_orchestrator.authorizer()));

        vm.startBroadcast(orchestratorOwner);

        //Give the Orchestrator_v1 owner the power to change module roles
        deployedAuthorizer.grantRole(
            deployedAuthorizer.DEFAULT_ADMIN_ROLE(), orchestratorOwner
        );

        // Choose the role to be modified. In this example we will use the CLAIMANT_ROLE
        bytes32 roleId = deployedAuthorizer.generateRoleId(
            address(orchestratorCreatedBountyManager),
            orchestratorCreatedBountyManager.CLAIMANT_ROLE()
        );

        //First, we mark the Role as Token-Gated
        deployedAuthorizer.setTokenGated(roleId, true);
        // Second, we set the token to be used for the Role as the gating token
        deployedAuthorizer.grantRole(roleId, address(token));
        // Third, we set the minimum amount of tokens needed to be able to execute the Role
        deployedAuthorizer.setThreshold(roleId, address(token), thresholdAmount);

        vm.stopBroadcast();

        console.log(
            "=================================================================================="
        );
        console.log(
            "Execution succesful: Token-gating set up by the token %s with a threshold of %s",
            address(token),
            thresholdAmount
        );

        // ------------------------------------------------------------------------

        /*
        // Create a Bounty
        vm.startBroadcast(orchestratorOwnerPrivateKey);

        // Whitelist owner to create bounties
        orchestratorCreatedBountyManager.grantModuleRole(
            orchestratorCreatedBountyManager.BOUNTY_ISSUER_ROLE(),
            orchestratorOwner
        );

        // Whitelist owner to post claims
        orchestratorCreatedBountyManager.grantModuleRole(
            orchestratorCreatedBountyManager.CLAIMANT_ROLE(), orchestratorOwner
        );
        // Whitelist owner to verify claims
        orchestratorCreatedBountyManager.grantModuleRole(
            orchestratorCreatedBountyManager.VERIFIER_ROLE(), orchestratorOwner
        );

        bytes memory details = "TEST BOUNTY";

        uint bountyId = orchestratorCreatedBountyManager.addBounty(
            scriptConstants.addBounty_minimumPayoutAmount(),
            scriptConstants.addBounty_maximumPayoutAmount(),
            details
        );

        vm.stopBroadcast();

        console2.log("\t -Bounty Created. Id: ", bountyId);

        console2.log(
            "=================================================================================="
        );
        console2.log("\n\n"); */

        return address(test_orchestrator);
    }
}
