// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// External Dependencies
import {ERC165} from "@oz/utils/introspection/ERC165.sol";

import {IVirtualCollateralSupplyBase} from
    "src/modules/fundingManager/bondingCurve/interfaces/IVirtualCollateralSupplyBase.sol";

/// @title VirtualCollateralSupplyBase Contract
/// @author Inverter Network
/// @notice This contract manages the virtual collateral supply, providing functionality to set, get
/// add, and subtract the virtual supply.
/// @dev This abstract contract uses internal state variables for the virtual collateral supply and employs
/// various internal and external functions for managing it.
abstract contract VirtualCollateralSupplyBase is
    IVirtualCollateralSupplyBase,
    ERC165
{
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165)
        returns (bool)
    {
        bytes4 interfaceId_IVirtualCollateralSupplyBase =
            type(IVirtualCollateralSupplyBase).interfaceId;
        return interfaceId == interfaceId_IVirtualCollateralSupplyBase
            || super.supportsInterface(interfaceId);
    }

    //--------------------------------------------------------------------------
    // Storage

    /// @dev The internal state variable to keep track of the virtual collateral supply.
    uint internal virtualCollateralSupply;
    /// @dev Maximum unsigned integer value for overflow checks.
    uint private constant MAX_UINT = type(uint).max;

    //--------------------------------------------------------------------------
    // Public Functions
    /// @inheritdoc IVirtualCollateralSupplyBase
    function getVirtualCollateralSupply() external view returns (uint) {
        return _getVirtualCollateralSupply();
    }

    //--------------------------------------------------------------------------
    // Public Functions Implemented in Downstream Contract

    /// @inheritdoc IVirtualCollateralSupplyBase
    function setVirtualCollateralSupply(uint _virtualSupply) external virtual;

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @dev Adds a specified amount to the virtual collateral supply.
    /// Checks for overflow and reverts if an overflow occurs.
    /// @param _amount The amount to add to the virtual collateral supply.
    function _addVirtualCollateralAmount(uint _amount) internal {
        if (_amount > (MAX_UINT - virtualCollateralSupply)) {
            revert VirtualCollateralSupplyBase_AddResultsInOverflow();
        }
        unchecked {
            virtualCollateralSupply += _amount;
        }

        emit VirtualCollateralAmountAdded(_amount, virtualCollateralSupply);
    }

    /// @dev Subtracts a specified amount from the virtual collateral supply.
    /// Checks for underflow and reverts if an underflow occurs.
    /// @param _amount The amount to subtract from the virtual collateral supply.
    function _subVirtualCollateralAmount(uint _amount) internal {
        if (_amount > virtualCollateralSupply) {
            revert VirtualCollateralSupplyBase__SubtractResultsInUnderflow();
        }

        if (_amount == virtualCollateralSupply) {
            revert VirtualCollateralSupplyBase__VirtualSupplyCannotBeZero();
        }
        unchecked {
            virtualCollateralSupply -= _amount;
        }

        emit VirtualCollateralAmountSubtracted(_amount, virtualCollateralSupply);
    }

    /// @dev Internal function to directly set the virtual collateral supply to a new value.
    /// @param _virtualSupply The new value to set for the virtual collateral supply.
    function _setVirtualCollateralSupply(uint _virtualSupply) internal {
        if (_virtualSupply == 0) {
            revert VirtualCollateralSupplyBase__VirtualSupplyCannotBeZero();
        }
        emit VirtualCollateralSupplySet(_virtualSupply, virtualCollateralSupply);
        virtualCollateralSupply = _virtualSupply;
    }

    /// @dev Internal view function to return the current virtual collateral supply.
    /// @return The current virtual collateral supply as a uint.
    function _getVirtualCollateralSupply() internal view returns (uint) {
        return virtualCollateralSupply;
    }
}
