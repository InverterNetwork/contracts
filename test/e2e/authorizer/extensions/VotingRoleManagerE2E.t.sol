// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

//Internal Dependencies
import {
    E2ETest,
    IOrchestratorFactory_v1,
    IOrchestrator_v1
} from "test/e2e/E2ETest.sol";

// Modules that are used in this E2E test
import {AUT_Roles_v1} from "@aut/role/AUT_Roles_v1.sol";
import {
    LM_PC_Bounties_v1, ILM_PC_Bounties_v1
} from "@lm/LM_PC_Bounties_v1.sol";

//SuT
import {
    AUT_EXT_VotingRoles_v1,
    IAUT_EXT_VotingRoles_v1
} from "src/modules/authorizer/extensions/AUT_EXT_VotingRoles_v1.sol";

contract VotingRoleManagerE2E is E2ETest {
    // Module Configurations for the current E2E test. Should be filled during setUp() call.
    IOrchestratorFactory_v1.ModuleConfig[] moduleConfigurations;

    // E2E Test Variables
    address voter1 = makeAddr("voter1");
    address voter2 = makeAddr("voter2");
    address voter3 = makeAddr("voter3");
    address[] initialVoters = [voter1, voter2, voter3];

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
                tokenRoleAuthorizerMetadata,
                abi.encode(address(this), address(this))
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

        setUpSingleVoteGovernor();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                singleVoteGovernorMetadata, abi.encode(initialVoters, 2, 3 days)
            )
        );
    }

    function test_e2e_SingleVoteGovernor() public {
        //--------------------------------------------------------------------------------
        // Orchestrator_v1 Initialization
        //--------------------------------------------------------------------------------
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
        IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        IOrchestrator_v1 orchestrator =
            _create_E2E_Orchestrator(workflowConfig, moduleConfigurations);

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

        // Find AUT_EXT_VotingRoles_v1
        AUT_EXT_VotingRoles_v1 singleVoteGovernor;

        for (uint i; i < modulesList.length; ++i) {
            try IAUT_EXT_VotingRoles_v1(modulesList[i]).isVoter(address(0))
            returns (bool) {
                singleVoteGovernor = AUT_EXT_VotingRoles_v1(modulesList[i]);
                break;
            } catch {
                continue;
            }
        }

        // We make the governor the only owner
        bytes32 ownerRole = authorizer.getOwnerRole();
        authorizer.grantRole(ownerRole, address(singleVoteGovernor));

        // we authorize governance to create  bounties
        bountyManager.grantModuleRole(
            bountyManager.BOUNTY_ISSUER_ROLE(), address(singleVoteGovernor)
        );

        // By having address(this) renounce the Owner Role, all changes from now on need to go through the AUT_EXT_VotingRoles_v1
        authorizer.renounceRole(ownerRole, address(this));

        //--------------------------------------------------------------------------------
        // Set up Vote to create Bounty
        //--------------------------------------------------------------------------------

        // Bounty details
        uint minimumPayoutAmount = 100e18;
        uint maximumPayoutAmount = 500e18;
        bytes memory details = "This is a test bounty";

        // voter 1 sets up vote to create bounty
        vm.prank(voter1);
        uint motionId = singleVoteGovernor.createMotion(
            address(bountyManager),
            abi.encodeWithSelector(
                ILM_PC_Bounties_v1.addBounty.selector,
                minimumPayoutAmount,
                maximumPayoutAmount,
                details
            )
        );

        vm.warp(block.timestamp + 2);

        //--------------------------------------------------------------------------------
        // Vote happens
        //--------------------------------------------------------------------------------
        vm.prank(voter1);
        singleVoteGovernor.castVote(motionId, 0);
        vm.prank(voter2);
        singleVoteGovernor.castVote(motionId, 0);
        vm.prank(voter3);
        singleVoteGovernor.castVote(motionId, 0);

        vm.warp(block.timestamp + 3 days);
        //--------------------------------------------------------------------------------
        // Execute Vote
        //--------------------------------------------------------------------------------
        vm.prank(voter1);
        singleVoteGovernor.executeMotion(motionId);

        vm.warp(block.timestamp + 2);

        // check that the bounty was created
        ILM_PC_Bounties_v1.Bounty memory bounty =
            bountyManager.getBountyInformation(1);
        assertEq(bounty.minimumPayoutAmount, minimumPayoutAmount);
        assertEq(bounty.maximumPayoutAmount, maximumPayoutAmount);
        assertEq(bounty.details, details);
    }

    function _getMotionExecutionResult(
        AUT_EXT_VotingRoles_v1 singleVoteGovernor,
        uint motionId
    ) internal view returns (bool, bytes memory) {
        (
            , //address _addr
            , //bytes memory _act
            , //uint _start
            , //uint _end
            , //uint _threshold
            , //uint _for
            , //uint _against
            , //uint _abstain
            , //uint _excAt
            bool _excRes,
            bytes memory _excData
        ) = singleVoteGovernor.motions(motionId);

        return (_excRes, _excData);
    }
}
