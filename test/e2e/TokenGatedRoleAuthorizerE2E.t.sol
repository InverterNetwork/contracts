// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {E2eTest} from "test/e2e/E2eTest.sol";
import "forge-std/console.sol";

//Internal Dependencies
import {ModuleTest, IModule, IOrchestrator} from "test/modules/ModuleTest.sol";
import {IOrchestratorFactory} from "src/factories/OrchestratorFactory.sol";
import {TokenGatedRoleAuthorizer} from "src/modules/authorizer/TokenGatedRoleAuthorizer.sol";

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

contract TokenGatedRoleAuthorizerE2E is E2eTest {
    address orchestratorOwner = makeAddr("orchestratorOwner");
    address orchestratorManager = makeAddr("orchestratorManager");
    address bountySubmitter = makeAddr("bountySubmitter");

    // Constants
    ERC20Mock token = new ERC20Mock("Mock", "MOCK");
    ERC20Mock gatingToken = new ERC20Mock("Gating Token", "GATOR");

    function test_e2e_RoleAuthorizer() public {
         // -----------INIT
        // address(this) creates a new orchestrator.
        IOrchestratorFactory.OrchestratorConfig memory orchestratorConfig =
        IOrchestratorFactory.OrchestratorConfig({
            owner: address(this),
            token: token
        });

        IOrchestrator orchestrator =
        _createNewOrchestratorWithAllModules_withTokenGatedRoleAuthorizer(
            orchestratorConfig
        );

        RebasingFundingManager fundingManager =
            RebasingFundingManager(address(orchestrator.fundingManager()));

        TokenGatedRoleAuthorizer authorizer =
            TokenGatedRoleAuthorizer(address(orchestrator.authorizer()));

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




        // Set up Bounty Manager Roles with different thresholds


        //Give the Orchestrator owner the power to change module roles
        authorizer.grantRole(
            authorizer.DEFAULT_ADMIN_ROLE(), orchestratorOwner
        );

        vm.startPrank(orchestratorOwner);


        // Choose the role to be modified. In this example we will use the BOUNTY_ADMIN_ROLE
        bytes32 bountyRoleId = authorizer.generateRoleId(
            address(bountyManager), bountyManager.BOUNTY_ADMIN_ROLE()
        );

        //First, we mark the Role as Token-Gated
        authorizer.setTokenGated(bountyRoleId, true);
        // Second, we set the token to be used for the Role as the gating token
        authorizer.grantRole(bountyRoleId, address(gatingToken));
        // Third, we set the minimum amount of tokens needed to be able to execute the Role
        authorizer.setThreshold(
            bountyRoleId,  address(gatingToken), 100
        );

        gatingToken.mint(orchestratorOwner, 101);


        bytes32 verifierRoleId = authorizer.generateRoleId(
            address(bountyManager), bountyManager.VERIFY_ADMIN_ROLE()
        );

        //First, we mark the Role as Token-Gated
        authorizer.setTokenGated(verifierRoleId, true);
        // Second, we set the token to be used for the Role as the gating token
        authorizer.grantRole(verifierRoleId, address(gatingToken));
        // Third, we set the minimum amount of tokens needed to be able to execute the Role
        authorizer.setThreshold(
            verifierRoleId,  address(gatingToken), 50
        );

        gatingToken.mint(orchestratorManager, 51);



        bytes32 claimRoleId = authorizer.generateRoleId(
            address(bountyManager), bountyManager.CLAIM_ADMIN_ROLE()
        );

        //First, we mark the Role as Token-Gated
        authorizer.setTokenGated(claimRoleId, true);
        // Second, we set the token to be used for the Role as the gating token
        authorizer.grantRole(claimRoleId, address(gatingToken));
        // Third, we set the minimum amount of tokens needed to be able to execute the Role
        authorizer.setThreshold(
            claimRoleId,  address(gatingToken), 25
        );

        gatingToken.mint(bountySubmitter, 26);


        vm.stopPrank();

        // We mint different amounts to different actors


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
        bytes memory details = "This is a test bounty";


        // Create bounty
        vm.prank(orchestratorOwner);
        uint bountyId = bountyManager.addBounty(
            100e18, 500e18, details
        );

        // others can't add it

        // check that the bounty was created
        IBountyManager.Bounty memory bounty =
            bountyManager.getBountyInformation(1);
        assertEq(bounty.minimumPayoutAmount, 100e18);
        assertEq(bounty.maximumPayoutAmount, 500e18);
        assertEq(bounty.details, details);

        // Worker submits bounty
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

        // the worker can't verifiy it



    }
    function _createNewOrchestratorWithAllModules_withTokenGatedRoleAuthorizer(
        IOrchestratorFactory.OrchestratorConfig memory config
    ) internal returns (IOrchestrator) {
        IOrchestratorFactory.ModuleConfig[] memory optionalModules =
            new IOrchestratorFactory.ModuleConfig[](1);
        optionalModules[0] = bountyManagerFactoryConfig;

        IOrchestratorFactory.ModuleConfig memory
            rebasingFundingManagerFactoryConfig = IOrchestratorFactory
                .ModuleConfig(
                rebasingFundingManagerMetadata,
                abi.encode(address(config.token)),
                abi.encode(hasDependency, dependencies)
            );

        return orchestratorFactory.createOrchestrator(
            config,
            rebasingFundingManagerFactoryConfig,
            tokenRoleAuthorizerFactoryConfig,
            paymentProcessorFactoryConfig,
            optionalModules
        );
    }

}
