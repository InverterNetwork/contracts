// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {
    E2ETest,
    IOrchestratorFactory_v1,
    IOrchestrator_v1
} from "test/e2e/E2ETest.sol";
import {AUT_Roles_v2} from "@aut/role/AUT_Roles_v2.sol";

// SuT
import {
    LM_PC_Bounties_v2, ILM_PC_Bounties_v2
} from "@lm/LM_PC_Bounties_v2.sol";
import {FM_DepositVault_v1} from "@fm/depositVault/FM_DepositVault_v1.sol";
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
        setUpDepositVaultFundingManager();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                depositVaultMetadata, abi.encode(address(token))
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

        FM_DepositVault_v1 fundingManager =
            FM_DepositVault_v1(address(orchestrator.fundingManager()));

        AUT_Roles_v2 authorizer =
            AUT_Roles_v2(address(orchestrator.authorizer()));

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

        // =========
        // Setting up Roles

        // In the upcoming section we will use different permissioned functions
        // For which we need to create roles, add function access and assign the roles
        // to the different actors

        // The main functions that we will use are:
        // - addBounty
        // - addClaim
        // - verifyClaim
        // For demonstration purposes we will set up the roles in reverse order

        // verifyClaim
        // for this function we will set up the VERIFIER role
        // First we define the Members of the role in an array
        // Verifiers approve claim

        address verifier1 = makeAddr("verifier 1");

        {
            address[] memory roleMembers = new address[](1);
            roleMembers[0] = verifier1;

            // Then we select the target contract and function selectors
            address[] memory targets = new address[](1);
            targets[0] = address(bountyManager);

            bytes4[][] memory selectors = new bytes4[][](1);
            selectors[0] = new bytes4[](1);
            selectors[0][0] = bountyManager.verifyClaim.selector;

            // Create role, adapt permissions and set members
            orchestrator.authorizer().createRoleAndAddAccessPermissions(
                "VERIFIER",
                authorizer.getAdminRole(),
                roleMembers,
                targets,
                selectors
            );
        }

        // addClaim
        // Instead of a assigning a role to this function we will make it public
        // so that anyone can call it

        authorizer.addAccessPermission(
            address(bountyManager),
            bountyManager.addClaim.selector,
            authorizer.PUBLIC_ROLE()
        );

        // addBounty
        // addBounty allows the caller to create a new bounty
        // This could be a high level admin function so we will only allow the workflow admin to call it
        // As the initial admin of the workflow already has access to all permissioned functions
        // we wont set up anything for the access to work
        // The initial admin in this case is this contract itself, so we dont need to prank the calls

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

        ILM_PC_Bounties_v2.Contributor[] memory contribs =
            new ILM_PC_Bounties_v2.Contributor[](2);
        contribs[0] = contrib1;
        contribs[1] = contrib2;

        bytes memory claimDetails = "This is a test submission";

        vm.prank(address(0xA11CE));
        uint claimId = bountyManager.addClaim(bountyId, contribs, claimDetails);

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
