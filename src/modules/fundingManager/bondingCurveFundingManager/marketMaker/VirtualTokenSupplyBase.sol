// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// External Dependencies
import {ERC165} from "@oz/utils/introspection/ERC165.sol";

import {IVirtualTokenSupply} from
    "src/modules/fundingManager/bondingCurveFundingManager/marketMaker/IVirtualTokenSupply.sol";

/// @title Virtual Token Supply Management Contract
/// @author Inverter Network
/// @notice This contract manages the virtual token supply, providing functionality to set, get
/// add, and subtract the virtual supply.
/// @dev This abstract contract uses internal state variables for the virtual token supply and employs
/// various internal and external functions for managing it.
abstract contract VirtualTokenSupplyBase is IVirtualTokenSupply, ERC165 {
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165)
        returns (bool)
    {
        bytes4 interfaceId_IVirtualTokenSupply =
            type(IVirtualTokenSupply).interfaceId;
        return interfaceId == interfaceId_IVirtualTokenSupply
            || super.supportsInterface(interfaceId);
    }

    //--------------------------------------------------------------------------
    // Storage

    /// @dev The internal state variable to keep track of the virtual token supply.
    uint internal virtualTokenSupply;
    /// @dev Maximum unsigned integer value for overflow checks.
    uint private constant MAX_UINT = type(uint).max;

    //--------------------------------------------------------------------------
    // Public Functions

    /// @inheritdoc IVirtualTokenSupply
    function getVirtualTokenSupply() external view returns (uint) {
        return _getVirtualTokenSupply();
    }

    //--------------------------------------------------------------------------
    // Public Functions Implemented in Downstream Contract

    /// @inheritdoc IVirtualTokenSupply
    function setVirtualTokenSupply(uint _virtualSupply) external virtual;

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @dev Adds a specified amount to the virtual token supply.
    /// Checks for overflow and reverts if an overflow occurs.
    /// @param _amount The amount to add to the virtual token supply.
    function _addVirtualTokenAmount(uint _amount) internal {
        if (_amount > (MAX_UINT - virtualTokenSupply)) {
            revert VirtualTokenSupply_AddResultsInOverflow();
        }
        unchecked {
            virtualTokenSupply += _amount;
        }

        emit VirtualTokenAmountAdded(_amount, virtualTokenSupply);
    }

    /// @dev Subtracts a specified amount from the virtual token supply.
    /// Checks for underflow and reverts if an underflow occurs.
    /// @param _amount The amount to subtract from the virtual token supply.
    function _subVirtualTokenAmount(uint _amount) internal {
        if (_amount > virtualTokenSupply) {
            revert VirtualTokenSupply__SubtractResultsInUnderflow();
        }

        if (_amount == virtualTokenSupply) {
            revert VirtualTokenSupply__VirtualSupplyCannotBeZero();
        }
        unchecked {
            virtualTokenSupply -= _amount;
        }
        emit VirtualTokenAmountSubtracted(_amount, virtualTokenSupply);
    }

    /// @dev Internal function to directly set the virtual token supply to a new value.
    /// @param _virtualSupply The new value to set for the virtual token supply.
    function _setVirtualTokenSupply(uint _virtualSupply) internal {
        if (_virtualSupply == 0) {
            revert VirtualTokenSupply__VirtualSupplyCannotBeZero();
        }
        emit VirtualTokenSupplySet(_virtualSupply, virtualTokenSupply);
        virtualTokenSupply = _virtualSupply;
    }

    /// @dev Internal view function to return the current virtual token supply.
    /// @return The current virtual token supply as a uint.
    function _getVirtualTokenSupply() internal view returns (uint) {
        return virtualTokenSupply;
    }
}
