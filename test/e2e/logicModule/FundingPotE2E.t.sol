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
    LM_PC_FundingPot_v1,
    ILM_PC_FundingPot_v1
} from "@lm/LM_PC_FundingPot_v1.sol";
import {IERC20PaymentClientBase_v2} from
    "test/mocks/modules/paymentClient/ERC20PaymentClientBaseV2Mock.sol";
import {
    FM_BC_Bancor_Redeeming_VirtualSupply_v1,
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1
} from "@fm/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {PP_Streaming_v2} from "src/modules/paymentProcessor/PP_Streaming_v2.sol";
import {
    LM_PC_Bounties_v2, ILM_PC_Bounties_v2
} from "@lm/LM_PC_Bounties_v2.sol";

import {FM_DepositVault_v1} from "@fm/depositVault/FM_DepositVault_v1.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";
import {ERC20Mock} from "test/mocks/external/token/ERC20Mock.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";

contract FundingPotE2E is E2ETest {
    // Module Configurations for the current E2E test. Should be filled during setUp() call.
    IOrchestratorFactory_v1.ModuleConfig[] moduleConfigurations;

    // Let's create a list of contributors
    address contributor1 = makeAddr("contributor 1");
    address contributor2 = makeAddr("contributor 2");
    address contributor3 = makeAddr("contributor 3");
    ERC20Issuance_v1 issuanceToken;
    LM_PC_Bounties_v2 bountyManager;
    IOrchestrator_v1 orchestrator;
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1 bondingCurveFundingManager;
    PP_Streaming_v2 paymentProcessor;
    LM_PC_FundingPot_v1 fundingPot;

    // Constants
    uint constant _SENTINEL = type(uint).max;
    //ERC20Mock contributionToken = new ERC20Mock("Contribution Mock", "C_MOCK");
    ERC20Mock contributionToken;

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

        issuanceToken = new ERC20Issuance_v1(
            "Bonding Curve Token", "BCT", 18, type(uint).max - 1
        );

        issuanceToken.setMinter(address(this), true);

        IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties memory
            bc_properties = IFM_BC_Bancor_Redeeming_VirtualSupply_v1
                .BondingCurveProperties({
                formula: address(formula),
                reserveRatioForBuying: 333_333,
                reserveRatioForSelling: 333_333,
                buyFee: 0,
                sellFee: 0,
                buyIsOpen: true,
                sellIsOpen: true,
                initialIssuanceSupply: 10,
                initialCollateralSupply: 30
            });

        // FundingManager
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                bancorVirtualSupplyBondingCurveFundingManagerMetadata,
                abi.encode(address(issuanceToken), bc_properties, token)
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
        setUpStreamingPaymentProcessor();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                streamingPaymentProcessorMetadata,
                abi.encode(10, 0, 30) // defaultStart, defaultCliff, defaultEnd
            )
        );

        // Additional Logic Modules
        setUpLM_PC_FundingPot_v1();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                LM_PC_FundingPot_v1Metadata, abi.encode(contributionToken)
            )
        );
        setUpBancorVirtualSupplyBondingCurveFundingManager();

        // BancorFormula 'formula' is instantiated in the E2EModuleRegistry
    }

    function init() private {
        //--------------------------------------------------------------------------
        // Orchestrator_v1 Initialization
        //--------------------------------------------------------------------------
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
        IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        orchestrator =
            _create_E2E_Orchestrator(workflowConfig, moduleConfigurations);

        contributionToken =
            ERC20Mock(address(orchestrator.fundingManager().token()));
        // Get the Bancor bonding curve funding manager
        bondingCurveFundingManager = IFM_BC_Bancor_Redeeming_VirtualSupply_v1(
            address(orchestrator.fundingManager())
        );

        // Get the streaming payment processor
        paymentProcessor =
            PP_Streaming_v2(address(orchestrator.paymentProcessor()));

        // Get the funding pot
        address[] memory modulesList = orchestrator.listModules();
        for (uint i; i < modulesList.length; ++i) {
            if (
                ERC165Upgradeable(modulesList[i]).supportsInterface(
                    type(ILM_PC_FundingPot_v1).interfaceId
                )
            ) {
                fundingPot = LM_PC_FundingPot_v1(modulesList[i]);
                break;
            }
        }

        // Set up the bonding curve
        issuanceToken.setMinter(address(bondingCurveFundingManager), true);
    }

    function test_e2e_FundingPotLifecycle() public {
        init();

        // 2. Grant FUNDING_POT_ADMIN_ROLE to this contract for configuring rounds
        fundingPot.grantModuleRole(
            fundingPot.FUNDING_POT_ADMIN_ROLE(), address(this)
        );

        // 3. Configure rounds
        // Round 1
        uint32 round1Id = fundingPot.createRound(
            block.timestamp + 1 days, // start
            block.timestamp + 30 days, // end
            1000e18, // cap
            address(0), // no hook
            bytes(""), // no hook function
            false, // auto closure
            ILM_PC_FundingPot_v1.AccumulationMode.Disabled // no global caps
        );

        // Round 2
        uint32 round2Id = fundingPot.createRound(
            block.timestamp + 1, // start
            block.timestamp + 60 days, // end
            750e18, // cap
            address(0), // no hook
            bytes(""), // no hook function
            true, // auto closure
            ILM_PC_FundingPot_v1.AccumulationMode.Disabled // no global caps
        );

        // 4. Set access criteria for the rounds
        // Add access criteria to round 1
        address[] memory allowedAddresses = new address[](2);
        allowedAddresses[0] = contributor1;
        allowedAddresses[1] = contributor2;

        address[] memory removedAddresses = new address[](0);

        fundingPot.setAccessCriteria(
            round1Id,
            uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.LIST),
            0,
            address(0),
            bytes32(0),
            allowedAddresses,
            removedAddresses
        );

        // Add access criteria to round 2
        allowedAddresses = new address[](1);
        allowedAddresses[0] = contributor3;

        fundingPot.setAccessCriteria(
            round2Id,
            uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.LIST),
            0,
            address(0),
            bytes32(0),
            allowedAddresses,
            removedAddresses
        );

        // 5. Set access criteria privileges for the rounds
        fundingPot.setAccessCriteriaPrivileges(
            round1Id,
            1, // accessCriteriaId
            500e18, // personalCap
            true, // overrideContributionSpan
            block.timestamp, // start
            0, // cliff
            block.timestamp + 60 days // end
        );

        fundingPot.setAccessCriteriaPrivileges(
            round2Id,
            1, // accessCriteriaId
            750e18, // personalCap
            true, // overrideContributionSpan
            block.timestamp, // start
            0, // cliff
            block.timestamp + 60 days // end
        );

        vm.warp(block.timestamp + 1 days);

        // 6. Fund contributors and contribute to rounds
        contributionToken.mint(contributor1, 1000e18);
        contributionToken.mint(contributor2, 1000e18);
        contributionToken.mint(contributor3, 1000e18);

        uint contributor1Amount = 400e18;
        uint contributor2Amount = 500e18;
        uint contributor3Amount = 750e18;
        uint totalContributionForRound1 =
            contributor1Amount + contributor2Amount;

        vm.startPrank(contributor1);
        contributionToken.approve(address(fundingPot), contributor1Amount);
        fundingPot.contributeToRoundFor(
            contributor1, round1Id, contributor1Amount, 1, new bytes32[](0)
        );
        vm.stopPrank();

        vm.startPrank(contributor2);
        contributionToken.approve(address(fundingPot), contributor2Amount);
        fundingPot.contributeToRoundFor(
            contributor2, round1Id, contributor2Amount, 1, new bytes32[](0)
        );
        vm.stopPrank();

        vm.startPrank(contributor3);
        contributionToken.approve(address(fundingPot), contributor3Amount);
        fundingPot.contributeToRoundFor(
            contributor3, round2Id, contributor3Amount, 1, new bytes32[](0)
        );
        vm.stopPrank();

        // 7. Fast forward to after rounds end
        vm.warp(block.timestamp + 50 days);

        // 8. Close rounds
        fundingPot.closeRound(round1Id);
        assertEq(fundingPot.isRoundClosed(round1Id), true);
        assertEq(fundingPot.isRoundClosed(round2Id), true); // round2 is auto closed
        assertEq(contributionToken.balanceOf(address(fundingPot)), 0);
        assertGt(issuanceToken.balanceOf(address(fundingPot)), 0);

        // 9. Create payment orders for contributors
        fundingPot.createPaymentOrdersForContributorsBatch(round1Id, 2);
        fundingPot.createPaymentOrdersForContributorsBatch(round2Id, 1);

        // 10. Process payments
        vm.prank(address(fundingPot));
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v2(address(fundingPot))
        );

        // 11. Claim payments
        vm.prank(contributor1);
        paymentProcessor.claimAll(address(fundingPot));

        vm.prank(contributor2);
        paymentProcessor.claimAll(address(fundingPot));

        vm.prank(contributor3);
        paymentProcessor.claimAll(address(fundingPot));

        // 12. Verify proportional distribution for round 1
        uint contributor1Issuance = issuanceToken.balanceOf(contributor1);
        uint contributor2Issuance = issuanceToken.balanceOf(contributor2);
        uint totalIssuanceForRound1 =
            contributor1Issuance + contributor2Issuance;

        // Calculate the expected proportions (scaled by 1e18 for precision)
        uint contributor1ExpectedProportion =
            (contributor1Amount * 1e18) / totalContributionForRound1;
        uint contributor1ActualProportion =
            (contributor1Issuance * 1e18) / totalIssuanceForRound1;

        uint contributor2ExpectedProportion =
            (contributor2Amount * 1e18) / totalContributionForRound1;
        uint contributor2ActualProportion =
            (contributor2Issuance * 1e18) / totalIssuanceForRound1;

        // Using 0.001e18 (0.1%) as the maximum relative error
        assertApproxEqRel(
            contributor1ActualProportion,
            contributor1ExpectedProportion,
            0.001e18
        );

        assertApproxEqRel(
            contributor2ActualProportion,
            contributor2ExpectedProportion,
            0.001e18
        );

        // verify round 2 contributor
        assertGt(issuanceToken.balanceOf(contributor3), 0);
    }
}
