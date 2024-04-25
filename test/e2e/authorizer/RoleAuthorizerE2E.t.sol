// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// SuT
import {AUT_Roles_v1} from "@aut/role/AUT_Roles_v1.sol";

//Internal Dependencies
import {
    E2ETest,
    IOrchestratorFactory_v1,
    IOrchestrator_v1
} from "test/e2e/E2ETest.sol";

// Modules that are used in this E2E test
import {FM_Rebasing_v1} from "@fm/rebasing/FM_Rebasing_v1.sol";
import {
    LM_PC_Bounties_v1,
    ILM_PC_Bounties_v1,
    IERC20PaymentClientBase_v1
} from "@lm/LM_PC_Bounties_v1.sol";

contract RoleAuthorizerE2E is E2ETest {
    // Module Configurations for the current E2E test. Should be filled during setUp() call.
    IOrchestratorFactory_v1.ModuleConfig[] moduleConfigurations;

    // E2E Test Variables
    address orchestratorOwner = makeAddr("orchestratorOwner");
    address orchestratorManager = makeAddr("orchestratorManager");
    address bountySubmitter = makeAddr("bountySubmitter");

    function setUp() public override {
        // Setup common E2E framework
        super.setUp();

        // Set Up individual Modules the E2E test is going to use and store their configurations:
        // NOTE: It's important to store the module configurations in order, since _create_E2E_Orchestrator() will copy from the array.
        // The order should be:
        //      moduleConfigurations[0]  => FundingManager
        //      moduleConfigurations[1]  => Authorizer
        //      moduleConfigurations[2]  => PaymentProcessor
        //      moduleConfigurations[3:] => Additional Logic Modules

        // FundingManager
        setUpRebasingFundingManager();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                rebasingFundingManagerMetadata,
                abi.encode(address(token)),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );

        // Authorizer
        setUpRoleAuthorizer();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                roleAuthorizerMetadata,
                abi.encode(address(this), address(this)),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );

        // PaymentProcessor
        setUpSimplePaymentProcessor();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                simplePaymentProcessorMetadata,
                bytes(""),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );

        // Additional Logic Modules
        setUpBountyManager();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                bountyManagerMetadata,
                bytes(""),
                abi.encode(true, EMPTY_DEPENDENCY_LIST)
            )
        );
    }

    function test_e2e_RoleAuthorizer() public {
        //--------------------------------------------------------------------------------
        // Orchestrator_v1 Initialization
        //--------------------------------------------------------------------------------
        IOrchestratorFactory_v1.OrchestratorConfig memory orchestratorConfig =
        IOrchestratorFactory_v1.OrchestratorConfig({
            owner: address(this),
            token: token
        });

        IOrchestrator_v1 orchestrator =
            _create_E2E_Orchestrator(orchestratorConfig, moduleConfigurations);

        FM_Rebasing_v1 fundingManager =
            FM_Rebasing_v1(address(orchestrator.fundingManager()));

        AUT_Roles_v1 authorizer =
            AUT_Roles_v1(address(orchestrator.authorizer()));

        // Find LM_PC_Bounties_v1
        LM_PC_Bounties_v1 bountyManager;

        address[] memory modulesList = orchestrator.listModules();
        for (uint i; i < modulesList.length; ++i) {
            try ILM_PC_Bounties_v1(modulesList[i]).isExistingBountyId(0)
            returns (bool) {
                bountyManager = LM_PC_Bounties_v1(modulesList[i]);
                break;
            } catch {
                continue;
            }
        }

        //--------------------------------------------------------------------------------
        // Assign Bounty Manager Roles
        //--------------------------------------------------------------------------------

        // we authorize the owner to create  bounties
        bountyManager.grantModuleRole(
            bountyManager.BOUNTY_ISSUER_ROLE(), address(orchestratorOwner)
        );

        // we authorize the manager to verify bounty claims
        bountyManager.grantModuleRole(
            bountyManager.VERIFIER_ROLE(), address(orchestratorManager)
        );

        // we authorize the bountySubmitter to submit bounty claims
        bountyManager.grantModuleRole(
            bountyManager.CLAIMANT_ROLE(), address(bountySubmitter)
        );

        // Since we deploy the orchestrator, with address(this) as owner and manager for easier setup,
        // we now assign them to two external addresses. In production these will be directly set on deployment.

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

        //--------------------------------------------------------------------------------
        // Set up seed deposit and initial deposit by users
        //--------------------------------------------------------------------------------

        uint initialDeposit = 10e18;
        token.mint(address(this), initialDeposit);
        token.approve(address(fundingManager), initialDeposit);
        fundingManager.deposit(initialDeposit);

        address funder1 = makeAddr("funder1");
        token.mint(funder1, 1000e18);

        vm.startPrank(funder1);
        {
            token.approve(address(fundingManager), 1000e18);
            fundingManager.deposit(1000e18);
        }
        vm.stopPrank();

        //--------------------------------------------------------------------------------
        // Create bounty
        //--------------------------------------------------------------------------------

        // Bounty details
        uint minimumPayoutAmount = 100e18;
        uint maximumPayoutAmount = 500e18;
        bytes memory details = "This is a test bounty";

        vm.prank(orchestratorOwner);
        uint bountyId = bountyManager.addBounty(
            minimumPayoutAmount, maximumPayoutAmount, details
        );

        // check that the bounty was created
        ILM_PC_Bounties_v1.Bounty memory bounty =
            bountyManager.getBountyInformation(1);
        assertEq(bounty.minimumPayoutAmount, minimumPayoutAmount);
        assertEq(bounty.maximumPayoutAmount, maximumPayoutAmount);
        assertEq(bounty.details, details);

        //--------------------------------------------------------------------------------
        // Worker submits bounty
        //--------------------------------------------------------------------------------
        vm.startPrank(bountySubmitter);
        ILM_PC_Bounties_v1.Contributor memory BOB =
            ILM_PC_Bounties_v1.Contributor(bountySubmitter, 200e18);

        ILM_PC_Bounties_v1.Contributor[] memory contribs =
            new ILM_PC_Bounties_v1.Contributor[](1);
        contribs[0] = BOB;

        uint claimId = bountyManager.addClaim(
            bountyId, contribs, "This is a test submission"
        );

        vm.stopPrank();

        //--------------------------------------------------------------------------------
        // Manager verifies bounty claim
        //--------------------------------------------------------------------------------
        vm.prank(orchestratorManager);
        bountyManager.verifyClaim(claimId, contribs);
    }
}
