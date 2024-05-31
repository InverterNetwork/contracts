// SPDX-License-Identifier: LGPL-3.0-only

pragma solidity ^0.8.0;

interface IVirtualIssuanceSupplyBase_v1 {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice The virtual supply cannot be zero.
    error Module__VirtualIssuanceSupplyBase__VirtualSupplyCannotBeZero();

    /// @notice Subtracting would result in an underflow.
    error Module__VirtualIssuanceSupplyBase__SubtractResultsInUnderflow();

    /// @notice Adding would result in and overflow.
    error Module__VirtualIssuanceSupplyBase__AddResultsInOverflow();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when virtual issuance supply has been set
    /// @param newSupply The new virtual issuance supply
    /// @param oldSupply The old virtual issuance supply
    event VirtualIssuanceSupplySet(uint newSupply, uint oldSupply);

    /// @notice Event emitted when virtual issuance amount has been added
    /// @param amountAdded The amount added to the virtual issuance supply
    /// @param newSupply The new virtual issuance supply
    event VirtualIssuanceAmountAdded(uint amountAdded, uint newSupply);

    /// @notice Event emitted when virtual issuance amount has ben subtracted
    /// @param amountSubtracted The amount subtracted from the virtual issuance supply
    /// @param newSupply The new virtual issuance supply
    event VirtualIssuanceAmountSubtracted(
        uint amountSubtracted, uint newSupply
    );

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Sets the virtual issuance supply to a new value.
    /// @dev This function calls the internal function `_setVirtualIssuanceSupply`.
    /// The function must be implemented by the downstream contract. The downstream contract should
    /// manage access control for setting the supply.
    /// @param _virtualSupply The new value to set for the virtual issuance supply.
    function setVirtualIssuanceSupply(uint _virtualSupply) external;

    /// @notice Returns the current virtual issuance supply.
    /// @dev This function returns the virtual supply by calling the
    /// internal `_getVirtualIssuanceSupply` function.
    /// @return The current virtual issuance supply as a uint.
    function getVirtualIssuanceSupply() external view returns (uint);
}
