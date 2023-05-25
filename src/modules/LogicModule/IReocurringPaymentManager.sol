// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

interface IReocurringPaymentManager {
    struct ReocurringPayment {
        uint amount;
        //in which epoch this should start
        uint startEpoch;
        //When was the last epoch this Payment was triggered
        uint lastTriggeredEpoch;
        address target;
    }
    //@todo add event

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Given ReocurringPayment id invalid.
    error Module__ReocurringPaymentManager__InvalidReocurringPaymentId();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new milestone added.
    event ReocurringPaymentAdded(
        uint indexed reocurringPaymentId,
        uint amount,
        uint startEpoch,
        uint lastTriggeredEpoch,
        address target
    );

    /// @notice Event emitted when a new milestone added.
    event ReocurringPaymentRemoved(
        uint indexed reocurringPaymentId
    );

    /// @notice Event emitted when a new milestone added.
    event ReocurringPaymentsTriggered(
        uint indexed currentEpoch
    );

    //--------------------------------------------------------------------------
    // Getter Functions

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

    /// @notice Returns whether ReocurringPayment with id `id` exists.
    /// @return True if ReocurringPayment with id `id` exists, false otherwise.
    function isExistingReocurringPaymentId(uint id)
        external
        view
        returns (bool);

    //--------------------------------------------------------------------------
    // Mutating Functions

    /// @notice Function that triggers the start of the due payments
    function trigger() external;

    /// @notice Adds a reocurring payment to the manager
    /// @dev a new id is created for each Payment
    /// @param amount : amount of tokens send to the target address
    /// @param startEpoch : epoch in which the payment starts
    /// @param target : target address that should receive tokens
    /// @return id : id of the newly created reocurring payment
    function addReocurringPayment(uint amount, uint startEpoch, address target)
        external
        returns (uint id);

    /// @notice Removes a reocurring Payment
    /// @param prevId : id of the previous reocurring payment in the payment list
    /// @param id : id of the reocurring payment that is to be removed
    function removeReocurringPayment(uint prevId, uint id) external;
}
