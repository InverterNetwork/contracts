// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "../deployment/DeploymentScript.s.sol";

import {IMilestoneManager} from "src/modules/logicModule/IMilestoneManager.sol";
import {IFundingManager} from "src/modules/fundingManager/IFundingManager.sol";
import {IProposalFactory} from "src/factories/IProposalFactory.sol";
import {IProposal} from "src/proposal/Proposal.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract SetupToyProposalScript is Test, DeploymentScript {
    bool hasDependency;
    string[] dependencies = new string[](0);

    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint proposalOwnerPrivateKey = vm.envUint("PROPOSAL_OWNER_PRIVATE_KEY");
    address proposalOwner = vm.addr(proposalOwnerPrivateKey);

    //-------------------------------------------------------------------------
    // Mock Funder and Contributor information

    //Since this is a demo deployment, we will use the same address for the owner and the funder.
    uint funder1PrivateKey = proposalOwnerPrivateKey;
    address funder1 = proposalOwner;

    // Every Milestone needs some contributors
    IMilestoneManager.Contributor alice = IMilestoneManager.Contributor(
        address(0xA11CE), 50_000_000, "AliceIdHash"
    );
    IMilestoneManager.Contributor bob =
        IMilestoneManager.Contributor(address(0x606), 50_000_000, "BobIdHash");

    //-------------------------------------------------------------------------
    // Storage

    ERC20Mock token;
    IProposal test_proposal;

    IMilestoneManager.Contributor[] contributors;
    address[] initialAuthorizedAddresses;

    //-------------------------------------------------------------------------
    // Script

    function run() public override returns (address deployedProposal) {
        // ------------------------------------------------------------------------
        // Setup

        // First we deploy a mock ERC20 to act as funding token for the proposal. It has a public mint function.
        vm.startBroadcast(proposalOwnerPrivateKey);
        {
            token = new ERC20Mock("Mock", "MOCK");
        }
        vm.stopBroadcast();

        // Then, we run the deployment script to deploy the factories, implementations and Beacons.
        address proposalFactory = DeploymentScript.run();

        // ------------------------------------------------------------------------
        // Define Initial Configuration Data

        // Proposal: Owner, funding token
        IProposalFactory.ProposalConfig memory proposalConfig = IProposalFactory
            .ProposalConfig({owner: proposalOwner, token: token});

        // Funding Manager: Metadata, token address
        IProposalFactory.ModuleConfig memory fundingManagerFactoryConfig =
        IProposalFactory.ModuleConfig(
            fundingManagerMetadata, abi.encode(address(token)), abi.encode(hasDependency, dependencies)
        );

        // Payment Processor: only Metadata
        IProposalFactory.ModuleConfig memory paymentProcessorFactoryConfig =
            IProposalFactory.ModuleConfig(paymentProcessorMetadata, bytes(""), abi.encode(hasDependency, dependencies));

        // Authorizer: Metadata, initial authorized addresses
        initialAuthorizedAddresses.push(proposalOwner);
        IProposalFactory.ModuleConfig memory authorizerFactoryConfig =
        IProposalFactory.ModuleConfig(
            authorizerMetadata, abi.encode(initialAuthorizedAddresses), abi.encode(hasDependency, dependencies)
        );

        // MilestoneManager: Metadata, salary precision, fee percentage, fee treasury address
        IProposalFactory.ModuleConfig memory milestoneManagerFactoryConfig =
        IProposalFactory.ModuleConfig(
            milestoneManagerMetadata,
            abi.encode(100_000_000, 1_000_000, proposalOwner), abi.encode(hasDependency, dependencies)
        );

        // Add the configuration for all the non-mandatory modules. In this case only the Milestone Manager.
        IProposalFactory.ModuleConfig[] memory additionalModuleConfig =
            new IProposalFactory.ModuleConfig[](1);
        additionalModuleConfig[0] = milestoneManagerFactoryConfig;

        // ------------------------------------------------------------------------
        // Proposal Creation

        vm.startBroadcast(proposalOwnerPrivateKey);
        {
            test_proposal = IProposalFactory(proposalFactory).createProposal(
                proposalConfig,
                fundingManagerFactoryConfig,
                authorizerFactoryConfig,
                paymentProcessorFactoryConfig,
                additionalModuleConfig
            );
        }
        vm.stopBroadcast();

        // Check if the proposal has been created correctly.

        assert(address(test_proposal) != address(0));

        address proposalToken = address(IProposal(test_proposal).token());
        assertEq(proposalToken, address(token));

        // Now we need to find the MilestoneManager. ModuleManager has a function called `listModules` that returns a list of
        // active modules, let's use that to get the address of the MilestoneManager.

        // TODO: Ideally this would be substituted by a check that that all mandatory modules implement their corresponding interfaces + the same for MilestoneManager

        address[] memory moduleAddresses =
            IProposal(test_proposal).listModules();
        uint lenModules = moduleAddresses.length;
        address proposalCreatedMilestoneManagerAddress;

        for (uint i; i < lenModules;) {
            try IMilestoneManager(moduleAddresses[i]).hasActiveMilestone()
            returns (bool) {
                proposalCreatedMilestoneManagerAddress = moduleAddresses[i];
                break;
            } catch {
                i++;
            }
        }

        IMilestoneManager proposalCreatedMilestoneManager =
            IMilestoneManager(proposalCreatedMilestoneManagerAddress);

        assertFalse(
            proposalCreatedMilestoneManager.hasActiveMilestone(),
            "Error in the MilestoneManager"
        );
        assertFalse(
            proposalCreatedMilestoneManager.isExistingMilestoneId(
                type(uint).max
            ),
            "Error in the MilestoneManager"
        );
        assertEq(
            proposalCreatedMilestoneManager.getMaximumContributors(),
            50,
            "Error in the MilestoneManager"
        );

        console2.log("\n\n");
        console2.log(
            "=================================================================================="
        );
        console2.log(
            "Proposal with Id %s created at address: %s ",
            test_proposal.proposalId(),
            address(test_proposal)
        );

        // ------------------------------------------------------------------------
        // Initialize FundingManager

        // IMPORTANT
        // =========
        // Due to how the underlying rebase mechanism works, it is necessary
        // to always have some amount of tokens in the proposal.
        // It's best, if the owner deposits them right after deployment.

        uint initialDeposit = 10e18;
        IFundingManager fundingManager =
            IFundingManager(address(test_proposal.fundingManager()));

        vm.startBroadcast(proposalOwnerPrivateKey);
        {
            token.mint(address(proposalOwner), initialDeposit);

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

        vm.startBroadcast(proposalOwnerPrivateKey);
        {
            proposalCreatedMilestoneManager.addMilestone(
                1 weeks,
                1000e18,
                contributors,
                bytes("Here could be a more detailed description")
            );

            proposalCreatedMilestoneManager.addMilestone(
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
        assertTrue(!(proposalCreatedMilestoneManager.isExistingMilestoneId(0)));
        assertTrue(proposalCreatedMilestoneManager.isExistingMilestoneId(1));

        assertTrue(proposalCreatedMilestoneManager.isContributor(1, alice.addr));
        assertTrue(proposalCreatedMilestoneManager.isContributor(2, alice.addr));

        console2.log(
            "=================================================================================="
        );
        console2.log("\n\n");

        return address(test_proposal);
    }
}
