// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {Types} from "src/common/Types.sol";

interface IContributorManager {
    //--------------------------------------------------------------------------
    // Types

    struct Contributor {
        string name;
        string role;
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

    /// @notice The supplied contributors are not consecutive
    error Proposal__ContributorManager__ContributorsNotConsecutive();

    //--------------------------------------------------------------------------
    // Events

    event ContributorAdded(address indexed who);

    event ContributorRemoved(address indexed who);

    event ContributorsRoleUpdated(
        address indexed who, string newRole, string oldRole
    );

    event ContributorsSalaryUpdated(
        address indexed who, uint newSalary, uint oldSalary
    );

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Revokes the caller from being a contributor.
    /// @param prevContrib The previous contributor in the contributor's list.
    function revokeContributor(address prevContrib) external;

    /// @notice Returns whether `who` is a contributor.
    function isContributor(address who) external view returns (bool);

    /// @notice Returns the list of addresses of current contributors.
    function listContributors() external view returns (address[] memory);

    /// @notice Returns the registerted {Contributor} instance for `who`.
    function getContributorInformation(address who)
        external
        view
        returns (Contributor memory);
}
