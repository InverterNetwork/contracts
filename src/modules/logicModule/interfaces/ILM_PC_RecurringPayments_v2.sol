// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface ILM_PC_RecurringPayments_v2 {
    //--------------------------------------------------------------------------
    // Structs

    /// @notice Struct that holds the information of a RecurringPayment.
    /// @param  amount The amount of tokens that will be paid out upon triggering the RecurringPayment.
    /// @param  startEpoch The epoch in which the RecurringPayment should start.
    /// @param  lastTriggeredEpoch When was the last epoch this RecurringPayment was triggered.
    /// @param  recipient The recipient address that should receive tokens.
    struct RecurringPayment {
        uint amount;
        uint startEpoch;
        uint lastTriggeredEpoch;
        address recipient;
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Given RecurringPayment id is invalid.
    error Module__LM_PC_RecurringPayments__InvalidRecurringPaymentId();

    /// @notice Start epoch cant be placed before the current epoch.
    error Module__LM_PC_RecurringPayments__InvalidStartEpoch();

    /// @notice Given EpochLength is invalid.
    error Module__LM_PC_RecurringPayments__InvalidEpochLength();

    /// @notice Given startId is not position before endId.
    error Module__LM_PC_RecurringPayments__StartIdNotBeforeEndId();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new recurring payment added.
    /// @param  recurringPaymentId The id of the RecurringPayment.
    /// @param  amount The amount of tokens that should be sent to the recipient address.
    /// @param  startEpoch The epoch in which the payment starts.
    /// @param  lastTriggeredEpoch The epoch in which the payment was last triggered.
    /// @param  recipient The recipient address that should receive tokens.
    event RecurringPaymentAdded(
        uint indexed recurringPaymentId,
        uint amount,
        uint startEpoch,
        uint lastTriggeredEpoch,
        address recipient
    );

    /// @notice Event emitted when a recurring payment was removed.
    /// @param  recurringPaymentId The id of the RecurringPayment.
    event RecurringPaymentRemoved(uint indexed recurringPaymentId);

    /// @notice Event emitted when a recurring payment was triggered.
    /// @param  currentEpoch The current epoch.
    event RecurringPaymentsTriggered(uint indexed currentEpoch);

    /// @notice Event emitted when the epoch length is set.
    /// @param  epochLength The epoch length.
    event EpochLengthSet(uint epochLength);

    //--------------------------------------------------------------------------
    // Getter Functions

    /// @notice Returns the length of an epoch.
    /// @return epochLength Length of an epoch in a uint timestamp.
    function getEpochLength() external view returns (uint epochLength);

    /// @notice Returns the RecurringPayment instance with id `id`.
    /// @param  id The id of the RecurringPayment to return.
    /// @return RecurringPayment with id `id`.
    function getRecurringPaymentInformation(uint id)
        external
        view
        returns (RecurringPayment memory);

    /// @notice Returns total list of RecurringPayment ids.
    /// @dev	List is in ascending order.
    /// @return List of RecurringPayment ids.
    function listRecurringPaymentIds() external view returns (uint[] memory);

    /// @notice Returns the id of previous RecurringPayment.
    /// @param  id The id of the RecurringPayment to return.
    /// @return prevId The id of previous RecurringPayment.
    function getPreviousPaymentId(uint id)
        external
        view
        returns (uint prevId);

    /// @notice Returns whether RecurringPayment with id `id` exists.
    /// @param  id The id of the RecurringPayment to test.
    /// @return True if RecurringPayment with id `id` exists, false otherwise.
    function isExistingRecurringPaymentId(uint id)
        external
        view
        returns (bool);

    //--------------------------------------------------------------------------
    // Epoch Functions

    /// @notice Calculates the epoch from a given uint timestamp.
    /// @dev	Calculation is: timestamp divided by epochLength.
    /// @param  timestamp A timestamp in a uint format.
    /// @return epoch Epoch in which timestamp belongs to.
    function getEpochFromTimestamp(uint timestamp)
        external
        view
        returns (uint epoch);

    /// @notice Calculates the current epoch.
    /// @dev	Calculation is: block.timestamp divided by epochLength.
    /// @return epoch Epoch in which current timestamp (block.timestamp) belongs to.
    function getCurrentEpoch() external view returns (uint epoch);

    /// @notice Calculates a future epoch x epochs from now.
    /// @dev	Calculation is: current epoch + X epochs in the future = futureEpoch.
    /// @param  xEpochsInTheFuture How many epochs from the current epoch.
    /// @return futureEpoch Epoch in the future.
    function getFutureEpoch(uint xEpochsInTheFuture)
        external
        view
        returns (uint futureEpoch);

    //--------------------------------------------------------------------------
    // Mutating Functions

    /// @notice Adds a recurring payment to the manager.
    /// @dev	a new id is created for each Payment.
    /// @param  amount Amount of tokens send to the recipient address.
    /// @param  startEpoch Epoch in which the payment starts. Use getEpochFromTimestamp() or
    ///                   getCurrentEpoch() to get the appropriate epoch.
    /// @param  recipient Recipient address that should receive tokens.
    /// @return id Id of the newly created recurring payment.
    function addRecurringPayment(
        uint amount,
        uint startEpoch,
        address recipient
    ) external returns (uint id);

    /// @notice Removes a recurring Payment.
    /// @param  prevId Id of the previous recurring payment in the payment list.
    /// @param  id Id of the recurring payment that is to be removed.
    function removeRecurringPayment(uint prevId, uint id) external;

    //--------------------------------------------------------------------------
    // Trigger

    /// @notice Triggers the start of the due payments for all recurring payment orders.
    function trigger() external;

    /// @notice See trigger() but enables you to determine which ids you want to trigger payment ordes for.
    /// @dev	this is to being able to bypass the unlikely event of having a runOutOfGas error for the normal
    ///         trigger function.
    /// @param  startId : id of start position of the recurring payments that should be triggered.
    /// @param  endId : id of end position of the recurring payments that should be triggered.
    function triggerFor(uint startId, uint endId) external;
}
