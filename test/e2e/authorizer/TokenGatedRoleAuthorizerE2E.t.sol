// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

//Internal Dependencies
import {
    E2ETest,
    IOrchestratorFactory,
    IOrchestrator,
    ERC20Mock
} from "test/e2e/E2ETest.sol";

// SuT
import {TokenGatedRoleAuthorizer} from
    "src/modules/authorizer/TokenGatedRoleAuthorizer.sol";

// Modules that are used in this E2E test
import {
    BountyManager,
    IBountyManager
} from "src/modules/logicModule/BountyManager.sol";
import {RebasingFundingManager} from
    "src/modules/fundingManager/rebasing/RebasingFundingManager.sol";

contract TokenGatedRoleAuthorizerE2E is E2ETest {
    // Module Configurations for the current E2E test. Should be filled during setUp() call.
    IOrchestratorFactory.ModuleConfig[] moduleConfigurations;

    // E2E Test Variables
    address orchestratorOwner = makeAddr("orchestratorOwner");
    address orchestratorManager = makeAddr("orchestratorManager");
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
            IOrchestratorFactory.ModuleConfig(
                rebasingFundingManagerMetadata,
                abi.encode(address(token)),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );

        // Authorizer
        setUpTokenGatedRoleAuthorizer();
        moduleConfigurations.push(
            IOrchestratorFactory.ModuleConfig(
                tokenRoleAuthorizerMetadata,
                abi.encode(address(this), address(this)),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );

        // PaymentProcessor
        setUpSimplePaymentProcessor();
        moduleConfigurations.push(
            IOrchestratorFactory.ModuleConfig(
                simplePaymentProcessorMetadata,
                bytes(""),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );

        // Additional Logic Modules
        setUpBountyManager();
        moduleConfigurations.push(
            IOrchestratorFactory.ModuleConfig(
                bountyManagerMetadata,
                bytes(""),
                abi.encode(true, EMPTY_DEPENDENCY_LIST)
            )
        );
    }

    function test_e2e_TokenGatedRoleAuthorizer() public {
        //--------------------------------------------------------------------------------
        // Orchestrator Initialization
        //--------------------------------------------------------------------------------
        IOrchestratorFactory.OrchestratorConfig memory orchestratorConfig =
        IOrchestratorFactory.OrchestratorConfig({
            owner: address(this),
            token: token
        });

        IOrchestrator orchestrator =
            _create_E2E_Orchestrator(orchestratorConfig, moduleConfigurations);

        TokenGatedRoleAuthorizer authorizer =
            TokenGatedRoleAuthorizer(address(orchestrator.authorizer()));

        RebasingFundingManager fundingManager =
            RebasingFundingManager(address(orchestrator.fundingManager()));

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
}
