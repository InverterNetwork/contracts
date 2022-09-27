// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {Module} from "src/modules/base/Module.sol";

// Interfaces
import {IProposal} from "src/interfaces/IProposal.sol";

/**
* @title Contributor manager module
*
* @dev
* This Module handles the list of active contributors in the inverter.
* 
* It saves the assigned role and salary of each contributor in a registry,
* and keeps a list of active contributors in the stile of the Gnosis Safe 
* OwnerManager (https://github.com/safe-global/safe-contracts/blob/main/contracts/base/OwnerManager.sol) 
* 
* Each contributor can only be included in the registry once, but since the 
* role is saved as bytes32, several roles can be specified (and a combined
* salary stored)
*   
*/



contract ContributorManager is Module {

    //--------------------------------------------------------------------------
    // Errors



    //--------------------------------------------------------------------------
    // Events

    event contributorAdded(address who, bytes32 role, uint salary);
    
    event contributorRemoved(address who, bytes32 role, uint salary);

    //--------------------------------------------------------------------------
    // Modifiers

    //--------------------------------------------------------------------------
    // Storage

    struct Contributor {
        bytes32 role;
        uint salary;
    }

    //for retrieval
    address internal constant SENTINEL_CONTRIBUTORS = address(0x1);

    mapping(address => Contributor) internal contributorRegistry;

    // mapping of active contributors (gnosis-safe-like)
    mapping(address => address) internal activeContributors;
    uint internal contributorCount;


    //--------------------------------------------------------------------------
    // Internal Functions


    //--------------------------------------------------------------------------
    // Public Functions

    function initialize(IProposal proposal, bytes memory) external {
        __Module_init(proposal);
        
        //set up SENTINEL_CONTRIBS and (empty) active list
    }


    /// @notice Registers a new contributor and adds them to the list of active 
    ///         contributors.
    function addContributor(address _who, bytes32 _role, uint _salary) external onlyAuthorized{
        //require contributor doesn't already exist
        //require address is not 0
        //require salary is not 0
        //require role is not empty

        //initialize contributorRegistry[address] with contributor

        // add address to activecontributor mapping (gnosis-safe)

        emit contributorAdded(_who, _role, _salary);

    }

    /// @notice Removes a contributor from the registry and from the list of 
    ///         active contributors.
    function removeContributor(address _who) external onlyAuthorized{
        //require contributor already exists
        //require address is not 0

        //save role to temp var
        //save salary to temp var 

        //delete contributorRegistry[_who]

        //remove address from active contributors (gnosis-safe)

        emit contributorRemoved(_who, _role, _salary);



    }

    /// @notice Returns registry information about a specifc contributor    
    function getContributorInformation(address _who) external view returns(bytes32, uint) {
        //require contributor already exists

        return (contributorRegistry[_who].role, contributorRegistry[_who].salary);
        
    }
        
    /// @notice Returns an array with the addresses of all active contributors
    function listActiveContributors() external view returns(address[] memory){
        //return all active contributors as an array of addresses (gnosis-safe)
    }



}