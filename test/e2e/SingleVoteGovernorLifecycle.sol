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

import {SingleVoteGovernor, ISingleVoteGovernor} from "src/modules/utils/SingleVoteGovernor.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract SingleVoteGovernorLifecycle is E2eTest {

    // voters
    address voter1 = makeAddr("voter1");
    address voter2 = makeAddr("voter2");
    address voter3 = makeAddr("voter3");

    // Constants
    ERC20Mock token = new ERC20Mock("Mock", "MOCK");

    function test_e2e_SingleVoteGovernorLifecycle() public {

        // Setup new orchestrator
        // add voters
        // create vote to create bounty
        // pass that vote
        // execute it
        // check that the bounty was created


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

        RoleAuthorizer authorizer = RoleAuthorizer(
            address(orchestrator.authorizer())
        );



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
            try ISingleVoteGovernor(modulesList[i]).isVoter(address(0)) returns (
                bool
            ) {
                singleVoteGovernor = SingleVoteGovernor(modulesList[i]);
                break;
            } catch {
                continue;
            }
        }


        // We make the governor the only owner
        bytes32 ownerRole = authorizer.getOwnerRole();
        authorizer.grantRole(ownerRole, address(singleVoteGovernor));

        authorizer.renounceRole(ownerRole, address(this));


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




        // Bounty details
        uint minimumPayoutAmount = 100e18;
        uint maximumPayoutAmount = 500e18;
        bytes memory details = "This is a test bounty";


        // voter 1 sets up vote to create bounty
        vm.prank(voter1);
        uint motionId= singleVoteGovernor.createMotion(address(bountyManager), abi.encodeWithSignature(
            "addBounty(uint,uint,bytes memory)",
            minimumPayoutAmount,
            maximumPayoutAmount,
            details
        ));

        vm.warp(block.timestamp + 2);

        // voters vote
         vm.prank(voter1);
        singleVoteGovernor.castVote(motionId, 0);
        vm.prank(voter2);
        singleVoteGovernor.castVote(motionId, 0);
        vm.prank(voter3);
        singleVoteGovernor.castVote(motionId, 0);

        
        vm.warp(block.timestamp + 3 days);

        // execute vote
        singleVoteGovernor.executeMotion(motionId);

        vm.warp(block.timestamp + 2);

        console.log(bountyManager.listBountyIds()[0]);

        // check that the bounty was created
        IBountyManager.Bounty memory bounty = bountyManager.getBountyInformation(2);
        assertEq(bounty.minimumPayoutAmount, minimumPayoutAmount);
        assertEq(bounty.maximumPayoutAmount, maximumPayoutAmount);
        assertEq(bounty.details, details);


/*

        // Workers submit bounty
        IBountyManager.Contributor memory contrib1 =
            IBountyManager.Contributor(address(0xA11CE), 150e18);
        IBountyManager.Contributor memory contrib2 =
            IBountyManager.Contributor(address(0xb0b), 150e18);

        //auth.setIsAuthorized(address(0xA11CE), true);
        bountyManager.grantModuleRole(
            uint8(IBountyManager.Roles.ClaimAdmin), address(0xA11CE)
        );

        IBountyManager.Contributor[] memory contribs =
            new IBountyManager.Contributor[](2);
        contribs[0] = contrib1;
        contribs[1] = contrib2;

        bytes memory claimDetails = "This is a test submission";

        vm.prank(contrib1.addr);
        uint claimId = bountyManager.addClaim(1, contribs, claimDetails);

        // Verifiers approve bounty

        address verifier1 = makeAddr("verifier 1");

        //auth.setIsAuthorized(verifier1, true);
        bountyManager.grantModuleRole(
            uint8(IBountyManager.Roles.VerifyAdmin), verifier1
        );

        vm.prank(verifier1);
        bountyManager.verifyClaim(claimId, bountyId);

        // Bounty has been paid out
        assertEq(token.balanceOf(contrib1.addr), 150e18);
        assertEq(token.balanceOf(contrib2.addr), 150e18);*/
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
