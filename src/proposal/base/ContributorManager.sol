// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

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
 *      It saves the assigned role, name, and salary of each contributor in a
 *      registry, and manages a list of contributors in the style of the
 *      Gnosis Safe's [OwnerManager](https://github.com/safe-global/safe-contracts/blob/main/contracts/base/OwnerManager.sol).
 *
 *      Along each contributor address, the contract stores a salary, name, and
 *      role. This role is NOT intended for access control, but for off-chain
 *      retrieval of team assignment or similar information.
 *
 *      Each contributor is only represented once.
 *
 * @author Adapted from Gnosis Safe
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
        if (who == address(0) || who == _SENTINEL || who == address(this)) {
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

    /// @dev Marks the beginning and end of the _modules list.
    address private constant _SENTINEL = address(0x1);

    //--------------------------------------------------------------------------
    // Storage

    /// @dev Registry mapping contributor addresses to Contributor structs.
    mapping(address => Contributor) private _contributorRegistry;

    /// @notice List of contributor addresses.
    mapping(address => address) private _contributors;

    /// @dev Counter for number of contributors in the _contributors list.
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
    function listContributors() public view returns (address[] memory) {
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

    /// @inheritdoc IContributorManager
    function contributorsSize() external view returns (uint) {
        return _contributorCounter;
    }

    /// @inheritdoc IContributorManager
    function getPreviousContributor(address contributor)
        external
        view
        isContributor_(contributor)
        returns (address)
    {
        address previousContributor;
        address[] memory contributors = listContributors();

        uint _length = contributors.length;
        for (uint i; i < _length; i++) {
            if (contributors[i] == contributor) {
                if (i == 0) {
                    previousContributor = _SENTINEL;
                } else {
                    previousContributor = contributors[i - 1];
                    break;
                }
            }
        }
        return previousContributor;
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
    function updateContributor(address who, string memory role, uint salary)
        external
        __ContributorManager_onlyAuthorized
        isContributor_(who)
        validRole(role)
        validSalary(salary)
    {
        string memory oldRole = _contributorRegistry[who].role;
        uint oldSalary = _contributorRegistry[who].salary;

        if (!oldRole.equals(role) || oldSalary != salary) {
            emit ContributorUpdated(who, role, salary);
            _contributorRegistry[who].role = role;
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
