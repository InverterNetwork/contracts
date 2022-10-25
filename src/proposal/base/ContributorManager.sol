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
contract ContributorManager is IContributorManager, Initializable {
    using LibString for string;
    // @todo mp: Should be abstract?

    //--------------------------------------------------------------------------
    // Modifiers

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

    modifier _isActiveContributor(address who) {
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
    ///         activeContributors[SENTINEL_CONTRIBUTORS] points to the last
    ///         added address, to aid retrieval.
    ///         The first added address points to SENTINEL_CONTRIBUTORS to
    //          signal end of list
    mapping(address => address) private _contributors;

    uint private _contributorCounter;

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IContributorManager
    function revokeContributor(address prevContrib) external {
        __Contributor_revokeContributor(prevContrib);
    }

    //--------------------------------------------------------------------------
    // Internal Mutating Functions

    // @todo mp, nuggan: Decide which functions should be public.

    function __ContributorManager_init() internal onlyInitializing {
        // Set up the sentinel to signal an empty list of active contributors.
        _contributors[_SENTINEL] = _SENTINEL;
    }

    function __ContributorManager_addContributor(
        address who,
        string memory name,
        string memory role,
        uint salary
    )
        internal
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

    function __ContributorManager_removeContributor(
        address who,
        address prevContrib
    )
        internal
        _isActiveContributor(who)
        onlyConsecutiveContributors(who, prevContrib)
    {
        _commitContributorRemoval(who, prevContrib);
    }

    function __Contributor_revokeContributor(address prevContrib)
        internal
        _isActiveContributor(msg.sender)
        onlyConsecutiveContributors(msg.sender, prevContrib)
    {
        _commitContributorRemoval(msg.sender, prevContrib);
    }

    function __ContributorManager_updateContributorsRole(
        address who,
        string memory role
    ) internal validAddress(who) validRole(role) _isActiveContributor(who) {
        string memory oldRole = _contributorRegistry[who].role;

        if (!oldRole.equals(role)) {
            emit ContributorsRoleUpdated(who, role, oldRole);
            _contributorRegistry[who].role = role;
        }
    }

    function __ContributorManager_updateContributorsSalary(
        address who,
        uint salary
    )
        internal
        validAddress(who)
        validSalary(salary)
        _isActiveContributor(who)
    {
        uint oldSalary = _contributorRegistry[who].salary;

        if (oldSalary != salary) {
            emit ContributorsSalaryUpdated(who, salary, oldSalary);
            _contributorRegistry[who].salary = salary;
        }
    }

    //--------------------------------------------------------------------------
    // Private Mutating Functions

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

    //--------------------------------------------------------------------------
    // Public View Functions

    /// @inheritdoc IContributorManager
    function getContributorInformation(address who)
        external
        view
        _isActiveContributor(who)
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
}
