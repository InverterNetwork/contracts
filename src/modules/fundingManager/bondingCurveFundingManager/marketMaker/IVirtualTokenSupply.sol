// SPDX-License-Identifier: LGPL-3.0-only

pragma solidity 0.8.19;

interface IVirtualTokenSupply {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice The virtual supply cannot be zero.
    error VirtualTokenSupply__VirtualSupplyCannotBeZero();

    /// @notice Subtracting would result in an underflow.
    error VirtualTokenSupply__SubtractResultsInUnderflow();

    /// @notice Adding would result in and overflow.
    error VirtualTokenSupply_AddResultsInOverflow();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when virtual token supply has been set
    event VirtualTokenSupplySet(uint indexed newSupply, uint indexed oldSupply);

    /// @notice Event emitted when virtual token amount has been added
    event VirtualTokenAmountAdded(
        uint indexed amountAdded, uint indexed newSupply
    );

    /// @notice Event emitted when virtual token amount has ben subtracted
    event VirtualTokenAmountSubtracted(
        uint indexed amountSubtracted, uint indexed newSupply
    );

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Sets the virtual token supply to a new value.
    /// @dev This function calls the internal function `_setVirtualTokenSupply`.
    /// The function must be implemented by the downstream contract. The downstream contract should
    /// manage access control for setting the supply.
    /// @param _virtualSupply The new value to set for the virtual token supply.
    function setVirtualTokenSupply(uint _virtualSupply) external;

    /// @notice Returns the current virtual token supply.
    /// @dev This function returns the virtual supply by calling the
    /// internal `_getVirtualTokenSupply` function.
    /// @return The current virtual token supply as a uint.
    function getVirtualTokenSupply() external view returns (uint);
}
