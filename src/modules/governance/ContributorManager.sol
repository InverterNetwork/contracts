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
* and keeps a list of active contributors in the style of the Gnosis Safe 
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

    /// @notice The supplied contributor address is not valid
    error Module__invalidContributorAddress();

    /// @notice The supplied contributor information is not valid.
    error Module__invalidContributorInformation();

    /// @notice The supplied contributor is already active
    error Module__contributorAlreadyActive();

    /// @notice The supplied contributor is not active
    error Module__contributorNotActive();


    //--------------------------------------------------------------------------
    // Events

    event contributorAdded(address who, bytes32 role, uint salary);
    
    event contributorRemoved(address who, bytes32 role, uint salary);

    //--------------------------------------------------------------------------
    // Modifiers

    //--------------------------------------------------------------------------
    // Storage

    struct Contributor {
        bool active;
        bytes32 role;
        uint salary;
    }

    //for retrieval.
    address internal constant SENTINEL_CONTRIBUTORS = address(0x1);

    mapping(address => Contributor) internal contributorRegistry;

    // mapping of active contributors.
    mapping(address => address) internal activeContributors;
    uint internal contributorCount;


    //--------------------------------------------------------------------------
    // Internal Functions


    //--------------------------------------------------------------------------
    // Public Functions

    function initialize(IProposal proposal, bytes memory) external {
        __Module_init(proposal);

        // set up the sentinel to signal empty list of active contributors
        activeContributors[SENTINEL_CONTRIBUTORS] = SENTINEL_CONTRIBUTORS;
        
    }


    /// @notice Registers a new contributor and adds them to the list of active 
    ///         contributors.
    function addContributor(address _who, bytes32 _role, uint _salary) external onlyAuthorized{

        //require address is not 0, the sentinel or the module itself
        if(_who == address(0) || _who == SENTINEL_CONTRIBUTORS || _who == address(this)) {
            revert Module__invalidContributorAddress();
        }
        //require role is not empty
        if(_role == bytes32(0) || _salary == 0){
            revert Module__invalidContributorInformation();
        }

        //require contributor isn't already active
        if(activeContributors[_who] != address(0) ){
            revert Module__contributorAlreadyActive();
        }

        //initialize contributorRegistry[address] with contributor
        Contributor memory _contributor;
        _contributor.active = true;
        _contributor.role = _role;
        _contributor.salary= _salary;
        
        contributorRegistry[_who] = _contributor;


        // add address to activecontributor mapping (gnosis-safe)
        activeContributors[_who] = activeContributors[SENTINEL_CONTRIBUTORS];
        activeContributors[SENTINEL_CONTRIBUTORS] = _who;
        contributorCount++;

        emit contributorAdded(_who, _role, _salary);

    }

    /// @notice Removes a contributor from the registry and from the list of 
    ///         active contributors. If the contributor to delete is the first
    ///         on the list, _prevContrib should be address(0x1), the sentinel.
    function removeContributor(address _who, address _prevContrib) external onlyAuthorized{
        //require that address is not 0
        if(_who == address(0) || _who == SENTINEL_CONTRIBUTORS || _who == address(this)) {
            revert Module__invalidContributorAddress();
        }
        //require that the contributors are indeed consecutive
        if(activeContributors[_prevContrib] != _who){
            revert Module__invalidContributorAddress();
        }

        //mark the contributor as inactive in the contributorRegistry
        contributorRegistry[_who].active = false;

        //remove address from active contributors (gnosis-safe)
        activeContributors[_prevContrib] = activeContributors[_who];
        activeContributors[_who] = address(0);
        contributorCount--;


        emit contributorRemoved(_who, contributorRegistry[_who].role, contributorRegistry[_who].salary);



    }

    /// @notice Returns registry information about a specifc contributor    
    function getContributorInformation(address _who) external view returns(bytes32, uint) {
        //require contributor is active
        if( ! isActiveContributor(_who) ){
            revert Module__contributorNotActive();
        }

        return (contributorRegistry[_who].role, contributorRegistry[_who].salary);
        
    }

    function isActiveContributor(address _who) public view returns (bool) {
        return _who != SENTINEL_CONTRIBUTORS && activeContributors[_who] != address(0);
    }
        
    /// @notice Returns an array with the addresses of all active contributors
    function listActiveContributors() external view returns(address[] memory){
        //return all active contributors as an array of addresses (gnosis-safe)
        address[] memory array = new address[](contributorCount);

        // populate return array
        uint256 index = 0;
        address currentContributor = activeContributors[SENTINEL_CONTRIBUTORS];
        while (currentContributor != SENTINEL_CONTRIBUTORS) {
            array[index] = currentContributor;
            currentContributor = activeContributors[currentContributor];
            index++;
        }
        return array;
    }



}