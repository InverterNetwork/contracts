// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Dependencies
import {IVirtualIssuanceSupplyBase_v1} from
    "@fm/bondingCurve/interfaces/IVirtualIssuanceSupplyBase_v1.sol";

// External Dependencies
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

/**
 * @title   Inverter Virtual Issuance Supply Base
 *
 * @notice  Manages a virtual issuance supply to facilitate interactions with Inverter's
 *          Funding Manager
 *
 * @dev     Implements {IVirtualIssuancelSupplyBase_v1} for handling virtual issuance.
 *          Includes functions to set, get, add, and subtract virtual issuance amounts.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 */
abstract contract VirtualIssuanceSupplyBase_v1 is
    IVirtualIssuanceSupplyBase_v1,
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
        bytes4 interfaceId_IVirtualIssuanceSupply =
            type(IVirtualIssuanceSupplyBase_v1).interfaceId;
        return interfaceId == interfaceId_IVirtualIssuanceSupply
            || super.supportsInterface(interfaceId);
    }

    // -------------------------------------------------------------------------
    // Storage

    /// @dev	The internal state variable to keep track of the virtual issuance supply.
    uint internal virtualIssuanceSupply;
    /// @dev	Maximum unsigned integer value for overflow checks.
    uint private constant MAX_UINT = type(uint).max;

    /// @dev	Storage gap for future upgrades.
    uint[50] private __gap;

    // -------------------------------------------------------------------------
    // Public Functions

    /// @inheritdoc IVirtualIssuanceSupplyBase_v1
    function getVirtualIssuanceSupply() external view virtual returns (uint) {
        return virtualIssuanceSupply;
    }

    // -------------------------------------------------------------------------
    // Public Functions Implemented in Downstream Contract

    /// @inheritdoc IVirtualIssuanceSupplyBase_v1
    function setVirtualIssuanceSupply(uint _virtualSupply) external virtual;

    // -------------------------------------------------------------------------
    // Internal Functions

    /// @dev    Adds a specified amount to the virtual issuance supply.
    ///         Checks for overflow and reverts if an overflow occurs.
    /// @param  _amount The amount to add to the virtual issuance supply.
    function _addVirtualIssuanceAmount(uint _amount) internal virtual {
        if (_amount > (MAX_UINT - virtualIssuanceSupply)) {
            revert Module__VirtualIssuanceSupplyBase__AddResultsInOverflow();
        }
        unchecked {
            virtualIssuanceSupply += _amount;
        }

        emit VirtualIssuanceAmountAdded(_amount, virtualIssuanceSupply);
    }

    /// @dev    Subtracts a specified amount from the virtual issuance supply.
    ///         Checks for underflow and reverts if an underflow occurs.
    /// @param  _amount The amount to subtract from the virtual issuance supply.
    function _subVirtualIssuanceAmount(uint _amount) internal virtual {
        if (_amount > virtualIssuanceSupply) {
            revert Module__VirtualIssuanceSupplyBase__SubtractResultsInUnderflow(
            );
        }

        if (_amount == virtualIssuanceSupply) {
            revert Module__VirtualIssuanceSupplyBase__VirtualSupplyCannotBeZero(
            );
        }
        unchecked {
            virtualIssuanceSupply -= _amount;
        }
        emit VirtualIssuanceAmountSubtracted(_amount, virtualIssuanceSupply);
    }

    /// @dev	Internal function to directly set the virtual issuance supply to a new value.
    /// @param  _virtualSupply The new value to set for the virtual issuance supply.
    function _setVirtualIssuanceSupply(uint _virtualSupply) internal virtual {
        if (_virtualSupply == 0) {
            revert Module__VirtualIssuanceSupplyBase__VirtualSupplyCannotBeZero(
            );
        }
        emit VirtualIssuanceSupplySet(_virtualSupply, virtualIssuanceSupply);
        virtualIssuanceSupply = _virtualSupply;
    }
}
