// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IPaymentClient} from "src/modules/base/mixins/IPaymentClient.sol";

interface IBountyManager is IPaymentClient {
    //--------------------------------------------------------------------------
    // Types

    struct Bounty {
        /// @dev The contributors for the Bounty
        ///      MUST not be empty
        ///      All contributors.salary MUST add up to 100_000_000 (100%)
        Contributor[] contributors;
        /// @dev Arbitrary data to store Bounty details if necessary.
        ///      CAN be empty.
        bytes details;
        /// @dev Whether the Bounty is completed.
        ///      A Bounty is completed if it got acknowledged by a Verifier
        bool completed;
    }

    struct Contributor {
        /// @dev The contributor's address.
        ///      MUST not be empty.
        address addr;
        /// @dev The reward for claiming the bounty.
        ///      That is the number of tokens payed to contributor when the
        ///      bounty is acknowledged.
        uint bountyAmount;
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by contributor.
    error Module__BountyManager__();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new Bounty added.
    event BountyAdded(
        uint indexed id,
        Contributor[] indexed contributors,
        bytes indexed details
    );

    /// @notice Event emitted when a Bounty got updated.
    event BountyUpdated(
        uint indexed id,
        Contributor[] indexed contributors,
        bytes indexed details
    );

    /// @notice Event emitted when a Bounty is removed.
    event BountyRemoved(uint indexed id);

    /// @notice Event emitted when a Bounty is verified.
    event BountyVerified(uint indexed id);

    //--------------------------------------------------------------------------
    // Functions

    //----------------------------------
    // Bounty View Functions

    /// @notice Returns the Bounty instance with id `id`.
    /// @dev Returns empty Bounty in case id `id` is invalid.
    /// @param id The id of the Bounty to return.
    /// @return Bounty with id `id`.
    function getBountyInformation(uint id)
        external
        view
        returns (Bounty memory);

    /// @notice Returns total list of Bounty ids.
    /// @dev List is in ascending order.
    /// @return List of Bounty ids.
    function listBountyIds() external view returns (uint[] memory);

    /// @notice Fetches the id of the previous Bounty in the list
    /// @dev Reverts if id invalid
    /// @dev This should ideally be only used in a frontend context
    ///      because iterating through the list and finding the previous element
    ///      causes an O(n) runtime of the given list and should ideally be outsourced off-chain.
    /// @param id the id of which the previous element in the list should be found.
    /// @return prevId The id of the previous Bounty.
    function getPreviousBountyId(uint id) external view returns (uint prevId);

    /// @notice Returns whether Bounty with id `id` exists.
    /// @return True if milestone with id `id` exists, false otherwise.
    function isExistingBountyId(uint id) external view returns (bool);

    //----------------------------------
    // Bounty Mutating Functions

    /// @notice Adds a new Bounty.
    /// @dev Reverts if an argument invalid.
    /// @param contributors The contributor information for the Bounty
    /// @param details The Bounty's details.
    /// @return The newly added Bounty's id.
    function addBounty(
        Contributor[] calldata contributors,
        bytes calldata details
    ) external returns (uint);

    /// @notice Updates a Bounty's informations.
    /// @dev Reverts if an argument invalid.
    /// @param id The Bounty's id.
    /// @param contributors The contributor information for the Bounty
    /// @param details The Bounty's details.
    function updateMilestone(
        uint id,
        Contributor[] calldata contributors,
        bytes calldata details
    ) external;

    /// @notice Completes a Bounty.
    /// @dev Only callable by authorized addresses.
    /// @dev Reverts if id invalid.
    /// @param id The Bounty's id.
    function verifyBounty(uint id) external;
}
