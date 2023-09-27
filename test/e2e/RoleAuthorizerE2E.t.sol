// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {E2eTest} from "test/e2e/E2eTest.sol";
import "forge-std/console.sol";

//Internal Dependencies
import {ModuleTest, IModule, IOrchestrator} from "test/modules/ModuleTest.sol";
import {IOrchestratorFactory} from "src/factories/OrchestratorFactory.sol";
import {RoleAuthorizer} from "src/modules/authorizer/RoleAuthorizer.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {RebasingFundingManager} from
    "src/modules/fundingManager/RebasingFundingManager.sol";
// SuT
import {
    BountyManager,
    IBountyManager,
    IERC20PaymentClient
} from "src/modules/logicModule/BountyManager.sol";

import {StreamingPaymentProcessor} from
    "src/modules/paymentProcessor/StreamingPaymentProcessor.sol";

import {
    IStreamingPaymentProcessor,
    IERC20PaymentClient
} from "src/modules/paymentProcessor/IStreamingPaymentProcessor.sol";


// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract RoleAuthorizerE2E is E2eTest {
    address orchestratorOwner = makeAddr("orchestratorOwner");
    address orchestratorManager = makeAddr("orchestratorManager");
    address bountySubmitter = makeAddr("bountySubmitter");

    // Constants
    ERC20Mock token = new ERC20Mock("Mock", "MOCK");

    function test_e2e_RoleAuthorizer() public {
         // -----------INIT
        // address(this) creates a new orchestrator.
        IOrchestratorFactory.OrchestratorConfig memory orchestratorConfig =
        IOrchestratorFactory.OrchestratorConfig({
            owner: address(this),
            token: token
        });

        IOrchestrator orchestrator =
        _createNewOrchestratorWithAllModules(
            orchestratorConfig
        );

        RebasingFundingManager fundingManager =
            RebasingFundingManager(address(orchestrator.fundingManager()));

        RoleAuthorizer authorizer =
            RoleAuthorizer(address(orchestrator.authorizer()));

        // Find BountyManager
        BountyManager bountyManager;

        address[] memory modulesList = orchestrator.listModules();
        for (uint i; i < modulesList.length; ++i) {
            try IBountyManager(modulesList[i]).isExistingBountyId(0) returns (
                bool
            ) {
                bountyManager = BountyManager(modulesList[i]);
                break;
            } catch {
                continue;
            }
        }




        // Assign Bounty Manager Roles


        // we authorize the owner to create  bounties
        bountyManager.grantModuleRole(
            bountyManager.BOUNTY_ADMIN_ROLE(), address(orchestratorOwner)
        );

        // we authorize the manager to verify bounty claims
        bountyManager.grantModuleRole(
            bountyManager.VERIFY_ADMIN_ROLE(), address(orchestratorManager)
        );

        // we authorize the bountySubmitter to submit bounty claims
        bountyManager.grantModuleRole(
            bountyManager.CLAIM_ADMIN_ROLE(), address(bountySubmitter)
        );


        // we grant manager role to managerAddress
        bytes32 managerRole = authorizer.getManagerRole();
        authorizer.grantRole(managerRole, address(orchestratorManager));
        authorizer.renounceRole(managerRole, address(this));
        assertTrue(authorizer.hasRole(managerRole, orchestratorManager));
        assertEq(authorizer.getRoleMemberCount(managerRole), 1);


        //we grant owner role to ownerAddress
        bytes32 ownerRole = authorizer.getOwnerRole();
        authorizer.grantRole(ownerRole, address(orchestratorOwner));
        authorizer.renounceRole(ownerRole, address(this));
        assertTrue(authorizer.hasRole(ownerRole, orchestratorOwner));
        assertEq(authorizer.getRoleMemberCount(ownerRole), 1);


        // Funders deposit funds

        // IMPORTANT
        // =========
        // Due to how the underlying rebase mechanism works, it is necessary
        // to always have some amount of tokens in the orchestrator.
        // It's best, if the owner deposits them right after deployment.
        uint initialDeposit = 10e18;
        token.mint(address(this), initialDeposit);
        token.approve(address(fundingManager), initialDeposit);
        fundingManager.deposit(initialDeposit);

        // Seeing this great working on the orchestrator, funder1 decides to fund
        // the orchestrator with 1k of tokens.
        address funder1 = makeAddr("funder1");

        token.mint(funder1, 1000e18);

        vm.startPrank(funder1);
        {
            token.approve(address(fundingManager), 1000e18);
            fundingManager.deposit(1000e18);
        }
        vm.stopPrank();

        // Bounty details
        uint minimumPayoutAmount = 100e18;
        uint maximumPayoutAmount = 500e18;
        bytes memory details = "This is a test bounty";

        // Create bounty
        vm.prank(orchestratorOwner);
        uint bountyId = bountyManager.addBounty(
            minimumPayoutAmount, maximumPayoutAmount, details
        );

        // check that the bounty was created
        IBountyManager.Bounty memory bounty =
            bountyManager.getBountyInformation(1);
        assertEq(bounty.minimumPayoutAmount, minimumPayoutAmount);
        assertEq(bounty.maximumPayoutAmount, maximumPayoutAmount);
        assertEq(bounty.details, details);

        // Workers submit bounty
        vm.startPrank(bountySubmitter);
            IBountyManager.Contributor memory BOB =
        IBountyManager.Contributor(bountySubmitter, 200e18);
        
            IBountyManager.Contributor[] memory contribs =
            new IBountyManager.Contributor[](1);
            contribs[0] = BOB;

        bytes memory claimDetails = "This is a test submission";

        uint claimId = bountyManager.addClaim(bountyId, contribs, claimDetails);

        vm.stopPrank(); 

        // Manager verifies bounty claim
        vm.prank(orchestratorManager);
        bountyManager.verifyClaim(claimId, contribs);




    }


}
