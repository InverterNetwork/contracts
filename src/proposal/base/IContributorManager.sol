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
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by authorized address.
    error Proposal__ContributorManager__CallerNotAuthorized();

    /// @notice Given contributor's name invalid.
    error Proposal__ContributorManager__InvalidContributorName();

    /// @notice Given contributor's role invalid.
    error Proposal__ContributorManager__InvalidContributorRole();

    // @todo perform this check on a milestone basis
    /// @notice Given contributor's salary invalid.
    //error Proposal__ContributorManager__InvalidContributorSalary();

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

    /// @notice Event emitted when contributor's role and/or name are updated.
    /// @param who The contributor's address.
    /// @param role The contributor's name.
    /// @param role The contributor's role.
    event ContributorUpdated(address indexed who, string name, string role);

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Adds `who` as new contributor.
    /// @dev Only callable by authorized addresses.
    /// @dev Reverts if an argument invalid.
    /// @param who The contributor's address to add as contributor.
    /// @param name The contributor's name.
    /// @param role The contributor's role.
    function addContributor(address who, string memory name, string memory role)
        external;

    /// @notice Removes `who` from being a contributor.
    /// @dev Only callable by authorized addresses.
    /// @dev Reverts if `who` not a contributor.
    /// @dev Reverts if `prevContrib` not previous element in the contributor's list
    /// @param prevContrib The previous contributor in the contributor's list.
    /// @param who The contributor's address to remove.
    function removeContributor(address prevContrib, address who) external;

    /// @notice Revokes the caller from being a contributor.
    /// @param prevContrib The previous contributor in the contributor's list.
    function revokeContributor(address prevContrib) external;

    /// @notice Updates name or role.
    /// @dev Only callable by authorized addresses.
    /// @dev Reverts if `role` or `name` invalid.
    /// @param who The contributor's address.
    /// @param role The contributor's new role.
    function updateContributor(
        address who,
        string memory name,
        string memory role
    ) external;

    /// @notice Returns whether `who` is a contributor.
    function isContributor(address who) external view returns (bool);

    /// @notice Returns the list of addresses of current contributors.
    function listContributors() external view returns (address[] memory);

    /// @notice Fetches the id of the previous Contributor in the list
    /// @dev Reverts if who is invalid
    /// @dev This should ideally be only used in a frontend context
    ///      because iterating through the list and finding the previous element
    ///      causes an O(n) runtime of the given list and should ideally be outsourced off-chain.
    /// @param who the address of which the previous element in the list should be found.
    /// @return previousContributor The address of the previous Contributor.
    function getPreviousContributor(address who)
        external
        view
        returns (address previousContributor);

    /// @notice Returns the number of contributors.
    function contributorsSize() external view returns (uint);

    /// @notice Returns the registerted {Contributor} instance for `who`.
    function getContributorInformation(address who)
        external
        view
        returns (Contributor memory);
}
