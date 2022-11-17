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
 * This Module handles the authorization of several of the smart contract
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
    error Module__AddressAlreadyAuthorized();
    error Module__AddressAlreadyNotAuthorized();

    //--------------------------------------------------------------------------
    // Events

    event AddedAuthorizedAddress(address added);

    event RemovedAuthorizedAddress(address removed);

    //--------------------------------------------------------------------------
    // Storage

    /// @dev Mapping of authorized addresses
    mapping(address => bool) private authorized;
    uint private amountAuthorized;

    //--------------------------------------------------------------------------
    // Initialization

    function initialize(IProposal proposal, Metadata memory metadata)
        external
        initializer
    {
        __Module_init(proposal, metadata);

        //authorize the calling address
        authorized[_msgSender()] = true;
        amountAuthorized++;

        emit AddedAuthorizedAddress(_msgSender());
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @notice Returns whether an address is authorized to facilitate
    ///         the current transaction.
    /// @param  _who  The address on which to perform the check.
    function isAuthorized(address _who) public view override returns (bool) {
        return authorized[_who];
    }

    /// @notice Returns the number of authorized addresses
    function getAmountAuthorized() public view returns (uint) {
        return amountAuthorized;
    }

    /// @notice Adds a new address to the list of authorized addresses.
    /// @param _who The address to add to the list of authorized addresses.
    function __ListAuthorizer_addToAuthorized(address _who)
        public
        virtual
        onlyProposal
    {
        if (!isAuthorized(_who)) {
            authorized[_who] = true;
            amountAuthorized++;

            emit AddedAuthorizedAddress(_who);
        }
    }

    /// @notice Adds a new address to the list of authorized addresses.
    /// @dev Relay Function that routes the function call via the proposal
    /// @param _who The address to add to the list of authorized addresses.
    function addToAuthorized(address _who) external onlyAuthorized {
        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__ListAuthorizer_addToAuthorized(address)", _who
            ),
            Types.Operation.Call
        );
    }

    /// @notice Removes an address from the list of authorized addresses.
    /// @param _who Address to remove authorization from
    function __ListAuthorizer_removeFromAuthorized(address _who)
        public
        virtual
        onlyProposal
    {
        //@question TODO Do we want to allow an empty authorizer list?
        //          My first impulse would be no...

        if (isAuthorized(_who)) {
            authorized[_who] = false;
            amountAuthorized--;

            emit RemovedAuthorizedAddress(_who);
        }
    }

    /// @notice Removes an address from the list of authorized addresses.
    /// @dev Relay Function that routes the function call via the proposal
    /// @param _who Address to remove authorization from
    function removeFromAuthorized(address _who) external onlyAuthorized {
        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__ListAuthorizer_removeFromAuthorized(address)", _who
            ),
            Types.Operation.Call
        );
    }

    /// @notice Transfers authorization from the calling address to a new one.
    /// @param _from The address to transfer the authorization from
    /// @param _to The address to transfer the authorization to
    function __ListAuthorizer_transferAuthorization(address _from, address _to)
        public
        virtual
        onlyProposal
    {
        //I think in this case we actually DO want to revert if the receiving address is already authorized to avoid confusion. The opposite could lead to think that somebedy has "double vote" or something like that. It also saves us implementing quorum management logic downstream.
        if (authorized[_to]) {
            revert Module__AddressAlreadyAuthorized();
        }

        authorized[_to] = true;
        authorized[_from] = false;

        emit AddedAuthorizedAddress(_to);
        emit RemovedAuthorizedAddress(_from);
    }

    /// @notice Transfers authorization from the calling address to a new one.
    /// @dev Relay Function that routes the function call via the proposal
    /// @param _who The address to transfer the authorization to
    function transferAuthorization(address _who) external onlyAuthorized {
        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__ListAuthorizer_transferAuthorization(address,address)",
                _msgSender(),
                _who
            ),
            Types.Operation.Call
        );
    }
}
