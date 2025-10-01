// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console2.sol";

// Internal Dependencies
import {
    E2ETest,
    IOrchestratorFactory_v1,
    IOrchestrator_v1
} from "test/e2e/E2ETest.sol";

import {Orchestrator_v1} from "src/orchestrator/Orchestrator_v1.sol";

import {IModule_v1} from "src/modules/base/IModule_v1.sol";

import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";

import {
    DiscreteCurveMathLibV1_Exposed
} from "@mocks/modules/fundingManager/bondingCurve/DiscreteCurveMathLibV1_Exposed.sol";
import {
    PackedSegment
} from "src/modules/fundingManager/bondingCurve/types/PackedSegment_v1.sol";
import {
    DiscreteCurveMathLib_v1,
    PackedSegmentLib
} from "src/modules/fundingManager/bondingCurve/formulas/DiscreteCurveMathLib_v1.sol";

// External Dependencies
import {
    ERC165Upgradeable
} from "@oz-up/utils/introspection/ERC165Upgradeable.sol";

// SuT
import {
    FM_BC_Discrete_Redeeming_VirtualSupply_v1,
    IFM_BC_Discrete_Redeeming_VirtualSupply_v1
} from "@fm/bondingCurve/FM_BC_Discrete_Redeeming_VirtualSupply_v1.sol";
import {
    LM_PC_Lending_Facility_v1,
    ILM_PC_Lending_Facility_v1
} from "src/modules/logicModule/LM_PC_Lending_Facility_v1.sol";
import {
    LM_PC_Lending_Facility_v1_Exposed
} from "test/mocks/modules/logicModule/LM_PC_HouseProtocol_v1_Exposed.sol";
import {DynamicFeeCalculator_v1} from "@ex/fees/DynamicFeeCalculator_v1.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {Clones} from "@oz/proxy/Clones.sol";
import {
    IDynamicFeeCalculator_v1
} from "@ex/fees/interfaces/IDynamicFeeCalculator_v1.sol";

contract LM_PC_Lending_Facility_v1_E2E is E2ETest {
    using PackedSegmentLib for PackedSegment;

    // Module Configurations for the current E2E test. Should be filled during setUp() call.
    IOrchestratorFactory_v1.ModuleConfig[] moduleConfigurations;

    ERC20Issuance_v1 issuanceToken;
    DynamicFeeCalculator_v1 dynamicFeeCalculator;
    DiscreteCurveMathLibV1_Exposed internal exposedLib;

    address lendingFacilityManager = makeAddr("lendingFacilityManager");
    address borrower1 = address(0xA11CE);
    address borrower2 = address(0x606);
    address borrower3 = address(0xBEEF);

    // Constants
    uint constant BORROWABLE_QUOTA = 10_000;
    uint constant MAX_LEVERAGE = 5;

    // Based on flatSlopedTestCurve initialized in setUp():
    PackedSegment[] internal flatSlopedTestCurve;

    function setUp() public override {
        // Setup common E2E framework
        super.setUp();

        exposedLib = new DiscreteCurveMathLibV1_Exposed();

        // Set Up individual Modules the E2E test is going to use and store their configurations:
        // NOTE: It's important to store the module configurations in order, since _create_E2E_Orchestrator() will copy from the array.
        // The order should be:
        //      moduleConfigurations[0]  => FundingManager
        //      moduleConfigurations[1]  => Authorizer
        //      moduleConfigurations[2]  => PaymentProcessor
        //      moduleConfigurations[3:] => Additional Logic Modules

        // FundingManager - FM_BC_Discrete_Redeeming_VirtualSupply_v1
        setUpFM_BC_Discrete_Redeeming_VirtualSupply_v1();

        // Floor Values
        uint floorPrice = 1 ether; //1 Dollar
        uint floorSupply = 1_000_000 ether; // 1 Million Floor Tokens

        // Curve Values
        uint initialPrice = 1.4 ether; //1.4 Dollar
        uint priceIncrease = 0.4 ether; //0.4 Dollar
        uint supplyPerStep = 40_000 ether; //40.000 Floor Tokens
        uint numberOfSteps = type(uint16).max; //65535 Steps (max value)

        // --- Initialize flatSlopedTestCurve ---
        flatSlopedTestCurve = new PackedSegment[](2);

        // Floor Segment
        flatSlopedTestCurve[0] = exposedLib.exposed_createSegment(
            floorPrice, //initialPriceOfSegment
            0, //priceIncreasePerStep (We have only one step)
            floorSupply, //supplyPerStep
            1 //numberOfSteps (1 equals one vertical element)
        );

        // Discrete Curve Segment
        flatSlopedTestCurve[1] = exposedLib.exposed_createSegment(
            initialPrice, //initialPriceOfSegment
            priceIncrease, //priceIncreasePerStep
            supplyPerStep, //supplyPerStep
            numberOfSteps //numberOfSteps
        );

        issuanceToken =
            new ERC20Issuance_v1("Floor Token", "FT", 18, type(uint).max - 1);
        issuanceToken.setMinter(address(this), true);

        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                FM_BC_Discrete_Redeeming_VirtualSupply_v1_Metadata,
                abi.encode(address(issuanceToken), token, flatSlopedTestCurve)
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

        // Additional Logic Modules - Lending Facility will be added after orchestrator creation
        setUpLM_PC_Lending_Facility_v1();

        // Deploy Dynamic Fee Calculator using proxy pattern
        address dynamicFeeCalculatorImpl =
            address(new DynamicFeeCalculator_v1());
        dynamicFeeCalculator =
            DynamicFeeCalculator_v1(Clones.clone(dynamicFeeCalculatorImpl));
        dynamicFeeCalculator.init(address(this));

        // Set up dynamic fee parameters
        IDynamicFeeCalculator_v1.DynamicFeeParameters memory feeParams =
            IDynamicFeeCalculator_v1.DynamicFeeParameters({
                Z_issueRedeem: 0.01 ether,
                m_issueRedeem: 0.01 ether,
                A_issueRedeem: 0.01 ether,
                Z_origination: 0.01 ether,
                A_origination: 0.01 ether,
                m_origination: 0.01 ether
            });
        dynamicFeeCalculator.setDynamicFeeCalculatorParams(feeParams);
    }

    function test_e2e_LendingFacilityLifecycle() public {
        //--------------------------------------------------------------------------------
        // Setup

        // Warp time to account for time calculations
        vm.warp(52 weeks);

        // address(this) creates a new orchestrator.
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
            IOrchestratorFactory_v1.WorkflowConfig({
                independentUpdates: false, independentUpdateAdmin: address(0)
            });

        IOrchestrator_v1 orchestrator =
            _create_E2E_Orchestrator(workflowConfig, moduleConfigurations);

        // Get the funding manager (bonding curve)
        FM_BC_Discrete_Redeeming_VirtualSupply_v1 fundingManager =
            FM_BC_Discrete_Redeeming_VirtualSupply_v1(
                address(orchestrator.fundingManager())
            );

        // Set up issuance token minting for the funding manager
        issuanceToken.setMinter(address(fundingManager), true);

        // Now create and add the lending facility module with the correct funding manager address
        address lendingFacilityAddress = moduleFactory.createAndInitModule(
            lendingFacilityMetadata,
            orchestrator,
            abi.encode(
                address(token), // collateralToken
                address(issuanceToken), // issuanceToken
                address(fundingManager), // dbcFmAddress
                address(dynamicFeeCalculator), // dynamicFeeCalculator
                BORROWABLE_QUOTA, // borrowableQuota
                MAX_LEVERAGE // maxLeverage
            ),
            workflowConfig
        );

        // Add the lending facility module to the orchestrator
        uint timelock =
            Orchestrator_v1(address(orchestrator)).MODULE_UPDATE_TIMELOCK();
        orchestrator.initiateAddModuleWithTimelock(lendingFacilityAddress);
        vm.warp(block.timestamp + timelock);
        orchestrator.executeAddModule(lendingFacilityAddress);

        // Get the lending facility logic module
        LM_PC_Lending_Facility_v1_Exposed lendingFacility =
            LM_PC_Lending_Facility_v1_Exposed(lendingFacilityAddress);

        // Grant lending facility manager role
        lendingFacility.grantModuleRole(
            lendingFacility.LENDING_FACILITY_MANAGER_ROLE(),
            lendingFacilityManager
        );

        //--------------------------------------------------------------------------------
        // Test 1: Setup and Configuration

        console2.log("=== Test 1: Setup and Configuration ===");

        // Verify initial configuration
        assertEq(lendingFacility.borrowableQuota(), BORROWABLE_QUOTA);
        assertEq(lendingFacility.maxLeverage(), MAX_LEVERAGE);
        assertEq(lendingFacility.currentlyBorrowedAmount(), 0);
        assertEq(lendingFacility.nextLoanId(), 1);

        //--------------------------------------------------------------------------------
        // Test 2: Buy Tokens from Bonding Curve

        console2.log("=== Test 2: Buy Tokens from Bonding Curve ===");

        uint buyAmount = 1000 ether; // 1000 USDC

        // Mint tokens to participants
        token.mint(borrower1, buyAmount);

        fundingManager.openBuy();
        fundingManager.openSell();

        vm.startPrank(borrower1);
        {
            // Approve tokens for funding manager
            token.approve(address(fundingManager), buyAmount);

            uint issuanceTokensBefore = issuanceToken.balanceOf(borrower1);
            // Buy tokens from bonding curve
            fundingManager.buy(buyAmount, 1);

            uint issuanceTokensAfter = issuanceToken.balanceOf(borrower1);

            assertGt(issuanceTokensAfter, issuanceTokensBefore);
            assertGt(issuanceTokensAfter - issuanceTokensBefore, 0);
        }
        vm.stopPrank();

        //--------------------------------------------------------------------------------
        // Test 3: Borrow Against Issuance Tokens

        console2.log("=== Test 3: Borrowing ===");

        uint borrowAmount = 500 ether; // 500 USDC

        vm.startPrank(borrower1);
        {
            // Approve issuance tokens for the lending facility
            issuanceToken.approve(address(lendingFacility), type(uint).max);
            uint fundingManagerBalanceBefore =
                token.balanceOf(address(fundingManager));
            uint borrowFee =
                lendingFacility.exposed_calculateDynamicBorrowingFee(
                    borrowAmount
                );
            // Borrow collateral tokens
            uint loanId = lendingFacility.borrow(borrowAmount);
            // Verify loan details
            ILM_PC_Lending_Facility_v1.Loan memory loan =
                lendingFacility.getLoan(loanId);
            assertEq(loan.id, loanId);
            assertEq(loan.borrower, borrower1);
            assertEq(loan.principalAmount, borrowAmount);
            assertGt(loan.lockedIssuanceTokens, 0);
            assertTrue(loan.isActive);

            // Verify borrower received collateral tokens
            assertEq(token.balanceOf(borrower1), borrowAmount - borrowFee);
            // Verify locked issuance tokens
            assertGt(lendingFacility.getLockedIssuanceTokens(borrower1), 0);
            assertEq(
                lendingFacility.getOutstandingLoan(borrower1), borrowAmount
            );
            //Verify funding manager balance
            //balance of funding manager should be the balance before minus the borrow amount plus the borrow fee
            assertEq(
                token.balanceOf(address(fundingManager)),
                fundingManagerBalanceBefore - borrowAmount + borrowFee
            );
        }
        vm.stopPrank();

        //--------------------------------------------------------------------------------
        // Test 4: Repayment

        console2.log("=== Test 4: Repayment ===");

        vm.startPrank(borrower1);
        {
            // Get loan details before repayment
            uint[] memory loanIds = lendingFacility.getUserLoanIds(borrower1);
            uint loanId = loanIds[0];

            // Calculate repayment amount
            uint repaymentAmount =
                lendingFacility.calculateLoanRepaymentAmount(loanId);
            uint issuanceTokenLocked =
                lendingFacility.getLockedIssuanceTokens(borrower1);
            uint issuanceTokenBalanceBefore = issuanceToken.balanceOf(borrower1);
            // Approve and repay
            uint currentCollateralBalance = token.balanceOf(borrower1);
            token.mint(borrower1, repaymentAmount - currentCollateralBalance);
            token.approve(address(lendingFacility), repaymentAmount);
            lendingFacility.repay(loanId, repaymentAmount);

            // Verify loan is closed
            ILM_PC_Lending_Facility_v1.Loan memory loanAfter =
                lendingFacility.getLoan(loanId);
            assertFalse(loanAfter.isActive);

            // Verify issuance tokens are unlocked
            assertEq(lendingFacility.getLockedIssuanceTokens(borrower1), 0);
            assertEq(lendingFacility.getOutstandingLoan(borrower1), 0);

            // Verify issuance tokens were returned to the borrower
            uint issuanceTokenBalanceAfter = issuanceToken.balanceOf(borrower1);
            uint issuanceTokenUnlocked =
                issuanceTokenBalanceAfter - issuanceTokenBalanceBefore;
            assertEq(issuanceTokenUnlocked, issuanceTokenLocked);
        }
        vm.stopPrank();

        //--------------------------------------------------------------------------------
        // Test 5: Buy and Borrow -- borrow

        console2.log("=== Test 5: Buy and Borrow ===");

        vm.startPrank(borrower2);
        {
            uint userBalanceBefore = token.balanceOf(borrower2);
            uint fundingManagerBalanceBefore =
                token.balanceOf(address(fundingManager));

            // Mint tokens to borrower2
            token.mint(borrower2, 50 ether);

            // Approve tokens for lending facility
            token.approve(address(lendingFacility), type(uint).max);

            // Buy and borrow
            lendingFacility.buyAndBorrow(50 ether, 5);

            // Calculate actual fees
            uint userBalanceAfter = token.balanceOf(borrower2);
            uint fundingManagerBalanceAfter =
                token.balanceOf(address(fundingManager));

            uint totalOutstandingLoan =
                lendingFacility.getOutstandingLoan(borrower2);

            // Calculate fees
            uint collateralDeposited = 50 ether;
            uint collateralReceived = userBalanceAfter - userBalanceBefore;
            // Total Fees Paid = buyFee + borrowFee
            uint totalFeesPaid = collateralDeposited - collateralReceived;
            uint fundingManagerBalanceChange =
                fundingManagerBalanceAfter - fundingManagerBalanceBefore;
            assertEq(totalFeesPaid, fundingManagerBalanceChange);
        }
        vm.stopPrank();

        // Test 5: Buy and Borrow -- repay
        vm.startPrank(borrower2);
        {
            uint[] memory loanIds = lendingFacility.getUserLoanIds(borrower2);
            uint loanId = loanIds[0];
            uint totalOutstandingLoan =
                lendingFacility.getOutstandingLoan(borrower2);
            token.mint(borrower2, totalOutstandingLoan);
            token.approve(address(lendingFacility), totalOutstandingLoan);
            // Repay
            lendingFacility.repay(loanId, totalOutstandingLoan);
            assertEq(lendingFacility.getOutstandingLoan(borrower2), 0);
            assertEq(lendingFacility.getLockedIssuanceTokens(borrower2), 0);
        }
        vm.stopPrank();

        console2.log("=== All tests completed successfully ===");
    }
}

