// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// SuT
import {AUT_Roles_v2} from "@aut/role/AUT_Roles_v2.sol";

// Internal Dependencies
import {
    E2ETest,
    IOrchestratorFactory_v1,
    IOrchestrator_v2
} from "test/e2e/E2ETest.sol";

// Modules that are used in this E2E test
import {FM_DepositVault_v1} from "@fm/depositVault/FM_DepositVault_v1.sol";
import {
    LM_PC_Bounties_v3,
    ILM_PC_Bounties_v3,
    IERC20PaymentClientBase_v3
} from "@lm/LM_PC_Bounties_v3.sol";

contract RoleAuthorizerE2E1 is E2ETest {
    // Module Configurations for the current E2E test. Should be filled during setUp() call.
    IOrchestratorFactory_v1.ModuleConfig[] moduleConfigurations;

    // E2E Test Variables
    address initialAdmin = makeAddr("initialAdmin");
    address bountyIssuer = makeAddr("bountyIssuer");
    address bountyVerifier = makeAddr("bountyVerifier");
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
                roleAuthorizerMetadata,
                abi.encode(initialAdmin) //this sets the given address to be the initialAdmin
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

    function test_e2e_RoleAuthorizer(address caller_) public {
        //--------------------------------------------------------------------------
        // Orchestrator_v2 Initialization
        //--------------------------------------------------------------------------
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
        IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        IOrchestrator_v2 orchestrator =
            _create_E2E_Orchestrator(workflowConfig, moduleConfigurations);

        FM_DepositVault_v1 fundingManager =
            FM_DepositVault_v1(address(orchestrator.fundingManager()));

        AUT_Roles_v2 authorizer =
            AUT_Roles_v2(address(orchestrator.authorizer()));

        // Find LM_PC_Bounties_v3
        LM_PC_Bounties_v3 bountyManager;

        address[] memory modulesList = orchestrator.listModules();
        for (uint i; i < modulesList.length; ++i) {
            try ILM_PC_Bounties_v3(modulesList[i]).isExistingBountyId(0)
            returns (bool) {
                bountyManager = LM_PC_Bounties_v3(modulesList[i]);
                break;
            } catch {
                continue;
            }
        }

        //--------------------------------------------------------------------------
        // Create Bounty Manager Roles
        //--------------------------------------------------------------------------

        // This subsection divider is to prevent stack too deep errors
        {
            // First we define new Roles that we want to have in the system
            // and assign initial members to them

            // BOUNTY_ISSUER Role
            // Lets start with the Bounty Issuer Role
            // For that we define a name
            string memory roleName = "BOUNTY_ISSUER";
            // We define which role will be the admin of the new role
            // (Admin Roles can add and remove members to that role)
            // In this case we will use the initial admin role (number 0)
            bytes32 roleAdmin = authorizer.getAdminRole(); // Alternatively bytes32(uint(0))

            // We define the initial members of the role
            address[] memory roleMembers = new address[](1);
            roleMembers[0] = bountyIssuer;

            // With the above defined values we can now create the role
            // We save the Id of the role in a variable
            // The function is initally only callable by the initial admin
            // but can be adapted like any other permissioned function (see down below)
            vm.prank(initialAdmin);
            bytes32 bountyIssuerRoleId =
                authorizer.createRole(roleName, roleAdmin, roleMembers);

            // Public Role (Bounty Submitter)
            // For the Bounty Submitter we choose the public role
            // Which allows anyone to join the role
            // We fetch the roleId of the public role from the authorizer
            bytes32 bountySubmitterRoleId = authorizer.PUBLIC_ROLE(); // Alternatively bytes32(uint(1))

            //--------------------------------------------------------------------------
            // Define Role Permissions
            //--------------------------------------------------------------------------

            // Now lets define the permissions for the roles
            // Starting with the Bounty Issuer Role
            // For this we will use the addAccessPermission function in the authorizer

            // First we define the target and function selector
            // The target is the address of the bountyManager
            address target = address(bountyManager);
            // The function selector is the addBounty function
            bytes4 selector = bountyManager.addBounty.selector;
            // With the previously created role and respective id
            // We can now add the permission to the bounty issuer role
            vm.prank(initialAdmin);
            authorizer.addAccessPermission(target, selector, bountyIssuerRoleId);

            // Lets check that the role holder is permissioned to call the function
            assertTrue(authorizer.hasPermission(bountyIssuer, target, selector));

            // Now lets add the Permission Bounty Submitter Role
            // The selector here is the addClaim function
            selector = bountyManager.addClaim.selector;
            // As we defined before we want to make the function have public access
            // so we use the public role as the given roleId
            vm.prank(initialAdmin);
            authorizer.addAccessPermission(
                target, selector, bountySubmitterRoleId
            );

            // Now we check that the address bountySubmitter, which we never set as
            // a member of the BOUNTY_ISSUER role, has the permission to call the function
            assertTrue(
                authorizer.hasPermission(bountySubmitter, target, selector)
            );

            //--------------------------------------------------------------------------
            // Creating Roles and Defining Role Permissions in the same Call
            //--------------------------------------------------------------------------

            // BOUNTY_VERIFIER Role
            // For the creation of the BOUNTY_VERIFIER Role we will use
            // the combined function createRoleAndAddAccessPermissions
            // Which allows us to create and assign roles and permissions
            // at the same time

            // We define the role name
            roleName = "BOUNTY_VERIFIER";
            // We define the role admin
            roleAdmin = authorizer.getAdminRole();
            // We define the initial members of the role
            roleMembers = new address[](1);
            roleMembers[0] = bountyVerifier;

            // Now we need to create two arrays
            // The first one defines the contracts for which we want to assign permissions
            address[] memory targets = new address[](1);
            // We take the address of the bountyManager here
            targets[0] = address(bountyManager);
            // The second one defines the selectors for which we want to assign permissions
            // This is a two dimensional array, where the first dimension is defines
            // the target contract for which we want to assign permissions and the second
            // dimension defines the function selectors of the target contract
            // In this case we want only the bountyManager functions, so we define the
            // array to be of length 1
            bytes4[][] memory selectors = new bytes4[][](1);
            // And we define the single bountyManager function verifyClaim(), so we
            // define the array to be of length 1 again
            selectors[0] = new bytes4[](1);
            // In case we wanted to select multiple functions, we would define the array
            // to be the size of the number of functions we want to modify permissions for
            // With that we can add the selector
            selectors[0][0] = bountyManager.verifyClaim.selector;

            vm.prank(initialAdmin);
            bytes32 bountyVerifierRoleId = authorizer
                .createRoleAndAddAccessPermissions(
                roleName, roleAdmin, roleMembers, targets, selectors
            );

            // Now we check that the role has been created
            assertTrue(authorizer.hasRole(bountyVerifierRoleId, bountyVerifier));
        }
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

        // Bounty details
        uint minimumPayoutAmount = 100e18;
        uint maximumPayoutAmount = 500e18;
        bytes memory details = "This is a test bounty";

        vm.prank(bountyIssuer);
        uint bountyId = bountyManager.addBounty(
            minimumPayoutAmount, maximumPayoutAmount, details
        );

        // check that the bounty was created
        ILM_PC_Bounties_v3.Bounty memory bounty =
            bountyManager.getBountyInformation(1);
        assertEq(bounty.minimumPayoutAmount, minimumPayoutAmount);
        assertEq(bounty.maximumPayoutAmount, maximumPayoutAmount);
        assertEq(bounty.details, details);

        //--------------------------------------------------------------------------
        // Worker submits bounty
        //--------------------------------------------------------------------------
        vm.startPrank(bountySubmitter);
        ILM_PC_Bounties_v3.Contributor memory BOB =
            ILM_PC_Bounties_v3.Contributor(bountySubmitter, 200e18);

        ILM_PC_Bounties_v3.Contributor[] memory contribs =
            new ILM_PC_Bounties_v3.Contributor[](1);
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
    }
}
