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
    error Module__ListAuthorizer__AddressAlreadyAuthorized();
    error Module__ListAuthorizer__AuthorizerListCannotBeEmpty();
    error Module__ListAuthorizer__invalidInitialAuthorizers();

    //--------------------------------------------------------------------------
    // Events

    event AddedAuthorizedAddress(address added);
    event RemovedAuthorizedAddress(address removed);

    //--------------------------------------------------------------------------
    // Modifiers
    modifier notLastAuthorizer() {
        if (amountAuthorized == 1) {
            revert Module__ListAuthorizer__AuthorizerListCannotBeEmpty();
        }
        _;
    }

    modifier validInitialAuthorizers(address[] memory _initialAuthorizers) {
        if (_initialAuthorizers.length == 0) {
            revert Module__ListAuthorizer__invalidInitialAuthorizers();
        }
        for (uint i; i < _initialAuthorizers.length; i++) {
            if (_initialAuthorizers[i] == address(0)) {
                revert Module__ListAuthorizer__invalidInitialAuthorizers();
            }
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
    ) internal onlyInitializing validInitialAuthorizers(initialAuthorizers) {
        __Module_init(proposal, metadata);

        for (uint i = 0; i < initialAuthorizers.length; i++) {
            authorized[initialAuthorizers[i]] = true;
            amountAuthorized++;
            emit AddedAuthorizedAddress(initialAuthorizers[i]);
        }
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @notice Returns whether an address is authorized to facilitate
    ///         the current transaction.
    /// @param  _who  The address on which to perform the check.
    function isAuthorized(address _who)
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
        if (!isAuthorized(_who)) {
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
        if (isAuthorized(_who)) {
            authorized[_who] = false;
            amountAuthorized--;

            emit RemovedAuthorizedAddress(_who);
        }
    }

    /// @notice Transfers authorization from the calling address to a new one.
    /// @param _to The address to transfer the authorization to
    function transferAuthorization(address _to) public virtual onlyAuthorized {
        //In this particular case, I think the method shouldn't be idempotent to avoid confusion.
        if (isAuthorized(_to)) {
            revert Module__ListAuthorizer__AddressAlreadyAuthorized();
        }

        authorized[_to] = true;
        authorized[_msgSender()] = false;

        emit AddedAuthorizedAddress(_to);
        emit RemovedAuthorizedAddress(_msgSender());
    }
}
