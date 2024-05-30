// SPDX-License-Identifier: LGPL-3.0-only

pragma solidity ^0.8.0;

interface IVirtualCollateralSupplyBase_v1 {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice The virtual supply cannot be zero.
    error Module__VirtualCollateralSupplyBase__VirtualSupplyCannotBeZero();

    // @notice Subtracting would result in an underflow.
    error Module__VirtualCollateralSupplyBase__SubtractResultsInUnderflow();

    /// @notice Adding would result in and overflow.
    error Module__VirtualCollateralSupplyBase__AddResultsInOverflow();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when virtual collateral supply has been set
    event VirtualCollateralSupplySet(uint newSupply, uint oldSupply);

    /// @notice Event emitted when virtual collateral amount has been added
    event VirtualCollateralAmountAdded(uint amountAdded, uint newSupply);

    /// @notice Event emitted when virtual collateral amount has been subtracted
    event VirtualCollateralAmountSubtracted(
        uint amountSubtracted, uint newSupply
    );

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Sets the virtual collateral supply to a new value.
    /// @dev This function should call the internal function `_setVirtualCollateralSupply`.
    /// The function must be implemented by the downstream contract. The downstream contract should
    /// manage access control for setting the supply.
    /// @param _virtualSupply The new value to set for the virtual collateral supply.
    function setVirtualCollateralSupply(uint _virtualSupply) external;

    /// @notice Returns the current virtual collateral supply.
    /// @dev This function returns the virtual supply by calling the
    /// internal `_getVirtualCollateralSupply` function.
    /// @return The current virtual collateral supply as a uint.
    function getVirtualCollateralSupply() external view returns (uint);
}
