// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {DynamicFeeCalculator_v1} from
    "src/modules/logicModule/libraries/DynamicFeeCalculator_v1.sol";
import {IDynamicFeeCalculator_v1} from
    "src/modules/logicModule/libraries/IDynamicFeeCalculator_v1.sol";
import {OZErrors} from "@testUtilities/OZErrors.sol";

contract DynamicFeeCalculator_v1_Test is Test {
    // System Under Test
    DynamicFeeCalculator_v1 feeCalculator;

    // =========================================================================
    // Constants

    uint internal constant MAX_FEE_PERCENTAGE = 1e18;

    // =========================================================================
    // Test parameters
    IDynamicFeeCalculator_v1.DynamicFeeParameters params;

    function setUp() public {
        // Deploy the fee calculator
        feeCalculator = new DynamicFeeCalculator_v1();

        params = helper_setDynamicFeeCalculatorParams(params);
    }

    // =========================================================================
    // Test: Dynamic Fee Calculator

    /* Test external setDynamicFeeCalculatorParams function
        ├── Given caller has FEE_CALCULATOR_ADMIN_ROLE
        │   └── When setting new fee calculator parameters
        │       ├── Then the parameters should be updated
        │       └── Then an event should be emitted
        └── Given invalid parameters (zero values/max values)
            └── When trying to set parameters
                └── Then it should revert with InvalidDynamicFeeParameters error
        └── Given caller doesn't have role
            └── When trying to set parameters
    */

    // function testFuzzPublicSetDynamicFeeCalculatorParams_failsGivenUnauthorizedCaller(
    //     address unauthorizedUser,
    //     IDynamicFeeCalculator_v1.DynamicFeeParameters memory feeParams
    // ) public {
    //     vm.assume(
    //         unauthorizedUser != address(0) && unauthorizedUser != address(this)
    //     );

    //     IDynamicFeeCalculator_v1.DynamicFeeParameters memory feeParams =
    //         helper_setDynamicFeeCalculatorParams(feeParams);

    //     vm.startPrank(unauthorizedUser);

    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             IModule_v1.Module__CallerNotAuthorized.selector,
    //             lendingFacility.FEE_CALCULATOR_ADMIN_ROLE(),
    //             unauthorizedUser
    //         )
    //     );
    //     lendingFacility.setDynamicFeeCalculatorParams(feeParams);
    //     vm.stopPrank();
    // }

    function testPublicSetDynamicFeeCalculatorParams_failsGivenInvalidParamsZero(
        IDynamicFeeCalculator_v1.DynamicFeeParameters memory feeParams
    ) public {
        vm.assume(
            feeParams.Z_issueRedeem == 0 || feeParams.A_issueRedeem == 0
                || feeParams.m_issueRedeem == 0 || feeParams.Z_origination == 0
                || feeParams.A_origination == 0 || feeParams.m_origination == 0
        );
        vm.expectRevert(
            IDynamicFeeCalculator_v1
                .Module__IDynamicFeeCalculator_v1_InvalidDynamicFeeParameters
                .selector
        );
        feeCalculator.setDynamicFeeCalculatorParams(feeParams);
    }

    function testPublicSetDynamicFeeCalculatorParams_failsGivenInvalidParamsMax(
        IDynamicFeeCalculator_v1.DynamicFeeParameters memory feeParams
    ) public {
        vm.assume(
            feeParams.Z_issueRedeem > MAX_FEE_PERCENTAGE
                || feeParams.A_issueRedeem > MAX_FEE_PERCENTAGE
                || feeParams.m_issueRedeem > MAX_FEE_PERCENTAGE
                || feeParams.Z_origination > MAX_FEE_PERCENTAGE
                || feeParams.A_origination > MAX_FEE_PERCENTAGE
                || feeParams.m_origination > MAX_FEE_PERCENTAGE
        );
        vm.expectRevert(
            IDynamicFeeCalculator_v1
                .Module__IDynamicFeeCalculator_v1_InvalidDynamicFeeParameters
                .selector
        );
        feeCalculator.setDynamicFeeCalculatorParams(feeParams);
    }

    function testPublicSetDynamicFeeCalculatorParams_succeedsGivenValidParams(
        IDynamicFeeCalculator_v1.DynamicFeeParameters memory feeParams
    ) public {
        vm.assume(
            feeParams.Z_issueRedeem != 0 && feeParams.A_issueRedeem != 0
                && feeParams.m_issueRedeem != 0 && feeParams.Z_origination != 0
                && feeParams.A_origination != 0 && feeParams.m_origination != 0
                && feeParams.Z_issueRedeem <= MAX_FEE_PERCENTAGE
                && feeParams.A_issueRedeem <= MAX_FEE_PERCENTAGE
                && feeParams.m_issueRedeem <= MAX_FEE_PERCENTAGE
                && feeParams.Z_origination <= MAX_FEE_PERCENTAGE
                && feeParams.A_origination <= MAX_FEE_PERCENTAGE
                && feeParams.m_origination <= MAX_FEE_PERCENTAGE
        );

        feeCalculator.setDynamicFeeCalculatorParams(feeParams);

        IDynamicFeeCalculator_v1.DynamicFeeParameters memory LF_feeParams =
            feeCalculator.getDynamicFeeParameters();

        assertEq(LF_feeParams.Z_issueRedeem, feeParams.Z_issueRedeem);
        assertEq(LF_feeParams.A_issueRedeem, feeParams.A_issueRedeem);
        assertEq(LF_feeParams.m_issueRedeem, feeParams.m_issueRedeem);
        assertEq(LF_feeParams.Z_origination, feeParams.Z_origination);
        assertEq(LF_feeParams.A_origination, feeParams.A_origination);
        assertEq(LF_feeParams.m_origination, feeParams.m_origination);
    }

    // Test: Dynamic Fee Calculator Library

    /* Test calculateOriginationFee function
        ├── Given utilizationRatio is below A_origination
        │   └── Then the fee should be Z_origination
        └── Given utilizationRatio is above A_origination
            └── Then the fee should be Z_origination + (utilizationRatio - A_origination) * m_origination / SCALING_FACTOR
    */
    function testFuzz_calculateOriginationFee_BelowThreshold(
        IDynamicFeeCalculator_v1.DynamicFeeParameters memory feeParams_,
        uint utilizationRatio_
    ) public {
        IDynamicFeeCalculator_v1.DynamicFeeParameters memory feeParams =
            helper_setDynamicFeeCalculatorParams(feeParams_);

        // Given: utilizationRatio is below A_origination
        vm.assume(
            utilizationRatio_ > 1 && utilizationRatio_ < type(uint64).max
                && utilizationRatio_ < feeParams.A_origination
        );

        uint fee = feeCalculator.calculateOriginationFee(utilizationRatio_);
        assertEq(fee, feeParams.Z_origination);
    }

    function testFuzz_calculateOriginationFee_AboveThreshold(
        IDynamicFeeCalculator_v1.DynamicFeeParameters memory feeParams_,
        uint utilizationRatio_
    ) public {
        IDynamicFeeCalculator_v1.DynamicFeeParameters memory feeParams =
            helper_setDynamicFeeCalculatorParams(feeParams_);

        // Given: utilizationRatio is above A_origination
        vm.assume(
            utilizationRatio_ > 1 && utilizationRatio_ < type(uint64).max
                && utilizationRatio_ > feeParams.A_origination
        );

        uint fee = feeCalculator.calculateOriginationFee(utilizationRatio_);

        assertEq(
            fee,
            feeParams.Z_origination
                + (
                    (utilizationRatio_ - feeParams.A_origination)
                        * feeParams.m_origination
                ) / 1e18
        );
    }

    /* Test calculateIssuanceFee function
        ├── Given premiumRate is below A_issueRedeem
        │   └── Then the fee should be Z_issueRedeem
        └── Given premiumRate is above A_issueRedeem
            └── Then the fee should be Z_issueRedeem + (premiumRate - A_issueRedeem) * m_issueRedeem / SCALING_FACTOR
    */
    function testFuzz_calculateIssuanceFee_BelowThreshold(
        IDynamicFeeCalculator_v1.DynamicFeeParameters memory feeParams_,
        uint premiumRate_
    ) public {
        IDynamicFeeCalculator_v1.DynamicFeeParameters memory feeParams =
            helper_setDynamicFeeCalculatorParams(feeParams_);

        // Given: premiumRate is below A_issueRedeem
        vm.assume(
            premiumRate_ > 1 && premiumRate_ < type(uint64).max
                && premiumRate_ < feeParams.A_issueRedeem
        );

        uint fee = feeCalculator.calculateIssuanceFee(premiumRate_);
        assertEq(fee, feeParams.Z_issueRedeem);
    }

    function testFuzz_calculateIssuanceFee_AboveThreshold(
        IDynamicFeeCalculator_v1.DynamicFeeParameters memory feeParams_,
        uint premiumRate_
    ) public {
        IDynamicFeeCalculator_v1.DynamicFeeParameters memory feeParams =
            helper_setDynamicFeeCalculatorParams(feeParams_);

        // Given: premiumRate is above A_issueRedeem
        vm.assume(
            premiumRate_ > 1 && premiumRate_ < type(uint64).max
                && premiumRate_ > feeParams.A_issueRedeem
        );

        uint fee = feeCalculator.calculateIssuanceFee(premiumRate_);
        assertEq(
            fee,
            feeParams.Z_issueRedeem
                + (premiumRate_ - feeParams.A_issueRedeem) * feeParams.m_issueRedeem
                    / 1e18
        );
    }

    /* Test calculateRedemptionFee function
        ├── Given premiumRate is below A_issueRedeem
        │   └── Then the fee should be Z_issueRedeem
        └── Given premiumRate is above A_issueRedeem
            └── Then the fee should be feeParams.Z_issueRedeem
                + (feeParams.A_issueRedeem - premiumRate) * feeParams.m_issueRedeem
                    / SCALING_FACTOR
    */
    function testFuzz_calculateRedemptionFee_BelowThreshold(
        IDynamicFeeCalculator_v1.DynamicFeeParameters memory feeParams_,
        uint premiumRate_
    ) public {
        IDynamicFeeCalculator_v1.DynamicFeeParameters memory feeParams =
            helper_setDynamicFeeCalculatorParams(feeParams_);

        // Given: premiumRate is below A_issueRedeem
        vm.assume(
            premiumRate_ > 1 && premiumRate_ < type(uint64).max
                && premiumRate_ < feeParams.A_issueRedeem
        );

        uint fee = feeCalculator.calculateRedemptionFee(premiumRate_);
        assertEq(
            fee,
            feeParams.Z_issueRedeem
                + (feeParams.A_issueRedeem - premiumRate_) * feeParams.m_issueRedeem
                    / 1e18
        );
    }

    function testFuzz_calculateRedemptionFee_AboveThreshold(
        IDynamicFeeCalculator_v1.DynamicFeeParameters memory feeParams_,
        uint premiumRate_
    ) public {
        IDynamicFeeCalculator_v1.DynamicFeeParameters memory feeParams =
            helper_setDynamicFeeCalculatorParams(feeParams_);

        // Given: premiumRate is above A_issueRedeem
        vm.assume(
            premiumRate_ > 1 && premiumRate_ < type(uint64).max
                && premiumRate_ > feeParams.A_issueRedeem
        );

        uint fee = feeCalculator.calculateRedemptionFee(premiumRate_);
        assertEq(fee, feeParams.Z_issueRedeem);
    }

    // =========================================================================
    // Helper Functions

    function helper_setDynamicFeeCalculatorParams(
        IDynamicFeeCalculator_v1.DynamicFeeParameters memory feeParams_
    )
        internal
        returns (
            IDynamicFeeCalculator_v1.DynamicFeeParameters memory dynamicFeeParameters
        )
    {
        feeParams_.Z_issueRedeem =
            bound(feeParams_.Z_issueRedeem, 1e15, MAX_FEE_PERCENTAGE);
        feeParams_.A_issueRedeem =
            bound(feeParams_.A_issueRedeem, 1e15, MAX_FEE_PERCENTAGE);
        feeParams_.m_issueRedeem =
            bound(feeParams_.m_issueRedeem, 1e15, MAX_FEE_PERCENTAGE);
        feeParams_.Z_origination =
            bound(feeParams_.Z_origination, 1e15, MAX_FEE_PERCENTAGE);
        feeParams_.A_origination =
            bound(feeParams_.A_origination, 1e15, MAX_FEE_PERCENTAGE);
        feeParams_.m_origination =
            bound(feeParams_.m_origination, 1e15, MAX_FEE_PERCENTAGE);

        dynamicFeeParameters = IDynamicFeeCalculator_v1.DynamicFeeParameters({
            Z_issueRedeem: feeParams_.Z_issueRedeem,
            A_issueRedeem: feeParams_.A_issueRedeem,
            m_issueRedeem: feeParams_.m_issueRedeem,
            Z_origination: feeParams_.Z_origination,
            A_origination: feeParams_.A_origination,
            m_origination: feeParams_.m_origination
        });

        feeCalculator.setDynamicFeeCalculatorParams(dynamicFeeParameters);

        return dynamicFeeParameters;
    }
}
