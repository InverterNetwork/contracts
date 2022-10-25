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

    /// @notice Given contributor's name invalid.
    error Module__ContributorManager__InvalidContributorName();

    /// @notice Given contributor's role invalid.
    error Module__ContributorManager__InvalidContributorRole();

    /// @notice Given contributor's salary invalid.
    error Module__ContributorManager__InvalidContributorSalary();

    /// @notice Given contributor's address invalid.
    error Module__ContributorManager__InvalidContributorAddress();

    /// @notice Given contributor's address is active.
    error Module__ContributorManager__ActiveContributor();

    /// @notice Given contributor's address is not active.
    error Module__ContributorManager_NotActiveContributor();

    /// @notice The supplied contributors are not consecutive
    error Module__ContributorManager__ContributorsNotConsecutive();

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

    /// @notice Returns whether `who` is registered as active contributor.
    function isActiveContributor(address who) external view returns (bool);

    /// @notice Returns the list of addresses of current active contributors.
    function listActiveContributors()
        external
        view
        returns (address[] memory);

    /// @notice Returns the registerted {Contributor} instance for `who`.
    function getContributorInformation(address who)
        external
        view
        returns (Contributor memory);
}
