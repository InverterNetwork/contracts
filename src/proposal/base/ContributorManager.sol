// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Dependencies
import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";

// Internal Dependencies
import {Types} from "src/common/Types.sol";
import {Module} from "src/modules/base/Module.sol";

// Internal Libraries
import {LibString} from "src/common/LibString.sol";

// Interfaces
import {IProposal} from "src/proposal/IProposal.sol";
import {IContributorManager} from "src/proposal/base/IContributorManager.sol";

/**
 * @title Contributor Manager
 *
 * @dev A contract to manage a list of contributors.
 *
 *      It saves the assigned role and salary of each contributor in a registry,
 *      and keeps a list of active contributors in the style of the Gnosis Safe
 *      OwnerManager (https://github.com/safe-global/safe-contracts/blob/main/contracts/base/OwnerManager.sol)
 *
 *      Along each contributor address, the contract stores a salary and a role.
 *      This role is NOT intended for access control, but for offchain
 *      retrieval of team assignment or similar information.
 *
 *      Each active contributor is only represented once.
 *
 * @author byterocket
 */
abstract contract ContributorManager is IContributorManager, Initializable {
    using LibString for string;

    //--------------------------------------------------------------------------
    // Modifiers

    modifier onlyAuthorized() {
        if (!__ContributorManager_isAuthorized(msg.sender)) {
            revert("Not authorized");
        }
        _;
    }

    modifier validName(string memory name) {
        if (name.isEmpty()) {
            revert Module__ContributorManager__InvalidContributorName();
        }
        _;
    }

    modifier validRole(string memory role) {
        if (role.isEmpty()) {
            revert Module__ContributorManager__InvalidContributorRole();
        }
        _;
    }

    modifier validSalary(uint salary) {
        if (salary == 0) {
            revert Module__ContributorManager__InvalidContributorSalary();
        }
        _;
    }

    modifier validAddress(address who) {
        // @todo mp: Make gas optimized.
        bool isZero = who == address(0);
        bool isSentinel = who == _SENTINEL;
        bool isThis = who == address(this);

        if (isZero || isSentinel || isThis) {
            revert Module__ContributorManager__InvalidContributorAddress();
        }
        _;
    }

    modifier isNotActiveContributor(address who) {
        if (isActiveContributor(who)) {
            revert Module__ContributorManager__ActiveContributor();
        }
        _;
    }

    modifier isActiveContributor_(address who) {
        if (!isActiveContributor(who)) {
            revert Module__ContributorManager_NotActiveContributor();
        }
        _;
    }

    modifier onlyConsecutiveContributors(address _current, address _prev) {
        //require that the contributors are indeed consecutive
        if (_contributors[_prev] != _current) {
            revert Module__ContributorManager__ContributorsNotConsecutive();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Constants

    address private constant _SENTINEL = address(0x1);

    //--------------------------------------------------------------------------
    // Storage

    mapping(address => Contributor) private _contributorRegistry;

    /// @notice Mapping of active contributors. Every address points to the
    ///         last one added before them.
    ///         _contributors[_SENTINEL] points to the last added address,
    ///         to aid retrieval.
    ///         The first added address points to _SENTINEL to signal end of
    ///         list.
    mapping(address => address) private _contributors;

    uint private _contributorCounter;

    //--------------------------------------------------------------------------
    // Initializer

    function __ContributorManager_init() internal onlyInitializing {
        // Set up the sentinel to signal an empty list of active contributors.
        _contributors[_SENTINEL] = _SENTINEL;
    }

    //--------------------------------------------------------------------------
    // Internal Functions Implemented in Downstream Contract

    /// @dev Returns whether address `who` is authorized to mutate contributor
    ///      manager's state.
    /// @dev MUST be overriden by downstream contract.
    function __ContributorManager_isAuthorized(address who)
        internal
        virtual
        returns (bool);

    //--------------------------------------------------------------------------
    // onlyAuthorized Mutating Functions

    function addContributor(
        address who,
        string memory name,
        string memory role,
        uint salary
    )
        internal
        onlyAuthorized
        validAddress(who)
        validName(name)
        validRole(role)
        validSalary(salary)
        isNotActiveContributor(who)
    {
        // Create new Contributor instance.
        Contributor memory c = Contributor(name, role, salary);

        // Add address to _contributors mapping.
        _contributors[who] = _contributors[_SENTINEL];
        _contributors[_SENTINEL] = who;
        _contributorCounter++;

        // Add Contributor instance to registry.
        _contributorRegistry[who] = c;

        emit ContributorAdded(who);
    }

    function removeContributor(address who, address prevContrib)
        internal
        onlyAuthorized
        isActiveContributor_(who)
        onlyConsecutiveContributors(who, prevContrib)
    {
        _commitContributorRemoval(who, prevContrib);
    }

    function updateContributorsRole(address who, string memory role)
        internal
        onlyAuthorized
        validAddress(who)
        validRole(role)
        isActiveContributor_(who)
    {
        string memory oldRole = _contributorRegistry[who].role;

        if (!oldRole.equals(role)) {
            emit ContributorsRoleUpdated(who, role, oldRole);
            _contributorRegistry[who].role = role;
        }
    }

    function updateContributorsSalary(address who, uint salary)
        internal
        onlyAuthorized
        validAddress(who)
        validSalary(salary)
        isActiveContributor_(who)
    {
        uint oldSalary = _contributorRegistry[who].salary;

        if (oldSalary != salary) {
            emit ContributorsSalaryUpdated(who, salary, oldSalary);
            _contributorRegistry[who].salary = salary;
        }
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IContributorManager
    function revokeContributor(address prevContrib)
        external
        isActiveContributor_(msg.sender)
        onlyConsecutiveContributors(msg.sender, prevContrib)
    {
        _commitContributorRemoval(msg.sender, prevContrib);
    }

    //--------------------------------------------------------------------------
    // Public View Functions

    /// @inheritdoc IContributorManager
    function getContributorInformation(address who)
        external
        view
        isActiveContributor_(who)
        returns (Contributor memory)
    {
        return _contributorRegistry[who];
    }

    /// @inheritdoc IContributorManager
    function isActiveContributor(address who) public view returns (bool) {
        return who != _SENTINEL && _contributors[who] != address(0);
    }

    /// @inheritdoc IContributorManager
    function listActiveContributors()
        external
        view
        returns (address[] memory)
    {
        address[] memory result = new address[](_contributorCounter);

        // Populate result array.
        uint index = 0;
        address elem = _contributors[_SENTINEL];
        while (elem != _SENTINEL) {
            result[index] = elem;
            elem = _contributors[elem];
            index++;
        }

        return result;
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @dev Expects address arguments to be consecutive in the contributor
    ///      list.
    /// @dev Expects address `who` to be active contributor.
    function _commitContributorRemoval(address who, address prevContrib)
        private
    {
        // Remove Contributor instance from registry.
        delete _contributorRegistry[who];

        // Remove address from active contributors list.
        _contributors[prevContrib] = _contributors[who];
        _contributors[who] = address(0);
        _contributorCounter--;

        emit ContributorRemoved(who);
    }

}
