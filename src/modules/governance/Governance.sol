// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {ContextUpgradeable} from "@oz-up/utils/ContextUpgradeable.sol";
import {Module} from "src/modules/base/Module.sol";

// Interfaces
import {IProposal} from "src/interfaces/IProposal.sol";
import {IAuthorizer} from "src/interfaces/IAuthorizer.sol";

/**
* @title Authorization-based governance module
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

contract Governance is IAuthorizer, Module{

    
    //--------------------------------------------------------------------------
    // Events

    event AddedAuthorizedAddress(address added);

    event RemovedAuthorizedAddress(address removed);


    //--------------------------------------------------------------------------
    // Storage

    /// @dev Mapping of authorized addresses
    mapping(address => bool) private _authorized;


    //--------------------------------------------------------------------------
    // Public Functions

    function initialize(IProposal proposal, bytes memory) external {
        __Module_init(proposal);
    }

    /// @notice Returns whether an address is authorized to facilitate
    ///         the current transaction.
    function isAuthorized(address who) external override view returns (bool) {
        return _authorized[who];
    }

    /// @notice Adds a new address to the list of authorized addresses.
    function addToAuthorized(address who) external onlyAuthorized {
        
        require(!_authorized[who], "Address already authorized");
        
        _authorized[who] = true;
        
        emit AddedAuthorizedAddress(who);
    }

    /// @notice Removes an address from the list of authorized addresses.
    function removeFromAuthorized(address who) external onlyAuthorized {
        
        //Added the "already" to error message to avoid confusion regarding access control errors
        require(_authorized[who], "Address already not authorized");
        
        _authorized[who] = false;
        
        emit RemovedAuthorizedAddress(who);
    }

    /// @notice Transfers authorization from the calling address to a new one.
    function transferAuthorization(address who) external onlyAuthorized {

        require(!_authorized[who], "Address already authorized");

        _authorized[who] = true;
        _authorized[_msgSender()]=false;

        emit AddedAuthorizedAddress(who);
        emit RemovedAuthorizedAddress(_msgSender());
    }

    /*
        requiredQuorum() - Returns the number of confirmations that a certain action requires before it may be executed
        changeQuorum() - Updates the number of confirmations that a certain action requires before it may be executed
        confirmAction(action) - Confirms a queued action that has been initiated by another authorized address. It automatically executes the action if the quorum has been reached.
        cancelAction(action)
    */
}
