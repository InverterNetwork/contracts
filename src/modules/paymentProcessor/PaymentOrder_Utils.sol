// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import "forge-std/console.sol";

/**
 * @title   Inverter Simple Payment Processor
 *
 * @notice  Manages ERC20 payment processing for modules within the Inverter Network
 *          that are compliant with the {IERC20PaymentClientBase_v1} interface.
 *
 * @dev     Inherits {Module_v1} and implements {IPaymentProcessor_v1} to handle payment
 *          orders from registered modules, ensuring only eligible modules can initiate
 *          payments. Utilizes {SafeERC20} for secure token transfers.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 */
library PaymentOrder_Utils {
    /*
    | Flag | Variable type | Name       | Description                         |
    |------|---------------|------------|-------------------------------------|
    | 0    | uint256       | orderID    | ID of the order within the client.  |
    | 1    | uint256       | start      | Start date of the streaming period. | 
    | 2    | uint256       | cliff      | Duration of the cliff period.       |
    | 3    | uint256       | end        | Due Date of the order               |
    | ...  | ...           | ...        | (yet unassigned)                    |
    | 255  | .             | .          | (Max Value).                        | 
    |------|---------------|------------|-------------------------------------|
    */

    // Errors
    error PaymentOrder_Utils__FlagAmountTooHigh();

    // Function to generate "bytes32 flags" from an array of uint8's
    function generateFlagConfig(uint8[] calldata flagValues_)
        public
        pure
        returns (bytes32 flagConfig_)
    {
        uint amountOfFlags = flagValues_.length;

        if (amountOfFlags > type(uint8).max) {
            revert PaymentOrder_Utils__FlagAmountTooHigh();
        }

        for (uint8 i = 0; i < amountOfFlags; i++) {
            flagConfig_ |= bytes32((1 << flagValues_[i]));
        }

        return flagConfig_;
    }

    // Fucntion to decode "bytes32 flags" into an array of uint8's
    function decodeFlagConfig(bytes32 flagConfig_)
        public
        view
        returns (uint8[] memory flagValues_)
    {
        uint8[] memory flagValue_buffer = new uint8[](256);
        uint flagCounter = 0;

        for (uint i = 0; i < 256; i++) {
            if (uint(flagConfig_) & (1 << i) != 0) {
                flagValue_buffer[flagCounter] = uint8(i);

                flagCounter++;
            }
        }
        flagValues_ = new uint8[](flagCounter);

        for (uint i = 0; i < flagCounter; i++) {
            flagValues_[i] = flagValue_buffer[i];
        }

        return flagValues_;
    }

    // Function to parse paymentOrder data:
    //  - receive an array of data, the flags it contains, and the flags want to check for
    //  - return an array of the flags that were found in the data, an array with their values, and an array of the flags that were not found

    function parsePaymentOrderData(
        bytes32 targetFlags_,
        bytes32 orderFlags_,
        bytes32[] calldata orderData_
    )
        public
        view
        returns (
            uint8[] memory foundFlags_,
            bytes32[] memory foundValues_,
            uint8[] memory missingFlags_
        )
    {
        // compare order & target flags to find:
        // - the flags that are included in the order
        // - the flags that are missing

        bytes32 foundFlagBytes = targetFlags_ & orderFlags_;
        bytes32 missingFlagBytes = targetFlags_ & ~orderFlags_;

        // decodFlagConfig() for the missing and included flags
        foundFlags_ = decodeFlagConfig(foundFlagBytes);
        missingFlags_ = decodeFlagConfig(missingFlagBytes);

        // create an array that stores the values of the flags that are included in the order
        // go through orderData while checking if the the flag is present in both targetFlags and orderFlags

        uint8 positionInOrderData = 0;
        uint8 positionInReturnData = 0;

        for (uint i = 0; i < 256; i++) {
            if (positionInReturnData == foundFlags_.length) {
                // we have either:
                // - reached the end of the orderData_ array
                // - already checked for all the values this P_P will need
                //      ==> exit loop
                break;
            }

            bool orderBit = (uint(orderFlags_) & (1 << i)) != 0;
            bool processorBit = (uint(targetFlags_) & (1 << i)) != 0;

            if (orderBit == true && processorBit == false) {
                // the P_P does not use that value
                //      ==> skip that data slot in the order
                positionInOrderData++;
            }
            /* if (orderBit == false && processorBit == true) {
                // the P_P needs the value, but it's missing in the order
                //      ==> use default value
                returnData[positionInReturnData] =
                    uint(defaultValues[positionInReturnData]);
                positionInReturnData++;
            }*/
            if (orderBit == true && processorBit == true) {
                // the P_P needs the value, and the order supplies it
                //      ==> use the value from the order
                foundValues_[positionInReturnData] =
                    orderData_[positionInOrderData];
                positionInOrderData++;
                positionInReturnData++;
            }
        }

        //return values
    }
}
