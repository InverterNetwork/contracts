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
    mapping(address => bool) private authorized;
    uint amountAuthorized;


    //--------------------------------------------------------------------------
    // Public Functions

    function initialize(IProposal proposal, bytes memory) external {
        __Module_init(proposal);
    }

    /// @notice Returns whether an address is authorized to facilitate
    ///         the current transaction.
    function isAuthorized(address _who) external override view returns (bool) {
        return authorized[_who];
    }

    /// @notice Adds a new address to the list of authorized addresses.
    function addToAuthorized(address _who) external onlyAuthorized {
        
        require(!authorized[_who], "Address already authorized");
        
        authorized[_who] = true;
        amountAuthorized++;
        
        emit AddedAuthorizedAddress(_who);
    }

    /// @notice Removes an address from the list of authorized addresses.
    function removeFromAuthorized(address _who) external onlyAuthorized {
        
        //Added the "already" to error message to avoid confusion regarding access control errors
        require(authorized[_who], "Address already not authorized");
        
        authorized[_who] = false;
        amountAuthorized--;
        
        emit RemovedAuthorizedAddress(_who);
    }

    /// @notice Transfers authorization from the calling address to a new one.
    function transferAuthorization(address _who) external onlyAuthorized {

        require(!authorized[_who], "Address already authorized");

        authorized[_who] = true;
        authorized[_msgSender()]=false;

        emit AddedAuthorizedAddress(_who);
        emit RemovedAuthorizedAddress(_msgSender());
    }

    /*
        requiredQuorum() - Returns the number of confirmations that a certain action requires before it may be executed
        changeQuorum() - Updates the number of confirmations that a certain action requires before it may be executed
        confirmAction(action) - Confirms a queued action that has been initiated by another authorized address. It automatically executes the action if the quorum has been reached.
        cancelAction(action)
    */

    /// @notice This is the part that maybe could be "delegated" to the calling
    ///         addresses, i.e Gnosis Safe, Aragon DAO, etc.
    

    event QuorumModified(uint newQuorum);
    
    error Module__alreadyVoted(address who);
    error Module__voteNotActive(uint voteID);
    error Module__quorumIsZero();
    error Module_quorumUnreachable();

    struct Vote {
        bool isActive;
        bytes encodedAction;
        mapping(address => bool) hasVoted;
        uint aye;
        uint nay;

    }
    
    mapping(uint => Vote ) voteRegistry;
    uint voteIDCounter;

    uint8 quorum;

    function requiredQuorum() external view returns(uint8){
        return quorum;
    }

    function changeQuorum(uint8 _new) external onlyAuthorized {
        if(_new == 0){
            revert Module__quorumIsZero();
        }
        if(_new > amountAuthorized){
            revert Module_quorumUnreachable();
        }

        quorum = _new;

        emit QuorumModified(_new);

    }

    function createVote(bytes calldata _encodedAction) external onlyAuthorized{
        voteRegistry[voteIDCounter].isActive = true;
        voteRegistry[voteIDCounter].encodedAction = _encodedAction;

        voteIDCounter++;

        
    }

    function confirmAction(uint _voteID) external onlyAuthorized{
        // Ensure that the vote is active (and exists)
        if(! voteRegistry[_voteID].isActive ){
            revert Module__voteNotActive(_voteID);
        }

        // Ensure voter hasn't voted yet
        if(voteRegistry[_voteID].hasVoted[_msgSender()]){
            revert Module__alreadyVoted(_msgSender());
        }


        voteRegistry[_voteID].hasVoted[_msgSender()] = true;
        voteRegistry[_voteID].aye++;
        

        // If enough confirmations happened, execute vote
        if(voteRegistry[_voteID].aye >= quorum){
            executeVote(_voteID);
        }

    }

    function cancelAction(uint _voteID) external onlyAuthorized{
        // Ensure that the vote is active (and exists)
        if(! voteRegistry[_voteID].isActive ){
            revert Module__voteNotActive(_voteID);
        }

        // Ensure voter hasn't voted yet
        if(voteRegistry[_voteID].hasVoted[_msgSender()]){
            revert Module__alreadyVoted(_msgSender());
        }

        voteRegistry[_voteID].hasVoted[_msgSender()] = true;
        voteRegistry[_voteID].nay++;
        
        // If enough denials happened, cancel vote
        if(voteRegistry[_voteID].nay >= quorum){
            voteRegistry[_voteID].isActive= false;
        }

    }


    function executeVote(uint _voteID) internal{
        // Ensure that the vote is active (and exists)
        if(! voteRegistry[_voteID].isActive ){
            revert Module__voteNotActive(_voteID);
        }
        
        // Deactivate the vote
        voteRegistry[_voteID].isActive= false;


        // execute stuff? should this override _triggerProposalCallback
        // and call voteRegistry[_voteID].encodedAction with a custom address
        // from another module as caller?


    }

}
