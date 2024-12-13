// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IPaymentProcessor_v1} from
    "src/modules/paymentProcessor/IPaymentProcessor_v1.sol";

/**
 * @title   Inverter ERC20 Payment Client Base Interface
 *
 * @notice  Enables modules within the Inverter Network to create and manage payment orders
 *          that can be processed by authorized payment processors, ensuring efficient
 *          and secure transactions. Refer to the implementations contract for more details.
 *
 * @dev     STRUCTURING OF THE FLAGS AND DATA FIELDS
 *          The PaymentOrder struct implements a flag system to manage the information payloads
 *          received by the payment processor. It is comprised of a bytes32 value that indicates
 *          the number of flags that are active, and a bytes32[] value that stores the corresponding values.
 *          and an array of bytes32[], which stores the corresponding values.
 *
 *          For example:    If the value of 'flags' is '0xB, that would correspond to a bit representation of '0000 [...] 0000 1011'.
 *                          This means that the order stores values for the paramters 0, 1 and 3 of the master list (seen below)
 *                          If a module wants to set flags, it can use bit shifts, in this case 1 << 0, 1 << 1 and 1 << 3.
 *                          Afterwards, to be correct, the following data variable should contain 3 elements of the type specified in the master list, each stored as bytes32 value.
 *
 *
 *
 *
 * @author  Inverter Network
 */
interface IERC20PaymentClientBase_v1 {
    //--------------------------------------------------------------------------
    // MASTER LIST OF PAYMENT ORDER FLAGS

    /*
    | Flag | Variable type | Name       | Description                              |
    |------|---------------|------------|------------------------------------------|
    | 0    | bytes32       | orderID    | The ID of the order.                     |
    | 1    | uint256       | start      | The start date of the streaming period.  | 
    | 2    | uint256       | cliff      | The duration of the cliff period.        |
    | 3    | uint256       | end        | The Due Date of the order                |
    */

    //--------------------------------------------------------------------------
    // Structs

    /// @notice Struct used to store information about a payment order.
    /// @param  recipient The recipient of the payment.
    /// @param  paymentToken The token in which to pay. Assumed to always be on the local chain_id.
    /// @param  amount The amount of tokens to pay.
    /// @param  originChainId The chain id of the origin.
    /// @param  targetChainId The chain id on which to find the recipient address.
    /// @param  flags Flags that contain information on the information contained in the data array.
    /// @param  data Array of bytes32 that contain information on the payment order.
    struct PaymentOrder {
        address recipient;
        address paymentToken;
        uint amount;
        uint originChainId;
        uint targetChainId;
        bytes32 flags;
        bytes32[] data;
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by authorized address.
    error Module__ERC20PaymentClientBase__CallerNotAuthorized();

    /// @notice ERC20 token transfer failed.
    error Module__ERC20PaymentClientBase__TokenTransferFailed();

    /// @notice Insufficient funds to fulfill the payment.
    /// @param  token The token in which the payment was made.
    error Module__ERC20PaymentClientBase__InsufficientFunds(address token);

    /// @notice Given recipient invalid.
    error Module__ERC20PaymentClientBase__InvalidRecipient();

    /// @notice Given token invalid.
    error Module__ERC20PaymentClientBase__InvalidToken();

    /// @notice Given amount invalid.
    error Module__ERC20PaymentClientBase__InvalidAmount();

    /// @notice Given paymentOrder is invalid.
    error Module__ERC20PaymentClientBase__InvalidPaymentOrder();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Added a payment order.
    /// @param  recipient The address that will receive the payment.
    /// @param  token The token in which to pay.
    /// @param  amount The amount of tokens the payment consists of.
    /// @param  originChainId The chain id the order originates from.
    /// @param  targetChainId The chain id to which the payment order will be sent.
    /// @param  flags List of flags that are employed by the payment order.
    /// @param  data Array of bytes32 that contain the values for the payment order's used flags.
    event PaymentOrderAdded(
        address indexed recipient,
        address indexed token,
        uint amount,
        uint originChainId,
        uint targetChainId,
        bytes32 flags,
        bytes32[] data
    );

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Returns the list of outstanding payment orders.
    /// @return list of payment orders.
    function paymentOrders() external view returns (PaymentOrder[] memory);

    /// @notice Returns the total outstanding token payment amount.
    /// @param  token_ The token in which to pay.
    /// @return total_ amount of token to pay.
    function outstandingTokenAmount(address token_)
        external
        view
        returns (uint total_);

    /// @notice Collects outstanding payment orders.
    /// @dev	Marks the orders as completed for the client.
    /// @return paymentOrders_ list of payment orders.
    /// @return tokens_ list of token addresses.
    /// @return totalAmounts_ list of amounts.
    function collectPaymentOrders()
        external
        returns (
            PaymentOrder[] memory paymentOrders_,
            address[] memory tokens_,
            uint[] memory totalAmounts_
        );

    /// @notice Notifies the PaymentClient, that tokens have been paid out accordingly.
    /// @dev	Payment Client will reduce the total amount of tokens it will stock up by the given amount.
    /// @dev	This has to be called by a paymentProcessor.
    /// @param  token_ The token in which the payment was made.
    /// @param  amount_ amount of tokens that have been paid out.
    function amountPaid(address token_, uint amount_) external;

    /// @notice Returns the number of flags and the flags of the PaymentOrders this client will create.
    /// @return numOfFlags_ The total number of active flags.
    /// @return flags_ The flags this client will use.
    function getFlags()
        external
        view
        returns (uint8 numOfFlags_, bytes32 flags_);
}
