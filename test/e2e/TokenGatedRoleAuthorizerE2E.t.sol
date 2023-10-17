// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {E2eTest} from "test/e2e/E2eTest.sol";
import "forge-std/console.sol";

//Internal Dependencies
import {ModuleTest, IModule, IOrchestrator} from "test/modules/ModuleTest.sol";
import {IOrchestratorFactory} from "src/factories/OrchestratorFactory.sol";
import {TokenGatedRoleAuthorizer} from
    "src/modules/authorizer/TokenGatedRoleAuthorizer.sol";

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

    function test_e2e_TokenGatedRoleAuthorizer() public {
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

        //--------------------------------------------------------------------------------
        // Set up Bounty Manager Roles with different thresholds
        //--------------------------------------------------------------------------------

        //Give the Orchestrator owner the power to change module roles
        authorizer.grantRole(authorizer.DEFAULT_ADMIN_ROLE(), orchestratorOwner);

        vm.startPrank(orchestratorOwner);
        {
            // Make the BOUNTY_ADMIN_ROLE token-gated by GATOR token and set the threshold
            bytes32 bountyRoleId = authorizer.generateRoleId(
                address(bountyManager), bountyManager.BOUNTY_ISSUER_ROLE()
            );
            authorizer.setTokenGated(bountyRoleId, true);
            authorizer.grantRole(bountyRoleId, address(gatingToken));
            authorizer.setThreshold(bountyRoleId, address(gatingToken), 100);

            // We mint 101 tokens to the orchestrator owner so they can create bounties
            gatingToken.mint(orchestratorOwner, 101);

            // Make the VERIFY_ADMIN_ROLE token-gated by GATOR token and set the threshold
            bytes32 verifierRoleId = authorizer.generateRoleId(
                address(bountyManager), bountyManager.VERIFIER_ROLE()
            );
            authorizer.setTokenGated(verifierRoleId, true);
            authorizer.grantRole(verifierRoleId, address(gatingToken));
            authorizer.setThreshold(verifierRoleId, address(gatingToken), 50);

            // We mint 51 tokens to the orchestrator manager so they can verify bounties
            gatingToken.mint(orchestratorManager, 51);

            // Make the CLAIM_ADMIN_ROLE token-gated by GATOR token and set the threshold
            bytes32 claimRoleId = authorizer.generateRoleId(
                address(bountyManager), bountyManager.CLAIMANT_ROLE()
            );
            authorizer.setTokenGated(claimRoleId, true);
            authorizer.grantRole(claimRoleId, address(gatingToken));
            authorizer.setThreshold(claimRoleId, address(gatingToken), 25);

            // We mint 26 tokens to the bounty submitter so they can submit bounties
            gatingToken.mint(bountySubmitter, 26);
        }
        vm.stopPrank();

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
        vm.prank(orchestratorOwner);
        uint bountyId =
            bountyManager.addBounty(100e18, 500e18, "This is a test bounty");

        // others can't add it
        vm.expectRevert();
        vm.prank(orchestratorManager);
        bountyManager.addBounty(100e18, 500e18, "This is a test bounty");

        vm.expectRevert();
        vm.prank(bountySubmitter);
        bountyManager.addBounty(100e18, 500e18, "This is a test bounty");

        // Validate
        IBountyManager.Bounty memory bounty =
            bountyManager.getBountyInformation(1);
        assertEq(bounty.minimumPayoutAmount, 100e18);
        assertEq(bounty.maximumPayoutAmount, 500e18);
        assertEq(bounty.details, "This is a test bounty");

        //--------------------------------------------------------------------------------
        // Worker submits bounty
        //--------------------------------------------------------------------------------
        vm.startPrank(bountySubmitter);
        IBountyManager.Contributor memory BOB =
            IBountyManager.Contributor(bountySubmitter, 200e18);

        IBountyManager.Contributor[] memory contribs =
            new IBountyManager.Contributor[](1);
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

        // the worker can't verifiy it
        vm.expectRevert();
        vm.prank(bountySubmitter);
        bountyManager.addBounty(100e18, 500e18, "This is a test bounty");
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
