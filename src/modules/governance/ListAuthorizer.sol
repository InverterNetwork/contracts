// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// External Dependencies
import {ContextUpgradeable} from "@oz-up/utils/ContextUpgradeable.sol";

// Internal Dependencies
import {Types} from "src/common/Types.sol";
import {Module} from "src/modules/base/Module.sol";

// Interfaces
import {IProposal, IAuthorizer} from "src/proposal/IProposal.sol";

/**
 * @title A simple List-based Authorizer
 *
 * @dev
 * This Module handles the authorization of the smart contract
 * functions
 *
 * It keeps a list authorized addresses and implements the IAuthorizers
 * abstract function "isAuthorized", necessary for the "onlyAuthorized" modifier
 * in the base module contract.
 *
 * The authorized addresses can be anything, ranging from an EOA to a Gnosis
 * multisignature, keeping the module agnostic to the specific governance
 * structure employed.
 */

contract ListAuthorizer is IAuthorizer, Module {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Authorization cannot be transferred to an already authorized address.
    error Module__ListAuthorizer__InvalidAuthorizationTransfer();

    /// @notice The list of authorized address cannot be empty.
    error Module__ListAuthorizer__AuthorizerListCannotBeEmpty();

    /// @notice The supplied list of initial authorized addresses is invalid.
    error Module__ListAuthorizer__invalidInitialAuthorizers();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new address gets authorized.
    /// @param added The newly authorized address.
    event AddedAuthorizedAddress(address added);

    /// @notice Event emitted when an address gets removed from the authorized list.
    /// @param removed The removed address.
    event RemovedAuthorizedAddress(address removed);

    //--------------------------------------------------------------------------
    // Modifiers
    modifier notLastAuthorizer() {
        if (amountAuthorized == 1) {
            revert Module__ListAuthorizer__AuthorizerListCannotBeEmpty();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    /// @dev Mapping of authorized addresses
    mapping(address => bool) private authorized;
    uint private amountAuthorized;

    //--------------------------------------------------------------------------
    // Initialization

    function init(
        IProposal proposal_,
        Metadata memory metadata,
        bytes memory configdata
    ) external virtual override initializer {
        address[] memory initialAuthorizers =
            abi.decode(configdata, (address[]));
        __ListAuthorizer_init(proposal_, metadata, initialAuthorizers);
    }

    function __ListAuthorizer_init(
        IProposal proposal,
        Metadata memory metadata,
        address[] memory initialAuthorizers
    ) internal onlyInitializing {
        __Module_init(proposal, metadata);

        uint intialAuthLength = initialAuthorizers.length;

        if (intialAuthLength == 0) {
            revert Module__ListAuthorizer__invalidInitialAuthorizers();
        }

        for (uint i; i < intialAuthLength; ++i) {
            address current = initialAuthorizers[i];

            if (current == address(0)) {
                revert Module__ListAuthorizer__invalidInitialAuthorizers();
            }

            if (authorized[initialAuthorizers[i]] == true) {
                //duplicate
                revert Module__ListAuthorizer__invalidInitialAuthorizers();
            }

            authorized[current] = true;
            amountAuthorized++;
            emit AddedAuthorizedAddress(current);
        }
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @notice Returns whether an address is authorized to facilitate
    ///         the current transaction.
    /// @param  _who  The address on which to perform the check.
    function isAuthorized(address _who, bytes32 role)
        public
        view
        virtual
        override
        returns (bool)
    {
        return authorized[_who];
    }

    /// @notice Returns the number of authorized addresses
    function getAmountAuthorized() public view returns (uint) {
        return amountAuthorized;
    }

    /// @notice Adds a new address to the list of authorized addresses.
    /// @param _who The address to add to the list of authorized addresses.
    function addToAuthorized(address _who) public virtual onlyAuthorized {
        if (!isAuthorized(_who, bytes32("placeholder role"))) {
            authorized[_who] = true;
            amountAuthorized++;

            emit AddedAuthorizedAddress(_who);
        }
    }

    /// @notice Removes an address from the list of authorized addresses.
    /// @param _who Address to remove authorization from
    function removeFromAuthorized(address _who)
        public
        virtual
        onlyAuthorized
        notLastAuthorizer
    {
        if (isAuthorized(_who, bytes32("placeholder role"))) {
            authorized[_who] = false;
            amountAuthorized--;

            emit RemovedAuthorizedAddress(_who);
        }
    }

    /// @notice Transfers authorization from the calling address to a new one.
    /// @param _to The address to transfer the authorization to
    function transferAuthorization(address _to) public virtual onlyAuthorized {
        //In this particular case the method shouldn't be idempotent to avoid confusion.
        //The extra msgSender check is for the case in which the ListAuthorizer is not the Proposal's main authorizer. In such a case, this module would still be governed by that other authorizer, but we cannot rely on onlyAuthorized == isAuthorized(_msgSender) == true
        if (isAuthorized(_msgSender(), bytes32("placeholder role")) && !isAuthorized(_to, bytes32("placeholder role"))) {
            authorized[_to] = true;
            authorized[_msgSender()] = false;

            emit AddedAuthorizedAddress(_to);
            emit RemovedAuthorizedAddress(_msgSender());
        } else {
            revert Module__ListAuthorizer__InvalidAuthorizationTransfer();
        }
    }
}
