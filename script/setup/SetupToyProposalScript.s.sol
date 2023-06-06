// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "../deployment/DeploymentScript.s.sol";

import {IMilestoneManager} from "src/modules/logicModule/MilestoneManager.sol";
import {IProposal} from "src/proposal/Proposal.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";



// NOTE: THIS WHOLE FILE CAN BE CONSIDERED A TODO

contract SetupToyProposalScript is Test, DeploymentScript {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint proposalOwnerPrivateKey = vm.envUint("PROPOSAL_OWNER_PRIVATE_KEY");
    address proposalOwner = vm.addr(deployerPrivateKey);



    /*
        // Before we can start a milestone, two things need to be present:
        // 1. A non-empty list of contributors for it
        // 2. The percentage of milestone funding to pay the contributors for the milestone.

        // So lets add Alice and Bob as contributors to the proposal.
        // Note the salary is specified in relation to the SALARY_PRECISION variable in the MilestoneManager.
    */


    //-------------------------------------------------------------------------
    // MOCK CONTRIBUTOR AND FUNDER INFORMATION

    // TODO: Use foundry cheatcodes to create mock funders and workers
    IMilestoneManager.Contributor alice = IMilestoneManager.Contributor(
        address(0xA11CE), 50_000_000, "AliceIdHash"
    );

    IMilestoneManager.Contributor bob =
        IMilestoneManager.Contributor(address(0x606), 50_000_000, "BobIdHash");

    IMilestoneManager.Contributor[] contributors;



    //This address is taken accordingly to the anvil private key of the env file
    address funder1 = address(0x976EA74026E726554dB657fA54763abd0C3a0aa9);
    uint funder1PrivateKey = vm.envUint("FUNDER_1_PRIVATE_KEY");

    function run() public override {
        ERC20Mock token;
        IProposal test_proposal;

        // First, we run the deployment script to deploy the factories, implementations and Beacons.
        DeploymentScript.run();

        // Then we deploy a mock ERC20 to act as funding token for the proposal. It has a public mint function.
        vm.startBroadcast(deployerPrivateKey);
        {
            token = new ERC20Mock("Mock", "MOCK");
        }
        vm.stopBroadcast();

         // ------------------------------------------------------------------------
        // Proposal Configuration Data
        // TODO: Clean up + revise

    address[] initialAuthorizedAddresses = [proposalOwner];

    // MilestoneManager config: Metadata, salary precision, fee percentage, fee treasury address
    IProposalFactory.ModuleConfig milestoneManagerFactoryConfig =
    IProposalFactory.ModuleConfig(
        milestoneManagerMetadata,
        abi.encode(100_000_000, 1_000_000, proposalOwner)
    );

    IProposalFactory.ModuleConfig authorizerFactoryConfig = IProposalFactory
        .ModuleConfig(authorizerMetadata, abi.encode(initialAuthorizedAddresses));

    IProposalFactory.ModuleConfig paymentProcessorFactoryConfig =
        IProposalFactory.ModuleConfig(paymentProcessorMetadata, bytes(""));


        IProposalFactory.ModuleConfig memory fundingManagerFactoryConfig =
        IProposalFactory.ModuleConfig(
            fundingManagerMetadata, abi.encode(address(token))
        );

        IProposalFactory.ProposalConfig memory proposalConfig = IProposalFactory
            .ProposalConfig({owner: proposalOwner, token: token});

        IProposalFactory.ModuleConfig[] memory optionalModules =
            new IProposalFactory.ModuleConfig[](1);
        optionalModules[0] = milestoneManagerFactoryConfig;


        // Create the proposal with the given configuration.
        // TODO: Add funding manager 
        vm.startBroadcast(proposalOwnerPrivateKey);
        test_proposal = proposalFactory.createProposal(
            proposalConfig,
            fundingManagerFactoryConfig,
            authorizerFactoryConfig,
            paymentProcessorFactoryConfig,
            optionalModules
        );
        vm.stopBroadcast();

        console2.log("Proposal Contract", address(test_proposal));

        // Check if the proposal has been created correctly.

        assert(address(test_proposal) != address(0));

        address proposalToken = address(IProposal(test_proposal).token());
        assertEq(proposalToken, address(token));

        // Now since ModuleManager is an abstract contract, inherited by ModuleManager and it has a function called `listModules` that returns a list of
        // active modules, let's use that to get the address of the Milestone Manager.

        address[] memory moduleAddresses =
            IProposal(test_proposal).listModules();
        uint lenModules = moduleAddresses.length;
        address proposalCreatedMilestoneManagerAddress;

        for (uint i; i < lenModules;) {
            try MilestoneManager(moduleAddresses[i]).hasActiveMilestone()
            returns (bool) {
                proposalCreatedMilestoneManagerAddress = moduleAddresses[i];
                break;
            } catch {
                i++;
            }
        }

        MilestoneManager proposalCreatedMilestoneManager =
            MilestoneManager(proposalCreatedMilestoneManagerAddress);

        assertTrue(
            !proposalCreatedMilestoneManager.hasActiveMilestone(),
            "Milestone manager wrong address inputted"
        );
        assertTrue(
            !proposalCreatedMilestoneManager.isExistingMilestoneId(
                type(uint).max
            ),
            "Milestone manager wrong address inputted"
        );
        assertEq(
            proposalCreatedMilestoneManager.getMaximumContributors(),
            50,
            "Milestone manager wrong address inputted"
        );

        // Initialize Milestone Manager

        contributors.push(alice);
        contributors.push(bob);

        vm.startBroadcast(proposalOwnerPrivateKey);

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

        // Initialize FundingManager

        // IMPORTANT
        // =========
        // Due to how the underlying rebase mechanism works, it is necessary
        // to always have some amount of tokens in the proposal.
        // It's best, if the owner deposits them right after deployment.

        uint initialDeposit = 10e18;
        token.mint(address(proposalOwner), initialDeposit);

        //fetch fundingmanager
        RebasingFundingManager fundingManager =
            RebasingFundingManager(address(test_proposal.fundingManager()));

        token.approve(address(fundingManager), initialDeposit);
        fundingManager.deposit(initialDeposit);

        vm.stopBroadcast();


        // Final checks

        // Let's confirm whether the milestone was added or not.
        // milestoneId 1 should exist and 0 shouldn't, since IDs start from 1.
        assertTrue(!(proposalCreatedMilestoneManager.isExistingMilestoneId(0)));
        assertTrue(proposalCreatedMilestoneManager.isExistingMilestoneId(1));

        assertTrue(proposalCreatedMilestoneManager.isContributor(1, alice.addr));
        assertTrue(proposalCreatedMilestoneManager.isContributor(2, alice.addr));

        // Seeing this great working on the proposal, funder1 decides to fund
        // the proposal with 1k of tokens.

        vm.startBroadcast(deployerPrivateKey);
        token.mint(funder1, 1000e18);
        vm.stopBroadcast();

        vm.startBroadcast(funder1PrivateKey);
        {
            token.approve(address(fundingManager), 1000e18);
            fundingManager.deposit(1000e18);
        }
        vm.stopBroadcast();
    }
}
