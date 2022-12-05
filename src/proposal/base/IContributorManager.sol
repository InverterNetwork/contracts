// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {Types} from "src/common/Types.sol";

interface IContributorManager {
    //--------------------------------------------------------------------------
    // Types

    struct Contributor {
        /// @dev MUST not be empty.
        string name;
        /// @dev MUST not be empty.
        string role;
        /// @dev MUST not be zero.
        uint salary; // @todo mp, nuggan: What exactly is contributor's salary?
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by authorized address.
    error Proposal__ContributorManager__CallerNotAuthorized();

    /// @notice Given contributor's name invalid.
    error Proposal__ContributorManager__InvalidContributorName();

    /// @notice Given contributor's role invalid.
    error Proposal__ContributorManager__InvalidContributorRole();

    /// @notice Given contributor's salary invalid.
    error Proposal__ContributorManager__InvalidContributorSalary();

    /// @notice Given contributor's address invalid.
    error Proposal__ContributorManager__InvalidContributorAddress();

    /// @notice Given contributor's address is contributor.
    error Proposal__ContributorManager__IsContributor();

    /// @notice Given contributor's address is not contributor.
    error Proposal__ContributorManager__IsNotContributor();

    /// @notice The supplied contributors are not consecutive.
    error Proposal__ContributorManager__ContributorsNotConsecutive();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when new contributor added.
    /// @param who The contributor's address.
    event ContributorAdded(address indexed who);

    /// @notice Event emitted when contributor removed
    /// @param who The contributor's address.
    event ContributorRemoved(address indexed who);

    /// @notice Event emitted when contributor's role and/or salary updated.
    /// @param who The contributor's address.
    /// @param role The contributor's role.
    /// @param salary The contributor's salary.
    event ContributorUpdated(address indexed who, string role, uint salary);

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Adds `who` as new contributor.
    /// @dev Only callable by authorized addresses.
    /// @dev Reverts if an argument invalid.
    /// @dev who The contributor's address to add as contributor.
    /// @dev name The contributor's name.
    /// @dev role The contributor's role.
    /// @dev salary The contributor's salary.
    function addContributor(
        address who,
        string memory name,
        string memory role,
        uint salary
    ) external;

    /// @notice Removes `who` from being a contributor.
    /// @dev Only callable by authorized addresses.
    /// @dev Reverts if `who` not a contributor.
    /// @dev Reverts if `prevContrib` not previous element in the contributor's
    ///      list.
    /// @param prevContrib The previous contributor in the contributor's list.
    /// @dev who The contributor's address to remove.
    function removeContributor(address prevContrib, address who) external;

    /// @notice Revokes the caller from being a contributor.
    /// @param prevContrib The previous contributor in the contributor's list.
    function revokeContributor(address prevContrib) external;

    /// @notice Updates `who` role and/or salary.
    /// @dev Only callable by authorized addresses.
    /// @dev Reverts if `role` or `salary` invalid.
    /// @param who The contributor's address.
    /// @param role The contributor's new role.
    /// @param salary The contributor's new salary.
    function updateContributor(address who, string memory role, uint salary)
        external;

    /// @notice Returns whether `who` is a contributor.
    function isContributor(address who) external view returns (bool);

    /// @notice Returns the list of addresses of current contributors.
    function listContributors() external view returns (address[] memory);

    /// @notice Returns the number of contributors.
    function contributorsSize() external view returns (uint);

    /// @notice Returns the registerted {Contributor} instance for `who`.
    function getContributorInformation(address who)
        external
        view
        returns (Contributor memory);
}
