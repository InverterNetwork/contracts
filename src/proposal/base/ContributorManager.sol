// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Dependencies
import {ContextUpgradeable} from "@oz-up/utils/ContextUpgradeable.sol";
import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";

// Internal Dependencies
import {Types} from "src/common/Types.sol";

// Internal Libraries
import {LibString} from "src/common/LibString.sol";

// Interfaces
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
abstract contract ContributorManager is
    IContributorManager,
    Initializable,
    ContextUpgradeable
{
    using LibString for string;

    //--------------------------------------------------------------------------
    // Modifiers

    modifier __ContributorManager_onlyAuthorized() {
        if (!__ContributorManager_isAuthorized(_msgSender())) {
            revert Proposal__ContributorManager__CallerNotAuthorized();
        }
        _;
    }

    modifier validAddress(address who) {
        // @todo mp: Make gas optimized.
        bool isZero = who == address(0);
        bool isSentinel = who == _SENTINEL;
        bool isThis = who == address(this);

        if (isZero || isSentinel || isThis) {
            revert Proposal__ContributorManager__InvalidContributorAddress();
        }
        _;
    }

    modifier validName(string memory name) {
        if (name.isEmpty()) {
            revert Proposal__ContributorManager__InvalidContributorName();
        }
        _;
    }

    modifier validRole(string memory role) {
        if (role.isEmpty()) {
            revert Proposal__ContributorManager__InvalidContributorRole();
        }
        _;
    }

    modifier validSalary(uint salary) {
        if (salary == 0) {
            revert Proposal__ContributorManager__InvalidContributorSalary();
        }
        _;
    }

    modifier isContributor_(address who) {
        if (!isContributor(who)) {
            revert Proposal__ContributorManager__IsNotContributor();
        }
        _;
    }

    modifier isNotContributor(address who) {
        if (isContributor(who)) {
            revert Proposal__ContributorManager__IsContributor();
        }
        _;
    }

    modifier onlyConsecutiveContributors(address prevContrib, address contrib) {
        if (_contributors[prevContrib] != contrib) {
            revert Proposal__ContributorManager__ContributorsNotConsecutive();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Constants

    address private constant _SENTINEL = address(0x1);

    //--------------------------------------------------------------------------
    // Storage

    mapping(address => Contributor) private _contributorRegistry;

    /// @notice Mapping of contributors.
    ///         TODO: Move this to docs/ and link to it.
    ///         Every address points to the last one added before them.
    ///         _contributors[_SENTINEL] points to the last added address,
    ///         to aid retrieval.
    ///         The first added address points to _SENTINEL to signal end of
    ///         list.
    mapping(address => address) private _contributors;

    uint private _contributorCounter;

    //--------------------------------------------------------------------------
    // Initializer

    function __ContributorManager_init() internal onlyInitializing {
        __Context_init();

        // Set up sentinel to signal empty list of contributors.
        _contributors[_SENTINEL] = _SENTINEL;
    }

    //--------------------------------------------------------------------------
    // Internal Functions Implemented in Downstream Contract

    /// @dev Returns whether address `who` is authorized to mutate contributor
    ///      manager's state.
    /// @dev MUST be overriden in downstream contract.
    function __ContributorManager_isAuthorized(address who)
        internal
        view
        virtual
        returns (bool);

    //--------------------------------------------------------------------------
    // Public View Functions

    /// @inheritdoc IContributorManager
    function getContributorInformation(address who)
        external
        view
        isContributor_(who)
        returns (Contributor memory)
    {
        return _contributorRegistry[who];
    }

    /// @inheritdoc IContributorManager
    function isContributor(address who) public view returns (bool) {
        return who != _SENTINEL && _contributors[who] != address(0);
    }

    /// @inheritdoc IContributorManager
    function listContributors() external view returns (address[] memory) {
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
    // onlyAuthorized Mutating Functions

    /// @inheritdoc IContributorManager
    function addContributor(
        address who,
        string memory name,
        string memory role,
        uint salary
    )
        external
        __ContributorManager_onlyAuthorized
        isNotContributor(who)
        validAddress(who)
        validName(name)
        validRole(role)
        validSalary(salary)
    {
        // Add address to _contributors mapping.
        _contributors[who] = _contributors[_SENTINEL];
        _contributors[_SENTINEL] = who;
        _contributorCounter++;

        // Write new contributor instance to registry.
        _contributorRegistry[who] = Contributor(name, role, salary);

        emit ContributorAdded(who);
    }

    /// @inheritdoc IContributorManager
    function removeContributor(address prevContrib, address who)
        external
        __ContributorManager_onlyAuthorized
        isContributor_(who)
        onlyConsecutiveContributors(prevContrib, who)
    {
        _commitRemoveContributor(prevContrib, who);
    }

    /// @inheritdoc IContributorManager
    function updateContributorsRole(address who, string memory role)
        external
        __ContributorManager_onlyAuthorized
        isContributor_(who)
        validRole(role)
    {
        string memory oldRole = _contributorRegistry[who].role;

        if (!oldRole.equals(role)) {
            emit ContributorsRoleUpdated(who, role, oldRole);
            _contributorRegistry[who].role = role;
        }
    }

    /// @inheritdoc IContributorManager
    function updateContributorsSalary(address who, uint salary)
        external
        __ContributorManager_onlyAuthorized
        isContributor_(who)
        validAddress(who)
        validSalary(salary)
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
        isContributor_(_msgSender())
        onlyConsecutiveContributors(prevContrib, _msgSender())
    {
        _commitRemoveContributor(prevContrib, _msgSender());
    }

    //--------------------------------------------------------------------------
    // Private Functions

    /// @dev Expects address arguments to be consecutive in the contributor
    ///      list.
    /// @dev Expects address `who` to be contributor.
    function _commitRemoveContributor(address prevContrib, address who)
        private
    {
        // Remove contributor instance from registry.
        delete _contributorRegistry[who];

        // Remove contributor address from list and decrease counter.
        _contributors[prevContrib] = _contributors[who];
        delete _contributors[who];
        _contributorCounter--;

        emit ContributorRemoved(who);
    }
}
