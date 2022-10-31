// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {Types} from "src/common/Types.sol";
import {Module} from "src/modules/base/Module.sol";

// Interfaces
import {IProposal} from "src/proposal/IProposal.sol";

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
 * Along each contributor address, the contract stores a salary and a role. This
 * role is NOT intended for access control, but for offchain retrieval of team
 * assignement or similar information.
 *
 * Each active contributor is only represented once.
 *
 */

contract ContributorManager is Module {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice The supplied contributor address is not valid
    error Module__ContributorManager__invalidContributorAddress();

    /// @notice The supplied contributor details are not valid.
    error Module__ContributorManager__invalidContributorInformation();

    /// @notice The supplied contributor is already active
    error Module__ContributorManager__contributorAlreadyActive();

    /// @notice The supplied contributor is not active
    error Module__ContributorManager__contributorNotActive();

    /// @notice The supplied contributors are not consecutive
    error Module__ContributorManager__ContributorsNotConsecutive();

    //--------------------------------------------------------------------------
    // Events

    event ContributorAdded(address who, bytes32 role, uint salary);

    event ContributorRemoved(address who, bytes32 role, uint salary);

    event ContributorModified(address who, bytes32 role, uint salary);

    //--------------------------------------------------------------------------
    // Modifiers

    modifier validAddress(address _who) {
        //require address is not 0, the sentinel or the module itself
        if (
            _who == address(0) || _who == SENTINEL_CONTRIBUTORS
                || _who == address(this)
        ) {
            revert Module__ContributorManager__invalidContributorAddress();
        }
        _;
    }

    modifier validContributor(bytes32 _role, uint _salary) {
        //require role and salary are not empty
        if (_role == bytes32(0) || _salary == 0) {
            revert Module__ContributorManager__invalidContributorInformation();
        }
        _;
    }

    modifier onlyConsecutiveContributors(address _current, address _prev) {
        //require that the contributors are indeed consecutive
        if (activeContributors[_prev] != _current) {
            revert Module__ContributorManager__ContributorsNotConsecutive();
        }
        _;
    }

    modifier contributorNotActive(address _who) {
        if (isActiveContributor(_who)) {
            revert Module__ContributorManager__contributorAlreadyActive();
        }
        _;
    }

    modifier contributorIsActive(address _who) {
        if (!isActiveContributor(_who)) {
            revert Module__ContributorManager__contributorNotActive();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    /// @notice Struct saving relevant contributor Information
    struct Contributor {
        bytes32 role;
        uint salary;
    }

    mapping(address => Contributor) internal contributorRegistry;

    /// @notice Mapping of active contributors. Every address points to the
    ///         last one added before them.
    ///         activeContributors[SENTINEL_CONTRIBUTORS] points to the last
    ///         added address, to aid retrieval.
    ///         The first added address points to SENTINEL_CONTRIBUTORS to
    //          signal end of list
    mapping(address => address) internal activeContributors;
    address internal constant SENTINEL_CONTRIBUTORS = address(0x1);

    uint internal contributorCount;

    //--------------------------------------------------------------------------
    // Internal Functions

    //--------------------------------------------------------------------------
    // Public Functions

    function initialize(IProposal proposal, Metadata memory metadata)
        external
        initializer
    {
        __Module_init(proposal, metadata);

        // set up the sentinel to signal empty list of active contributors
        activeContributors[SENTINEL_CONTRIBUTORS] = SENTINEL_CONTRIBUTORS;
    }

    /// @notice Registers a new contributor and adds them to the list of active
    ///         contributors.
    /// @param _who :   the contributor to be removed
    /// @param _role:   the role assigned to the contributor
    /// @param _salary: the salary the assigned to the contributor. To be spe-
    ///                 cified in a format already including the decimals of
    ///                 the payout token.
    function __Contributor_addContributor(
        address _who,
        bytes32 _role,
        uint _salary
    )
        external
        onlyProposal
        validAddress(_who)
        validContributor(_role, _salary)
        contributorNotActive(_who)
    {
        //initialize contributorRegistry[address] with contributor
        Contributor memory _contributor;
        _contributor.role = _role;
        _contributor.salary = _salary;

        // add address to activecontributor mapping (gnosis-safe)
        activeContributors[_who] = activeContributors[SENTINEL_CONTRIBUTORS];
        activeContributors[SENTINEL_CONTRIBUTORS] = _who;
        contributorCount++;

        contributorRegistry[_who] = _contributor;
        emit ContributorAdded(_who, _role, _salary);
    }

    /// @notice Registers a new contributor and adds them to the list of active
    ///         contributors.
    /// @dev    Relay Function that routes the function call via the proposal
    /// @param _who :   the contributor to be removed
    /// @param _role:   the role assigned to the contributor
    /// @param _salary: the salary the assigned to the contributor. To be spe-
    ///                 cified in a format already including the decimals of
    ///                 the payout token.
    function addContributor(address _who, bytes32 _role, uint _salary)
        external
        onlyAuthorized
    {
        //@question: I think it's better to make the call idempotent at this level? So if the user wants to add a contributor that exists we just call modify. This allows us to keep stricter checks in the func called by the proposal.

        if (!isActiveContributor(_who)) {
            _triggerProposalCallback(
                abi.encodeWithSignature(
                    "__Contributor_addContributor(address,bytes32,uint)",
                    _who,
                    _role,
                    _salary
                ),
                Types.Operation.Call
            );
        } else {
            _triggerProposalCallback(
                abi.encodeWithSignature(
                    "__Contributor_modifyContributor(address,bytes32,uint)",
                    _who,
                    _role,
                    _salary
                ),
                Types.Operation.Call
            );
        }
    }

    /// @notice Removes a contributor from the registry and from the list of
    ///         active contributors. If the contributor to delete is the first
    ///         on the list, _prevContrib should be address(0x1), the sentinel.
    ///@param _who : the contributor to be removed
    ///@param _prevContrib : the contributor situated previously in the list
    function __Contributor_removeContributor(address _who, address _prevContrib)
        external
        onlyProposal
        validAddress(_who)
        onlyConsecutiveContributors(_who, _prevContrib)
    {
        //remove contributor information from registry
        delete contributorRegistry[_who];

        //remove address from active contributors list
        activeContributors[_prevContrib] = activeContributors[_who];
        activeContributors[_who] = address(0);
        contributorCount--;

        emit ContributorRemoved(
            _who,
            contributorRegistry[_who].role,
            contributorRegistry[_who].salary
            );
    }

    /// @notice Removes a contributor from the registry and from the list of
    ///         active contributors. If the contributor to delete is the first
    ///         on the list, _prevContrib should be address(0x1), the sentinel.
    ///@dev     Relay Function that routes the function call via the proposal
    ///@param _who : the contributor to be removed
    ///@param _prevContrib : the contributor situated previously in the list
    function removeContributor(address _who, address _prevContrib)
        external
        onlyAuthorized
    {
        /// @question   Maybe _prevContrib should be determined internally here
        ///             and then sent in the call? Not for now

        if (isActiveContributor(_who)) {
            _triggerProposalCallback(
                abi.encodeWithSignature(
                    "__Contributor_removeContributor(address,address)",
                    _who,
                    _prevContrib
                ),
                Types.Operation.Call
            );
        }
    }

    /// @notice Modifies an existing contributor.
    /// @param _who :   the contributor to be modified
    /// @param _role:   the new role assigned to the contributor
    /// @param _salary: the new salary the assigned to the contributor. To be
    ///                 specified in a format already including the decimals of
    ///                 the payout token.
    function __Contributor_modifyContributor(
        address _who,
        bytes32 _role,
        uint _salary
    )
        external
        onlyProposal
        validAddress(_who)
        validContributor(_role, _salary)
        contributorIsActive(_who)
    {
        contributorRegistry[_who].role = _role;
        contributorRegistry[_who].salary = _salary;
        emit ContributorModified(_who, _role, _salary);
    }

    /// @notice Modifies an existing contributor.
    /// @dev    Relay Function that routes the function call via the proposal
    /// @param _who :   the contributor to be modified
    /// @param _role:   the new role assigned to the contributor
    /// @param _salary: the new salary the assigned to the contributor. To be
    ///                 specified in a format already including the decimals of
    ///                 the payout token.
    function modifyContributor(address _who, bytes32 _role, uint _salary)
        external
        onlyAuthorized
    {
        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Contributor_modifyContributor(address,bytes32,uint)",
                _who,
                _role,
                _salary
            ),
            Types.Operation.Call
        );
    }

    /// @notice Returns registry information about a specifc contributor
    function getContributorInformation(address _who)
        external
        view
        contributorIsActive(_who)
        returns (bytes32, uint)
    {
        return (
            contributorRegistry[_who].role, contributorRegistry[_who].salary
        );
    }

    /// @notice Returns if a specified contributor is currently active
    function isActiveContributor(address _who) public view returns (bool) {
        return _who != SENTINEL_CONTRIBUTORS
            && activeContributors[_who] != address(0);
    }

    /// @notice Returns an array with the addresses of all active contributors,
    ///         beginning with the last one added to the list and traversing
    ///         it in order.
    function listActiveContributors()
        external
        view
        returns (address[] memory)
    {
        //return all active contributors as an array of addresses (gnosis-safe)
        address[] memory array = new address[](contributorCount);

        // populate return array
        uint index = 0;
        address currentContributor = activeContributors[SENTINEL_CONTRIBUTORS];
        while (currentContributor != SENTINEL_CONTRIBUTORS) {
            array[index] = currentContributor;
            currentContributor = activeContributors[currentContributor];
            index++;
        }
        return array;
    }
}
