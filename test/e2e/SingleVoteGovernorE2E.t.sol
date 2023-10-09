// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {E2eTest} from "test/e2e/E2eTest.sol";
import "forge-std/console.sol";

//Internal Dependencies
import {ModuleTest, IModule, IOrchestrator} from "test/modules/ModuleTest.sol";
import {IOrchestratorFactory} from "src/factories/OrchestratorFactory.sol";
import {RoleAuthorizer} from "src/modules/authorizer/RoleAuthorizer.sol";

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

import {
    SingleVoteGovernor,
    ISingleVoteGovernor
} from "src/modules/utils/SingleVoteGovernor.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract SingleVoteGovernorE2E is E2eTest {
    // voters
    address voter1 = makeAddr("voter1");
    address voter2 = makeAddr("voter2");
    address voter3 = makeAddr("voter3");

    // Constants
    ERC20Mock token = new ERC20Mock("Mock", "MOCK");

    function test_e2e_SingleVoteGovernorE2E() public {
        // -----------INIT
        // address(this) creates a new orchestrator.
        IOrchestratorFactory.OrchestratorConfig memory orchestratorConfig =
        IOrchestratorFactory.OrchestratorConfig({
            owner: address(this),
            token: token
        });

        IOrchestrator orchestrator =
        _createNewOrchestratorWithAllModules_withBountyManagerAndSingleVoteGovernor(
            orchestratorConfig
        );

        RebasingFundingManager fundingManager =
            RebasingFundingManager(address(orchestrator.fundingManager()));

        RoleAuthorizer authorizer =
            RoleAuthorizer(address(orchestrator.authorizer()));

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

        // Find SingleVoteGovernor
        SingleVoteGovernor singleVoteGovernor;

        for (uint i; i < modulesList.length; ++i) {
            try ISingleVoteGovernor(modulesList[i]).isVoter(address(0))
            returns (bool) {
                singleVoteGovernor = SingleVoteGovernor(modulesList[i]);
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

        // By having address(this) renounce the Owner Role, all changes from now on need to go through the SingleVoteGovernor
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
                IBountyManager.addBounty.selector,
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

        // to avoid stack too deep
        (bool _excRes, bytes memory _excData) =
            _getMotionExecutionResult(singleVoteGovernor, motionId);

        console.log(_excRes);
        console.log(string(_excData));

        vm.warp(block.timestamp + 2);

        // check that the bounty was created
        IBountyManager.Bounty memory bounty =
            bountyManager.getBountyInformation(1);
        assertEq(bounty.minimumPayoutAmount, minimumPayoutAmount);
        assertEq(bounty.maximumPayoutAmount, maximumPayoutAmount);
        assertEq(bounty.details, details);
    }

    function _getMotionExecutionResult(
        SingleVoteGovernor singleVoteGovernor,
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

    function _createNewOrchestratorWithAllModules_withBountyManagerAndSingleVoteGovernor(
        IOrchestratorFactory.OrchestratorConfig memory config
    ) internal returns (IOrchestrator) {
        IOrchestratorFactory.ModuleConfig[] memory optionalModules =
            new IOrchestratorFactory.ModuleConfig[](2);
        optionalModules[0] = singleVoteGovernorFactoryConfig;
        optionalModules[1] = bountyManagerFactoryConfig;

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
            roleAuthorizerFactoryConfig,
            paymentProcessorFactoryConfig,
            optionalModules
        );
    }
}
