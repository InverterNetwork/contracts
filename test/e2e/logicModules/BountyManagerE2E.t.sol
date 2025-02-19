// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {
    E2ETest,
    IOrchestratorFactory_v1,
    IOrchestrator_v1
} from "test/e2e/E2ETest.sol";

// SuT
import {
    LM_PC_Bounties_v2, ILM_PC_Bounties_v2
} from "@lm/LM_PC_Bounties_v2.sol";
import {FM_Rebasing_v1} from "@fm/rebasing/FM_Rebasing_v1.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

contract BountyManagerE2E is E2ETest {
    // Module Configurations for the current E2E test. Should be filled during setUp() call.
    IOrchestratorFactory_v1.ModuleConfig[] moduleConfigurations;

    address bountyAdmin = makeAddr("bountyAdmin");
    address claimAdmin = makeAddr("claimAdmin");
    address verifyAdmin = makeAddr("verifyAdmin");

    // Let's create a list of contributors
    address contributor1 = makeAddr("contributor 1");
    address contributor2 = makeAddr("contributor 2");
    address contributor3 = makeAddr("contributor 3");

    // Constants
    uint constant _SENTINEL = type(uint).max;

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
        setUpRoleAuthorizer();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                roleAuthorizerMetadata, abi.encode(address(this))
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

    function test_e2e_BountyManagerLifecycle() public {
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

        FM_Rebasing_v1 fundingManager =
            FM_Rebasing_v1(address(orchestrator.fundingManager()));

        LM_PC_Bounties_v2 bountyManager;

        address[] memory modulesList = orchestrator.listModules();
        for (uint i; i < modulesList.length; ++i) {
            if (
                ERC165Upgradeable(modulesList[i]).supportsInterface(
                    type(ILM_PC_Bounties_v2).interfaceId
                )
            ) {
                bountyManager = LM_PC_Bounties_v2(modulesList[i]);
                break;
            }
        }

        // we authorize the deployer of the orchestrator as the bounty admin
        bountyManager.grantModuleRole(
            bountyManager.BOUNTY_ISSUER_ROLE(), address(this)
        );
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

        // Owner sets up bounty
        uint minimumPayoutAmount = 100e18;
        uint maximumPayoutAmount = 500e18;
        bytes memory details = "This is a test bounty";

        uint bountyId = bountyManager.addBounty(
            minimumPayoutAmount, maximumPayoutAmount, details
        );

        // Workers submit bounty
        ILM_PC_Bounties_v2.Contributor memory contrib1 =
            ILM_PC_Bounties_v2.Contributor(address(0xA11CE), 150e18);
        ILM_PC_Bounties_v2.Contributor memory contrib2 =
            ILM_PC_Bounties_v2.Contributor(address(0xb0b), 150e18);

        // auth.setIsAuthorized(address(0xA11CE), true);
        bountyManager.grantModuleRole(
            bountyManager.CLAIMANT_ROLE(), address(0xA11CE)
        );

        ILM_PC_Bounties_v2.Contributor[] memory contribs =
            new ILM_PC_Bounties_v2.Contributor[](2);
        contribs[0] = contrib1;
        contribs[1] = contrib2;

        bytes memory claimDetails = "This is a test submission";

        vm.prank(address(0xA11CE));
        uint claimId = bountyManager.addClaim(bountyId, contribs, claimDetails);

        // Verifiers approve claim

        address verifier1 = makeAddr("verifier 1");

        // auth.setIsAuthorized(verifier1, true);
        bountyManager.grantModuleRole(bountyManager.VERIFIER_ROLE(), verifier1);

        vm.prank(verifier1);
        bountyManager.verifyClaim(claimId, contribs);

        // Bounty has been paid out
        assertEq(token.balanceOf(contrib1.addr), 150e18);
        assertEq(token.balanceOf(contrib2.addr), 150e18);

        // Lets create another Claim for the same bounty
        vm.prank(address(0xA11CE));
        claimId = bountyManager.addClaim(bountyId, contribs, claimDetails);

        // Verifiers approve claim
        vm.prank(verifier1);
        bountyManager.verifyClaim(claimId, contribs);

        // Bounty has been paid out
        assertEq(token.balanceOf(contrib1.addr), 2 * 150e18);
        assertEq(token.balanceOf(contrib2.addr), 2 * 150e18);
    }
}
