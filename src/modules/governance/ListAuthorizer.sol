// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {Types} from "src/common/Types.sol";
import {ContextUpgradeable} from "@oz-up/utils/ContextUpgradeable.sol";
import {Module} from "src/modules/base/Module.sol";

// Interfaces
import {IProposal} from "src/interfaces/IProposal.sol";
import {IAuthorizer} from "src/interfaces/IAuthorizer.sol";

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

contract ListAuthorizer is IAuthorizer, Module{

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
    uint amountAuthorized;


    //--------------------------------------------------------------------------
    // Public Functions

    function initialize(IProposal proposal, bytes memory) external {
        __Module_init(proposal);
    }

    /// @notice Returns whether an address is authorized to facilitate
    ///         the current transaction.
    /// @param  _who  The address on which to perform the check.
    function isAuthorized(address _who) external override view returns (bool) {
        return authorized[_who];
    }

    /// @notice Adds a new address to the list of authorized addresses.
    /// @param _who The address to add to the list of authorized addresses.
    function __Governance_addToAuthorized(address _who) external onlyProposal {
        
        if(authorized[_who]){
            revert Module__AddressAlreadyAuthorized();
        }
        
        authorized[_who] = true;
        amountAuthorized++;
        
        emit AddedAuthorizedAddress(_who);
    }

    /// @notice Adds a new address to the list of authorized addresses.
    /// @dev Relay Function that routes the function call via the proposal
    /// @param _who The address to add to the list of authorized addresses.
    function addToAuthorized(address _who) external onlyAuthorized {

        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Governance_addToAuthorized(address)",
                _who
            ),
            Types.Operation.Call
        );       

        

    }


    function __Governance_removeFromAuthorized(address _who) external onlyProposal {

        if(! authorized[_who]){
            revert Module__AddressAlreadyNotAuthorized();
        }
        
        authorized[_who] = false;
        amountAuthorized--;
        
        emit RemovedAuthorizedAddress(_who);
    }

    /// @notice Removes an address from the list of authorized addresses.
    /// @dev Relay Function that routes the function call via the proposal
    /// @param _who Address to remove authorization from
    function removeFromAuthorized(address _who) external onlyAuthorized {

        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Governance_removeFromAuthorized(address)",
                _who
            ),
            Types.Operation.Call
        );       


    }


    function __Governance_transferAuthorization(address _who) external onlyProposal {
        
        if(authorized[_who]){
            revert Module__AddressAlreadyAuthorized();
        }

        authorized[_who] = true;
        authorized[_msgSender()]=false;

        emit AddedAuthorizedAddress(_who);
        emit RemovedAuthorizedAddress(_msgSender());

    }


    /// @notice Transfers authorization from the calling address to a new one.
    /// @dev Relay Function that routes the function call via the proposal
    /// @param _who The address to transfer the authorization to
    function transferAuthorization(address _who) external onlyAuthorized {

        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Governance_transferAuthorization(address)",
                _who
            ),
            Types.Operation.Call
        );       


    }
}