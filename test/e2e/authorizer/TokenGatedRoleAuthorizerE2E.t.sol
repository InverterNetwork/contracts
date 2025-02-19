// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {
    E2ETest,
    IOrchestratorFactory_v1,
    IOrchestrator_v1,
    ERC20Mock
} from "test/e2e/E2ETest.sol";

// SuT
import {AUT_TokenGated_Roles_v1} from "@aut/role/AUT_TokenGated_Roles_v1.sol";

// Modules that are used in this E2E test
import {
    LM_PC_Bounties_v2, ILM_PC_Bounties_v2
} from "@lm/LM_PC_Bounties_v2.sol";
import {FM_Rebasing_v1} from "@fm/rebasing/FM_Rebasing_v1.sol";

contract TokenGatedRoleAuthorizerE2E is E2ETest {
    // Module Configurations for the current E2E test. Should be filled during setUp() call.
    IOrchestratorFactory_v1.ModuleConfig[] moduleConfigurations;

    // E2E Test Variables
    address orchestratorAdmin = makeAddr("orchestratorAdmin");
    address bountyVerifier = makeAddr("bountyVerifier");
    address bountySubmitter = makeAddr("bountySubmitter");

    ERC20Mock gatingToken = new ERC20Mock("Gating Token", "GATOR");

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
                rebasingFundingManagerMetadata, abi.encode(address(token))
            )
        );

        // Authorizer
        setUpTokenGatedRoleAuthorizer();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                tokenRoleAuthorizerMetadata, abi.encode(address(this))
            )
        );

        // PaymentProcessor
        setUpSimplePaymentProcessor();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                simplePaymentProcessorMetadata, bytes("")
            )
        );

        // Additional Logic Modules
        setUpBountyManager();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                bountyManagerMetadata, bytes("")
            )
        );
    }

    function test_e2e_TokenGatedRoleAuthorizer() public {
        //--------------------------------------------------------------------------
        // Orchestrator_v1 Initialization
        //--------------------------------------------------------------------------
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
        IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        IOrchestrator_v1 orchestrator =
            _create_E2E_Orchestrator(workflowConfig, moduleConfigurations);

        AUT_TokenGated_Roles_v1 authorizer =
            AUT_TokenGated_Roles_v1(address(orchestrator.authorizer()));

        FM_Rebasing_v1 fundingManager =
            FM_Rebasing_v1(address(orchestrator.fundingManager()));

        // Find LM_PC_Bounties_v2
        LM_PC_Bounties_v2 bountyManager;

        address[] memory modulesList = orchestrator.listModules();
        for (uint i; i < modulesList.length; ++i) {
            try ILM_PC_Bounties_v2(modulesList[i]).isExistingBountyId(0)
            returns (bool) {
                bountyManager = LM_PC_Bounties_v2(modulesList[i]);
                break;
            } catch {
                continue;
            }
        }

        //--------------------------------------------------------------------------
        // Set up Bounty Manager Roles with different thresholds
        //--------------------------------------------------------------------------

        // Give the Orchestrator_v1 Admin the power to change module roles
        authorizer.grantRole(authorizer.DEFAULT_ADMIN_ROLE(), orchestratorAdmin);

        vm.startPrank(orchestratorAdmin);
        {
            // Make the BOUNTY_ADMIN_ROLE token-gated by GATOR token and set the threshold
            bytes32 bountyRoleId = authorizer.generateRoleId(
                address(bountyManager), bountyManager.BOUNTY_ISSUER_ROLE()
            );
            authorizer.setTokenGated(bountyRoleId, true);
            authorizer.setThreshold(bountyRoleId, address(gatingToken), 100);
            authorizer.grantRole(bountyRoleId, address(gatingToken));

            // We mint 101 tokens to the orchestrator admin so they can create bounties
            gatingToken.mint(orchestratorAdmin, 101);

            // Make the VERIFY_ADMIN_ROLE token-gated by GATOR token and set the threshold
            bytes32 verifierRoleId = authorizer.generateRoleId(
                address(bountyManager), bountyManager.VERIFIER_ROLE()
            );
            authorizer.setTokenGated(verifierRoleId, true);
            authorizer.setThreshold(verifierRoleId, address(gatingToken), 50);
            authorizer.grantRole(verifierRoleId, address(gatingToken));

            // We mint 51 tokens to the orchestrator manager so they can verify bounties
            gatingToken.mint(bountyVerifier, 51);

            // Make the CLAIM_ADMIN_ROLE token-gated by GATOR token and set the threshold
            bytes32 claimRoleId = authorizer.generateRoleId(
                address(bountyManager), bountyManager.CLAIMANT_ROLE()
            );
            authorizer.setTokenGated(claimRoleId, true);
            authorizer.setThreshold(claimRoleId, address(gatingToken), 25);
            authorizer.grantRole(claimRoleId, address(gatingToken));

            // We mint 26 tokens to the bounty submitter so they can submit bounties
            gatingToken.mint(bountySubmitter, 26);
        }
        vm.stopPrank();

        //--------------------------------------------------------------------------
        // Set up seed deposit and initial deposit by users
        //--------------------------------------------------------------------------

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

        //--------------------------------------------------------------------------
        // Create bounty
        //--------------------------------------------------------------------------
        vm.prank(orchestratorAdmin);
        uint bountyId =
            bountyManager.addBounty(100e18, 500e18, "This is a test bounty");

        // others can't add it
        vm.expectRevert();
        vm.prank(bountyVerifier);
        bountyManager.addBounty(100e18, 500e18, "This is a test bounty");

        vm.expectRevert();
        vm.prank(bountySubmitter);
        bountyManager.addBounty(100e18, 500e18, "This is a test bounty");

        // Validate
        ILM_PC_Bounties_v2.Bounty memory bounty =
            bountyManager.getBountyInformation(1);
        assertEq(bounty.minimumPayoutAmount, 100e18);
        assertEq(bounty.maximumPayoutAmount, 500e18);
        assertEq(bounty.details, "This is a test bounty");

        //--------------------------------------------------------------------------
        // Worker submits bounty
        //--------------------------------------------------------------------------
        vm.startPrank(bountySubmitter);
        ILM_PC_Bounties_v2.Contributor memory BOB =
            ILM_PC_Bounties_v2.Contributor(bountySubmitter, 200e18);

        ILM_PC_Bounties_v2.Contributor[] memory contribs =
            new ILM_PC_Bounties_v2.Contributor[](1);
        contribs[0] = BOB;

        uint claimId = bountyManager.addClaim(
            bountyId, contribs, "This is a test submission"
        );

        vm.stopPrank();

        //--------------------------------------------------------------------------
        // Manager verifies bounty claim
        //--------------------------------------------------------------------------
        vm.prank(bountyVerifier);
        bountyManager.verifyClaim(claimId, contribs);

        // the worker can't verifiy it
        vm.expectRevert();
        vm.prank(bountySubmitter);
        bountyManager.addBounty(100e18, 500e18, "This is a test bounty");
    }
}
