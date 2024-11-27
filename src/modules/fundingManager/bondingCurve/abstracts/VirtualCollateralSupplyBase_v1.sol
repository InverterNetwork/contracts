// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Dependencies
import {IVirtualCollateralSupplyBase_v1} from
    "@fm/bondingCurve/interfaces/IVirtualCollateralSupplyBase_v1.sol";

// External Dependencies
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

/**
 * @title   Inverter Virtual Collateral Supply Base
 *
 * @notice  Manages a virtual collateral supply to facilitate interactions with Inverter's
 *          Funding Manager
 *
 * @dev     Implements {IVirtualCollateralSupplyBase_v1} for handling virtual collateral.
 *          Includes functions to set, get, add, and subtract virtual collateral amounts.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 */
abstract contract VirtualCollateralSupplyBase_v1 is
    IVirtualCollateralSupplyBase_v1,
    ERC165Upgradeable
{
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165Upgradeable)
        returns (bool)
    {
        bytes4 interfaceId_IVirtualCollateralSupply =
            type(IVirtualCollateralSupplyBase_v1).interfaceId;
        return interfaceId == interfaceId_IVirtualCollateralSupply
            || super.supportsInterface(interfaceId);
    }

    // -------------------------------------------------------------------------
    // Storage

    /// @dev	The internal state variable to keep track of the virtual collateral supply.
    uint internal virtualCollateralSupply;
    /// @dev	Maximum unsigned integer value for overflow checks.
    uint private constant MAX_UINT = type(uint).max;

    /// @dev	Storage gap for future upgrades.
    uint[50] private __gap;

    // -------------------------------------------------------------------------
    // Public Functions
    /// @inheritdoc IVirtualCollateralSupplyBase_v1
    function getVirtualCollateralSupply()
        external
        view
        virtual
        returns (uint)
    {
        return virtualCollateralSupply;
    }

    // -------------------------------------------------------------------------
    // Public Functions Implemented in Downstream Contract

    /// @inheritdoc IVirtualCollateralSupplyBase_v1
    function setVirtualCollateralSupply(uint _virtualSupply) external virtual;

    // -------------------------------------------------------------------------
    // Internal Functions

    /// @dev    Adds a specified amount to the virtual collateral supply.
    ///         Checks for overflow and reverts if an overflow occurs.
    /// @param  _amount The amount to add to the virtual collateral supply.
    function _addVirtualCollateralAmount(uint _amount) internal virtual {
        if (_amount > (MAX_UINT - virtualCollateralSupply)) {
            revert Module__VirtualCollateralSupplyBase__AddResultsInOverflow();
        }
        unchecked {
            virtualCollateralSupply += _amount;
        }

        emit VirtualCollateralAmountAdded(_amount, virtualCollateralSupply);
    }

    /// @dev    Subtracts a specified amount from the virtual collateral supply.
    ///         Checks for underflow and reverts if an underflow occurs.
    /// @param  _amount The amount to subtract from the virtual collateral supply.
    function _subVirtualCollateralAmount(uint _amount) internal virtual {
        if (_amount > virtualCollateralSupply) {
            revert
                Module__VirtualCollateralSupplyBase__SubtractResultsInUnderflow();
        }

        if (_amount == virtualCollateralSupply) {
            revert
                Module__VirtualCollateralSupplyBase__VirtualSupplyCannotBeZero();
        }
        unchecked {
            virtualCollateralSupply -= _amount;
        }

        emit VirtualCollateralAmountSubtracted(_amount, virtualCollateralSupply);
    }

    /// @dev	Internal function to directly set the virtual collateral supply to a new value.
    /// @param  _virtualSupply The new value to set for the virtual collateral supply.
    function _setVirtualCollateralSupply(uint _virtualSupply)
        internal
        virtual
    {
        if (_virtualSupply == 0) {
            revert
                Module__VirtualCollateralSupplyBase__VirtualSupplyCannotBeZero();
        }
        emit VirtualCollateralSupplySet(_virtualSupply, virtualCollateralSupply);
        virtualCollateralSupply = _virtualSupply;
    }
}
