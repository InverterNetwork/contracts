// SPDX-License-Identifier: LGPL-3.0-only

pragma solidity 0.8.19;

interface IVirtualTokenSupply {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Subtracting would result in an underflow.
    error VirtualTokenSupply__SubtractResultsInUnderflow();

    /// @notice Adding would result in and overflow.
    error VirtualTokenSupply_AddResultsInOverflow();

    //--------------------------------------------------------------------------
    // Events

    // TODO: Contract still needs events. Where are events needed?

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Sets the virtual token supply to a new value.
    /// @dev This function calls the internal function `_setVirtualTokenSupply`.
    /// @param _virtualSupply The new value to set for the virtual token supply.
    function setVirtualTokenSupply(uint _virtualSupply) external;

    /// @notice Returns the current virtual token supply.
    /// @dev This function returns the virtual supply by calling the
    /// internal `_getVirtualTokenSupply` function.
    /// @return The current virtual token supply as a uint.
    function getVirtualTokenSupply() external view returns (uint);
}
