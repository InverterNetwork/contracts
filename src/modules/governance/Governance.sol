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

    /*
        requiredQuorum() - Returns the number of confirmations that a certain action requires before it may be executed
        changeQuorum() - Updates the number of confirmations that a certain action requires before it may be executed
        confirmAction(action) - Confirms a queued action that has been initiated by another authorized address. It automatically executes the action if the quorum has been reached.
        cancelAction(action)
    */

    /// @notice This is the part that maybe could be "delegated" to the calling
    ///         addresses, i.e Gnosis Safe, Aragon DAO, etc.
    

    event QuorumModified(uint8 oldQuorum, uint8 newQuorum);

    event VoteEnacted(uint voteID);
    event VotedInFavor(address who, uint voteID);
    event VotedAgainst(address who, uint voteID);
    event VoteCancelled(uint _voteID);

    


    error Module__addressAlreadyVoted(address who);
    error Module__voteNotActive(uint voteID);
    event Module__ExecuteVoteFailed();

    error Module__invalidAddress();
    error Module__invalidEncodedAction();

    error Module__quorumIsZero();
    error Module_quorumUnreachable();



    /// @notice This struct stores the information of a governance vote
    /// @param isActive False if canceled or executed
    /// @param encodedAction The tx to be executed, in ABI encoded format
    /// @param targetAddress The Module address to execute the tx on
    /// @param hasVoted Stores all addresses who already voted
    /// @param aye "Yes" votes
    /// @param nay "No" votes
    struct Vote {
        bool isActive;
        bytes encodedAction;
        address targetAddress;
        mapping(address => bool) hasVoted;
        uint aye;
        uint nay;

    }
    
    /// @notice Registry of created votes with corresponding ID
    mapping(uint => Vote ) voteRegistry;
    uint voteIDCounter;

    /// @notice Quorum necessary to pass/deny a vote
    uint8 quorum;

    /// @notice Returns the current required quorum
    function requiredQuorum() external view returns(uint8){
        return quorum;
    }


    /// @notice Sets a new quorum
    /// @param _new The new quorum
    function __Governance_changeQuorum(uint8 _new) external onlyProposal {

        if(_new == 0){
            revert Module__quorumIsZero();
        }
        if(_new > amountAuthorized){
            revert Module_quorumUnreachable();
        }

        uint8 old= quorum;
        quorum = _new;

        emit QuorumModified(old, quorum);

    }

    /// @notice Sets a new quorum
    /// @dev Relay Function that routes the function call via the proposal
    /// @param _new The new quorum
    function changeQuorum(uint8 _new) external onlyAuthorized {


        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Governance_changeQuorum(uint8)",
                _new
            ),
            Types.Operation.Call
        );       


    }


    /// @notice Creates a new vote
    /// @param _target The Module from which to execute the action
    /// @param _encodedAction The ABI encoded action to execute if it passes
    function __Governance_createVote(address _target, bytes calldata _encodedAction) external onlyProposal{

        if(_target == address(0)){
            revert Module__invalidAddress();
        }
        ///Check if _encoded action correct? Or only if not zero?

        voteRegistry[voteIDCounter].isActive = true;
        voteRegistry[voteIDCounter].targetAddress = _target;
        voteRegistry[voteIDCounter].encodedAction = _encodedAction;

        voteIDCounter++;

    }


    /// @notice Creates a new vote
    /// @dev Relay Function that routes the function call via the proposal
    /// @param _target The Module from which to execute the action
    /// @param _encodedAction The ABI encoded action to execute if it passes
    function createVote(address _target, bytes calldata _encodedAction) external onlyAuthorized{

        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Governance_createVote(address,bytes)",
                _target,
                _encodedAction
            ),
            Types.Operation.Call
        );       



        
    }

    /// @notice Vote "yes" and execute action if quorum is reached
    /// @param _voteID The ID of the vote to vote on
    function __Governance_confirmAction(uint _voteID) external onlyProposal{

        // Ensure that the vote is active (and exists)
        if(! voteRegistry[_voteID].isActive ){
            revert Module__voteNotActive(_voteID);
        }

        // Ensure voter hasn't voted yet
        if(voteRegistry[_voteID].hasVoted[_msgSender()]){
            revert Module__addressAlreadyVoted(_msgSender());
        }


        voteRegistry[_voteID].hasVoted[_msgSender()] = true;
        voteRegistry[_voteID].aye++;

        emit VotedInFavor(_msgSender(), _voteID);
        

        // If enough confirmations happened, execute vote
        if(voteRegistry[_voteID].aye >= quorum){
            executeVote(_voteID);
        }


    }

    /// @notice Vote "yes" and execute action if quorum is reached
    /// @dev Relay Function that routes the function call via the proposal
    /// @param _voteID The ID of the vote to vote on
    function confirmAction(uint _voteID) external onlyAuthorized{

        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Governance_confirmAction(uint)",
                _voteID
            ),
            Types.Operation.Call
        );       


    }

    /// @notice Vote "no" and abort action if quorum is reached
    /// @param _voteID The ID of the vote to vote on
    function __Governance_cancelAction(uint _voteID) external onlyProposal{
        // Ensure that the vote is active (and exists)
        if(! voteRegistry[_voteID].isActive ){
            revert Module__voteNotActive(_voteID);
        }

        // Ensure voter hasn't voted yet
        if(voteRegistry[_voteID].hasVoted[_msgSender()]){
            revert Module__addressAlreadyVoted(_msgSender());
        }

        voteRegistry[_voteID].hasVoted[_msgSender()] = true;
        voteRegistry[_voteID].nay++;

        emit VotedAgainst(_msgSender(), _voteID);
        
        // If enough denials happened, cancel vote
        if(voteRegistry[_voteID].nay >= quorum){
            voteRegistry[_voteID].isActive= false;
            emit VoteCancelled(_voteID);
        }

    }

    /// @notice Vote "no" and abort action if quorum is reached
    /// @dev Relay Function that routes the function call via the proposal
    /// @param _voteID The ID of the vote to vote on
    function cancelAction(uint _voteID) external onlyAuthorized{

        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Governance_cancelAction(uint)",
                _voteID
            ),
            Types.Operation.Call
        );       


    }


    /// @notice Execute a vote. Only called by confirmAction once quorum 
    ///         is reached
    /// @param _voteID The ID of the vote to execute
    function executeVote(uint _voteID) internal{

        // Ensure that the vote is active (and exists)
        if(! voteRegistry[_voteID].isActive ){
            revert Module__voteNotActive(_voteID);
        }
        
        // Deactivate the vote
        voteRegistry[_voteID].isActive= false;

        // Tell the proposal to execute the vote
        __Module_proposal.executeTxFromModule(
            voteRegistry[_voteID].targetAddress, 
            voteRegistry[_voteID].encodedAction, 
            Types.Operation.Call
            );

        emit VoteEnacted(_voteID);

    }

}
