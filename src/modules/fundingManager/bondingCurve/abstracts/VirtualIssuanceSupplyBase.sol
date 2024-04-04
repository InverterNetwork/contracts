// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// External Dependencies
import {ERC165} from "@oz/utils/introspection/ERC165.sol";

import {IVirtualIssuanceSupplyBase} from
    "src/modules/fundingManager/bondingCurve/interfaces/IVirtualIssuanceSupplyBase.sol";

/// @title Virtual Token Supply Management Contract
/// @author Inverter Network
/// @notice This contract manages the virtual issuance token supply, providing functionality to set, get
/// add, and subtract the virtual supply.
/// @dev This abstract contract uses internal state variables for the virtual issuance token supply and employs
/// various internal and external functions for managing it.
abstract contract VirtualIssuanceSupplyBase is
    IVirtualIssuanceSupplyBase,
    ERC165
{
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165)
        returns (bool)
    {
        bytes4 interfaceId_IVirtualIssuanceSupplyBase =
            type(IVirtualIssuanceSupplyBase).interfaceId;
        return interfaceId == interfaceId_IVirtualIssuanceSupplyBase
            || super.supportsInterface(interfaceId);
    }

    //--------------------------------------------------------------------------
    // Storage

    /// @dev The internal state variable to keep track of the virtual issuance token supply.
    uint internal virtualIssuanceSupply;
    /// @dev Maximum unsigned integer value for overflow checks.
    uint private constant MAX_UINT = type(uint).max;

    //--------------------------------------------------------------------------
    // Public Functions

    /// @inheritdoc IVirtualIssuanceSupplyBase
    function getVirtualIssuanceSupply() external view returns (uint) {
        return _getVirtualIssuanceSupply();
    }

    //--------------------------------------------------------------------------
    // Public Functions Implemented in Downstream Contract

    /// @inheritdoc IVirtualIssuanceSupplyBase
    function setVirtualIssuanceSupply(uint _virtualSupply) external virtual;

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @dev Adds a specified amount to the virtual issuance token supply.
    /// Checks for overflow and reverts if an overflow occurs.
    /// @param _amount The amount to add to the virtual issuance token supply.
    function _addVirtualTokenAmount(uint _amount) internal {
        if (_amount > (MAX_UINT - virtualIssuanceSupply)) {
            revert VirtualIssuanceSupplyBase_AddResultsInOverflow();
        }
        unchecked {
            virtualIssuanceSupply += _amount;
        }

        emit VirtualIssuanceAmountAdded(_amount, virtualIssuanceSupply);
    }

    /// @dev Subtracts a specified amount from the virtual issuance token supply.
    /// Checks for underflow and reverts if an underflow occurs.
    /// @param _amount The amount to subtract from the virtual issuance token supply.
    function _subVirtualTokenAmount(uint _amount) internal {
        if (_amount > virtualIssuanceSupply) {
            revert VirtualIssuanceSupplyBase__SubtractResultsInUnderflow();
        }

        if (_amount == virtualIssuanceSupply) {
            revert VirtualIssuanceSupplyBase__VirtualSupplyCannotBeZero();
        }
        unchecked {
            virtualIssuanceSupply -= _amount;
        }
        emit VirtualIssuanceAmountSubtracted(_amount, virtualIssuanceSupply);
    }

    /// @dev Internal function to directly set the virtual issuance token supply to a new value.
    /// @param _virtualSupply The new value to set for the virtual issuance token supply.
    function _setVirtualIssuanceSupply(uint _virtualSupply) internal {
        if (_virtualSupply == 0) {
            revert VirtualIssuanceSupplyBase__VirtualSupplyCannotBeZero();
        }
        emit VirtualIssuanceSupplySet(_virtualSupply, virtualIssuanceSupply);
        virtualIssuanceSupply = _virtualSupply;
    }

    /// @dev Internal view function to return the current virtual issuance token supply.
    /// @return The current virtual issuance token supply as a uint.
    function _getVirtualIssuanceSupply() internal view returns (uint) {
        return virtualIssuanceSupply;
    }
}
