// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {PaymentOrder_Utils} from "@pp/PaymentOrder_Utils.sol";

contract PaymentOrder_Utils_v1Test is Test {
    error PaymentOrder_Utils__FlagAmountTooHigh();
    /*
    generateFlagConfig
    ├── when amountOfFlags is bigger than the maximum uint8 value
    │   └── then it should revert
    └── when amountOfFlags is smaller or equal to the maximum uint8 value
        └── it should loop through all the flags
            └── it should set the byte corresponding to the flag value to 1 in the flagConfig_ to 1 for each flag
    */

    function test_generateFlagConfig_failsWhenAmountOfFlagsIsTooHigh(
        uint numOfFlags
    ) public {
        numOfFlags = bound(numOfFlags, uint(type(uint8).max) + 1, 512);

        uint8[] memory bufArray = new uint8[](numOfFlags);

        vm.expectRevert(PaymentOrder_Utils__FlagAmountTooHigh.selector);
        PaymentOrder_Utils.generateFlagConfig(bufArray);
    }

    function test_generateFlagConfig_WhenAmountOfFlagsIsWithinBounds(
        uint8[] calldata flags_
    ) public {
        vm.assume(flags_.length <= type(uint8).max);

        bytes32 emptyFlagConfig = bytes32(0);
        bytes32 incrementalFlagConfig = bytes32(0);

        for (uint i = 0; i < flags_.length; i++) {
            bytes32 testFlagConfig; // value under testing

            // we test setting only that one flag
            uint8[] memory bufferFlag = new uint8[](1);
            bufferFlag[0] = flags_[i];

            bytes32 bufferFlagConfig =
                emptyFlagConfig | bytes32((1 << bufferFlag[0]));

            testFlagConfig = PaymentOrder_Utils.generateFlagConfig(bufferFlag);
            assertEq(testFlagConfig, bufferFlagConfig);

            //we test incrementally setting that flag
            incrementalFlagConfig |= bufferFlagConfig;

            testFlagConfig =
                PaymentOrder_Utils.generateFlagConfig(flags_[:(i + 1)]);
            assertEq(testFlagConfig, incrementalFlagConfig);
        }
    }

    /*
    decodeFlagConfig
    └── it should loop through all the flag bytes
        └── it should return an array with each set flag stored as a uint8
    */

    function test_decodeFlagConfig(uint8[] calldata flagValues_) public {
        if (flagValues_.length > 256) flagValues_ = flagValues_[0:256];

        bytes32 emptyFlagConfig = bytes32(0);
        bytes32 incrementalFlagConfig = bytes32(0);

        for (uint i = 0; i < flagValues_.length; i++) {
            uint8[] memory testDecodeResult;
            // test that single flag
            bytes32 bufFlagConfig =
                emptyFlagConfig | bytes32((1 << flagValues_[i]));

            testDecodeResult =
                PaymentOrder_Utils.decodeFlagConfig(bufFlagConfig);
            assertEq(testDecodeResult[0], flagValues_[i]);

            // test the flag incrementally
            incrementalFlagConfig |= bufFlagConfig;

            testDecodeResult =
                PaymentOrder_Utils.decodeFlagConfig(incrementalFlagConfig);

            //encode the testDecode result
            bytes32 bufEncodeDecodedValue =
                PaymentOrder_Utils.generateFlagConfig(testDecodeResult);
            // compare with incrementalFlagConfig
            assertEq(bufEncodeDecodedValue, incrementalFlagConfig);

            // the same, but in the other direction: we check that all the flags in the result are in the original flags
            uint foundCount = 0;
            for (uint j = 0; j < testDecodeResult.length; j++) {
                for (uint k = 0; k <= i; k++) {
                    // we check that all the flags that have appeared until now are in the result
                    if (testDecodeResult[j] == flagValues_[k]) {
                        foundCount++;
                        break;
                    }
                }
            }
            assertEq(foundCount, testDecodeResult.length);
        }
    }

    //MISSING: parsePaymentOrderData Tests
    /*
    parsePaymentOrderData
    └── it should go compare the needed flags with the flags provided in the order
        ├── it should return the flags that are missing in the order
        ├── it should return the flags that are present in the order
        └── it should return the values of the flags that are present in the order
    */
    function test_parsePaymentOrderData(
        uint8[] calldata targetFlags_,
        uint8[] calldata orderFlags_,
        bytes32[] calldata orderValues_
    ) public {
        if (targetFlags_.length > 256) targetFlags_ = targetFlags_[0:256];
        if (orderFlags_.length > 256) orderFlags_ = orderFlags_[0:256];
        if (orderValues_.length > orderFlags_.length) {
            orderValues_ = orderValues_[0:orderFlags_.length];
        }

        bytes32 targetFlagConfig =
            PaymentOrder_Utils.generateFlagConfig(targetFlags_);
        bytes32 orderFlagConfig =
            PaymentOrder_Utils.generateFlagConfig(orderFlags_);

        (
            uint8[] memory missingFlags_,
            uint8[] memory foundFlags_,
            bytes32[] memory foundValues_
        ) = PaymentOrder_Utils.parsePaymentOrderData(
            targetFlagConfig, orderFlagConfig, orderValues_
        );

        uint countFoundFlags = 0;
        uint countMissingFlags = 0;

        // TODO: FINISH TEST
        // There is sth fishy in the loop regarding the if that breaks the loop
        // Shouldn't we just check if we found all the values we needed?
    }
}
