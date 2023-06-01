// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

interface IReocurringPaymentManager {
    struct ReocurringPayment {
        uint amount;
        //in which epoch this should start
        uint startEpoch;
        //When was the last epoch this Payment was triggered
        uint lastTriggeredEpoch;
        address recipient;
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Given ReocurringPayment id is invalid.
    error Module__ReocurringPaymentManager__InvalidReocurringPaymentId();

    /// @notice Start epoch cant be placed before the current epoch.
    error Module__ReocurringPaymentManager__InvalidStartEpoch();

    /// @notice Given EpochLength is too short.
    error Module__ReocurringPaymentManager__EpochLengthToShort();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new milestone added.
    event ReocurringPaymentAdded(
        uint indexed reocurringPaymentId,
        uint amount,
        uint startEpoch,
        uint lastTriggeredEpoch,
        address recipient
    );

    /// @notice Event emitted when a new milestone added.
    event ReocurringPaymentRemoved(uint indexed reocurringPaymentId);

    /// @notice Event emitted when a new milestone added.
    event ReocurringPaymentsTriggered(uint indexed currentEpoch);

    //--------------------------------------------------------------------------
    // Getter Functions

    /// @notice Returns the length of an epoch
    /// @return epochLength Length of an epoch in a uint timestamp
    function getEpochLength() external view returns (uint epochLength);

    /// @notice Returns the ReocurringPayment instance with id `id`.
    /// @param id The id of the ReocurringPayment to return.
    /// @return ReocurringPayment with id `id`.
    function getReocurringPaymentInformation(uint id)
        external
        view
        returns (ReocurringPayment memory);

    /// @notice Returns total list of ReocurringPayment ids.
    /// @dev List is in ascending order.
    /// @return List of ReocurringPayment ids.
    function listReocurringPaymentIds() external view returns (uint[] memory);

    /// @notice Returns the id of previous ReocurringPayment.
    /// @param id The id of the ReocurringPayment to return.
    /// @return prevId The id of previous ReocurringPayment.
    function getPreviousPaymentId(uint id) external view returns (uint prevId) ;

    /// @notice Returns whether ReocurringPayment with id `id` exists.
    /// @return True if ReocurringPayment with id `id` exists, false otherwise.
    function isExistingReocurringPaymentId(uint id)
        external
        view
        returns (bool);

    //--------------------------------------------------------------------------
    // Epoch Functions

    /// @notice Calculates the epoch from a given uint timestamp
    /// @dev Calculation is: timestamp divided by epochLength
    /// @param timestamp : a timestamp in a uint format
    /// @return epoch : epoch in which timestamp belongs to
    function getEpochFromTimestamp(uint timestamp)
        external
        view
        returns (uint epoch);

    /// @notice Calculates the current epoch
    /// @dev Calculation is: block.timestamp divided by epochLength
    /// @return epoch : epoch in which current timestamp (block.timestamp) belongs to
    function getCurrentEpoch() external view returns (uint epoch);

    /// @notice Calculates a future epoch x epochs from now
    /// @dev Calculation is: current epoch + X epochs in the future = futureEpoch
    /// @param xEpochsInTheFuture : how many epochs from the current epoch
    /// @return futureEpoch : epoch in the future
    function getFutureEpoch(uint xEpochsInTheFuture)
        external
        view
        returns (uint futureEpoch);

    //--------------------------------------------------------------------------
    // Mutating Functions

    /// @notice Adds a reocurring payment to the manager
    /// @dev a new id is created for each Payment
    /// @param amount : amount of tokens send to the recipient address
    /// @param startEpoch : epoch in which the payment starts. Use getEpochFromTimestamp() or getCurrentEpoch() to get the appropriate epoch
    /// @param recipient : recipient address that should receive tokens
    /// @return id : id of the newly created reocurring payment
    function addReocurringPayment(
        uint amount,
        uint startEpoch,
        address recipient
    ) external returns (uint id);

    /// @notice Removes a reocurring Payment
    /// @param prevId : id of the previous reocurring payment in the payment list
    /// @param id : id of the reocurring payment that is to be removed
    function removeReocurringPayment(uint prevId, uint id) external;

    //--------------------------------------------------------------------------
    // Trigger

    /// @notice Function that triggers the start of the due payments
    function trigger() external;
}
