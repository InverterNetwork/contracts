// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "../deployment/DeploymentScript.s.sol";

import {IMilestoneManager} from "src/modules/logicModule/IMilestoneManager.sol";
import {IFundingManager} from "src/modules/fundingManager/IFundingManager.sol";
import {IOrchestratorFactory} from "src/factories/IOrchestratorFactory.sol";
import {IOrchestrator} from "src/orchestrator/Orchestrator.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract SetupToyOrchestratorScript is Test, DeploymentScript {
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

    // Every Milestone needs some contributors
    IMilestoneManager.Contributor alice = IMilestoneManager.Contributor(
        address(0xA11CE), 50_000_000, "AliceIdHash"
    );
    IMilestoneManager.Contributor bob =
        IMilestoneManager.Contributor(address(0x606), 50_000_000, "BobIdHash");

    //-------------------------------------------------------------------------
    // Storage

    ERC20Mock token;
    IOrchestrator test_orchestrator;

    IMilestoneManager.Contributor[] contributors;
    address[] initialAuthorizedAddresses;

    //-------------------------------------------------------------------------
    // Script

    function run() public override returns (address deployedOrchestrator) {
        // ------------------------------------------------------------------------
        // Setup

        // First we deploy a mock ERC20 to act as funding token for the orchestrator. It has a public mint function.
        vm.startBroadcast(orchestratorOwnerPrivateKey);
        {
            token = new ERC20Mock("Mock", "MOCK");
        }
        vm.stopBroadcast();

        // Then, we run the deployment script to deploy the factories, implementations and Beacons.
        address orchestratorFactory = DeploymentScript.run();

        // ------------------------------------------------------------------------
        // Define Initial Configuration Data

        // Orchestrator: Owner, funding token
        IOrchestratorFactory.OrchestratorConfig memory orchestratorConfig =
        IOrchestratorFactory.OrchestratorConfig({
            owner: orchestratorOwner,
            token: token
        });

        // Funding Manager: Metadata, token address
        IOrchestratorFactory.ModuleConfig memory fundingManagerFactoryConfig =
        IOrchestratorFactory.ModuleConfig(
            fundingManagerMetadata,
            abi.encode(address(token)),
            abi.encode(hasDependency, dependencies)
        );

        // Payment Processor: only Metadata
        IOrchestratorFactory.ModuleConfig memory paymentProcessorFactoryConfig =
        IOrchestratorFactory.ModuleConfig(
            paymentProcessorMetadata,
            bytes(""),
            abi.encode(hasDependency, dependencies)
        );

        // Authorizer: Metadata, initial authorized addresses
        initialAuthorizedAddresses.push(orchestratorOwner);
        IOrchestratorFactory.ModuleConfig memory authorizerFactoryConfig =
        IOrchestratorFactory.ModuleConfig(
            authorizerMetadata,
            abi.encode(initialAuthorizedAddresses),
            abi.encode(hasDependency, dependencies)
        );

        // MilestoneManager: Metadata, salary precision, fee percentage, fee treasury address
        IOrchestratorFactory.ModuleConfig memory milestoneManagerFactoryConfig =
        IOrchestratorFactory.ModuleConfig(
            milestoneManagerMetadata,
            abi.encode(100_000_000, 1_000_000, orchestratorOwner),
            abi.encode(hasDependency, dependencies)
        );

        // Add the configuration for all the non-mandatory modules. In this case only the Milestone Manager.
        IOrchestratorFactory.ModuleConfig[] memory additionalModuleConfig =
            new IOrchestratorFactory.ModuleConfig[](1);
        additionalModuleConfig[0] = milestoneManagerFactoryConfig;

        // ------------------------------------------------------------------------
        // Orchestrator Creation

        vm.startBroadcast(orchestratorOwnerPrivateKey);
        {
            test_orchestrator = IOrchestratorFactory(orchestratorFactory)
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

        address orchestratorToken =
            address(IOrchestrator(test_orchestrator).token());
        assertEq(orchestratorToken, address(token));

        // Now we need to find the MilestoneManager. ModuleManager has a function called `listModules` that returns a list of
        // active modules, let's use that to get the address of the MilestoneManager.

        // TODO: Ideally this would be substituted by a check that that all mandatory modules implement their corresponding interfaces + the same for MilestoneManager

        address[] memory moduleAddresses =
            IOrchestrator(test_orchestrator).listModules();
        uint lenModules = moduleAddresses.length;
        address orchestratorCreatedMilestoneManagerAddress;

        for (uint i; i < lenModules;) {
            try IMilestoneManager(moduleAddresses[i]).hasActiveMilestone()
            returns (bool) {
                orchestratorCreatedMilestoneManagerAddress = moduleAddresses[i];
                break;
            } catch {
                i++;
            }
        }

        IMilestoneManager orchestratorCreatedMilestoneManager =
            IMilestoneManager(orchestratorCreatedMilestoneManagerAddress);

        assertFalse(
            orchestratorCreatedMilestoneManager.hasActiveMilestone(),
            "Error in the MilestoneManager"
        );
        assertFalse(
            orchestratorCreatedMilestoneManager.isExistingMilestoneId(
                type(uint).max
            ),
            "Error in the MilestoneManager"
        );
        assertEq(
            orchestratorCreatedMilestoneManager.getMaximumContributors(),
            50,
            "Error in the MilestoneManager"
        );

        console2.log("\n\n");
        console2.log(
            "=================================================================================="
        );
        console2.log(
            "Orchestrator with Id %s created at address: %s ",
            test_orchestrator.orchestratorId(),
            address(test_orchestrator)
        );

        // ------------------------------------------------------------------------
        // Initialize FundingManager

        // IMPORTANT
        // =========
        // Due to how the underlying rebase mechanism works, it is necessary
        // to always have some amount of tokens in the orchestrator.
        // It's best, if the owner deposits them right after deployment.

        uint initialDeposit = 10e18;
        IFundingManager fundingManager =
            IFundingManager(address(test_orchestrator.fundingManager()));

        vm.startBroadcast(orchestratorOwnerPrivateKey);
        {
            token.mint(address(orchestratorOwner), initialDeposit);

            token.approve(address(fundingManager), initialDeposit);

            fundingManager.deposit(initialDeposit);
        }
        vm.stopBroadcast();
        console2.log("\t -Initialization Funding Done");

        // Mint some tokens for the funder and deposit them
        vm.startBroadcast(funder1PrivateKey);
        {
            token.mint(funder1, 1000e18);
            token.approve(address(fundingManager), 1000e18);
            fundingManager.deposit(1000e18);
        }
        vm.stopBroadcast();
        console2.log("\t -Funder 1: Deposit Performed");

        // ------------------------------------------------------------------------
        // Initialize Milestone Manager: Set up two Milestones with corresponding contributors

        contributors.push(alice);
        contributors.push(bob);

        vm.startBroadcast(orchestratorOwnerPrivateKey);
        {
            orchestratorCreatedMilestoneManager.addMilestone(
                1 weeks,
                1000e18,
                contributors,
                bytes("Here could be a more detailed description")
            );

            orchestratorCreatedMilestoneManager.addMilestone(
                2 weeks,
                5000e18,
                contributors,
                bytes("The second milestone, right after the first one")
            );
        }
        vm.stopBroadcast();
        console2.log("\t -Milestones Added");

        // Check if the Milestones have has been added correctly

        // milestoneId 1 should exist and 0 shouldn't, since IDs start from 1.
        assertTrue(
            !(orchestratorCreatedMilestoneManager.isExistingMilestoneId(0))
        );
        assertTrue(orchestratorCreatedMilestoneManager.isExistingMilestoneId(1));

        assertTrue(
            orchestratorCreatedMilestoneManager.isContributor(1, alice.addr)
        );
        assertTrue(
            orchestratorCreatedMilestoneManager.isContributor(2, alice.addr)
        );

        console2.log(
            "=================================================================================="
        );
        console2.log("\n\n");

        return address(test_orchestrator);
    }
}
