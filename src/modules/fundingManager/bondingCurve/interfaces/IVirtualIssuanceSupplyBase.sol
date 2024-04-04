// SPDX-License-Identifier: LGPL-3.0-only

pragma solidity ^0.8.0;

interface IVirtualIssuanceSupplyBase {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice The virtual supply cannot be zero.
    error VirtualIssuanceSupplyBase__VirtualSupplyCannotBeZero();

    /// @notice Subtracting would result in an underflow.
    error VirtualIssuanceSupplyBase__SubtractResultsInUnderflow();

    /// @notice Adding would result in and overflow.
    error VirtualIssuanceSupplyBase_AddResultsInOverflow();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when virtual issuance token supply has been set
    /// @param newSupply The new virtual issuance token supply
    /// @param oldSupply The old virtual issuance token supply
    event VirtualIssuanceSupplySet(
        uint indexed newSupply, uint indexed oldSupply
    );

    /// @notice Event emitted when virtual token amount has been added
    /// @param amountAdded The amount added to the virtual issuance token supply
    /// @param newSupply The new virtual issuance token supply
    event VirtualIssuanceAmountAdded(
        uint indexed amountAdded, uint indexed newSupply
    );

    /// @notice Event emitted when virtual token amount has ben subtracted
    /// @param amountSubtracted The amount subtracted from the virtual issuance token supply
    /// @param newSupply The new virtual issuance token supply
    event VirtualIssuanceAmountSubtracted(
        uint indexed amountSubtracted, uint indexed newSupply
    );

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Sets the virtual issuance token supply to a new value.
    /// @dev This function calls the internal function `_setVirtualIssuanceSupply`.
    /// The function must be implemented by the downstream contract. The downstream contract should
    /// manage access control for setting the supply.
    /// @param _virtualSupply The new value to set for the virtual issuance token supply.
    function setVirtualIssuanceSupply(uint _virtualSupply) external;

    /// @notice Returns the current virtual issuance token supply.
    /// @dev This function returns the virtual supply by calling the
    /// internal `_getVirtualIssuanceSupply` function.
    /// @return The current virtual issuance token supply as a uint.
    function getVirtualIssuanceSupply() external view returns (uint);
}
