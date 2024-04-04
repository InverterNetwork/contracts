// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

//Internal Dependencies
import {
    E2ETest, IOrchestratorFactory, IOrchestrator
} from "test/e2e/E2ETest.sol";

// SuT
import {
    BountyManager,
    IBountyManager
} from "src/modules/logicModule/BountyManager.sol";
import {RebasingFundingManager} from
    "src/modules/fundingManager/rebasing/RebasingFundingManager.sol";

contract BountyManagerE2E is E2ETest {
    // Module Configurations for the current E2E test. Should be filled during setUp() call.
    IOrchestratorFactory.ModuleConfig[] moduleConfigurations;

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
            IOrchestratorFactory.ModuleConfig(
                rebasingFundingManagerMetadata,
                abi.encode(address(token)),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );

        // Authorizer
        setUpRoleAuthorizer();
        moduleConfigurations.push(
            IOrchestratorFactory.ModuleConfig(
                roleAuthorizerMetadata,
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

    function test_e2e_BountyManagerLifecycle() public {
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

        RebasingFundingManager fundingManager =
            RebasingFundingManager(address(orchestrator.fundingManager()));

        BountyManager bountyManager;

        // Find BountyManager
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
        IBountyManager.Contributor memory contrib1 =
            IBountyManager.Contributor(address(0xA11CE), 150e18);
        IBountyManager.Contributor memory contrib2 =
            IBountyManager.Contributor(address(0xb0b), 150e18);

        //auth.setIsAuthorized(address(0xA11CE), true);
        bountyManager.grantModuleRole(
            bountyManager.CLAIMANT_ROLE(), address(0xA11CE)
        );

        IBountyManager.Contributor[] memory contribs =
            new IBountyManager.Contributor[](2);
        contribs[0] = contrib1;
        contribs[1] = contrib2;

        bytes memory claimDetails = "This is a test submission";

        vm.prank(address(0xA11CE));
        uint claimId = bountyManager.addClaim(bountyId, contribs, claimDetails);

        // Verifiers approve claim

        address verifier1 = makeAddr("verifier 1");

        //auth.setIsAuthorized(verifier1, true);
        bountyManager.grantModuleRole(bountyManager.VERIFIER_ROLE(), verifier1);

        vm.prank(verifier1);
        bountyManager.verifyClaim(claimId, contribs);

        // Bounty has been paid out
        assertEq(token.balanceOf(contrib1.addr), 150e18);
        assertEq(token.balanceOf(contrib2.addr), 150e18);

        //Lets create another Claim for the same bounty
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
