// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {E2eTest} from "test/e2e/E2eTest.sol";
import "forge-std/console.sol";

//Internal Dependencies
import {ModuleTest, IModule, IOrchestrator} from "test/modules/ModuleTest.sol";
import {IOrchestratorFactory} from "src/factories/OrchestratorFactory.sol";
import {AuthorizerMock} from "test/utils/mocks/modules/AuthorizerMock.sol";

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

contract BountyManagerLifecycle is E2eTest {
    address bountyAdmin = makeAddr("bountyAdmin");
    address claimAdmin = makeAddr("claimAdmin");
    address verifyAdmin = makeAddr("verifyAdmin");

    // Let's create a list of contributors
    address contributor1 = makeAddr("contributor 1");
    address contributor2 = makeAddr("contributor 2");
    address contributor3 = makeAddr("contributor 3");

    // Constants
    uint constant _SENTINEL = type(uint).max;

    ERC20Mock token = new ERC20Mock("Mock", "MOCK");

    function test_e2e_BountyManagerLifecycle() public {
        // -----------INIT
        // address(this) creates a new orchestrator.
        IOrchestratorFactory.OrchestratorConfig memory orchestratorConfig =
        IOrchestratorFactory.OrchestratorConfig({
            owner: address(this),
            token: token
        });

        IOrchestrator orchestrator =
        _createNewOrchestratorWithAllModules_withRoleBasedAuthorizerAndBountyManager(
            orchestratorConfig
        );

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
            uint8(IBountyManager.Roles.BountyAdmin), address(this)
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
        bountyManager.verifyClaim(claimId, bountyId, contribs);

        // Bounty has been paid out
        assertEq(token.balanceOf(contrib1.addr), 150e18);
        assertEq(token.balanceOf(contrib2.addr), 150e18);
    }
}
