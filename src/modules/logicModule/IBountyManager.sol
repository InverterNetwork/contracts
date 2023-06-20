// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IPaymentClient} from "src/modules/base/mixins/IPaymentClient.sol";

interface IBountyManager is IPaymentClient {
    //--------------------------------------------------------------------------
    // Types

    struct Bounty {
        /// @dev Minimum amount of tokens that can be paid out upon fulfillment of the bounty
        uint minimumPayoutAmount;
        /// @dev Maximum amount of tokens that can be paid out upon fulfillment of the bounty
        uint maximumPayoutAmount;
        /// @dev Arbitrary data to store Bounty details if necessary.
        ///      CAN be empty.
        bytes details;
        /// @dev Id that claimed the bounty
        ///      A Bounty is claimed if a Claim got acknowledged by a Verifier
        uint claimedBy;
    }

    struct Claim {
        uint bountyId;
        /// @dev The contributors of the claim
        ///      MUST not be empty
        Contributor[] contributors;
        /// @dev Arbitrary data to store Claim details if necessary.
        ///      CAN be empty.
        bytes details;
    }

    struct Contributor {
        /// @dev The contributor's address.
        address addr;
        /// @dev The reward for claiming the bounty.
        ///      That is the number of tokens payed to contributor when the
        ///      bounty is acknowledged.
        uint bountyAmount;
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Given payoutAmounts are either zero or maximumPayoutAmount is smaller than minimumPayoutAmount
    error Module__BountyManager__InvalidPayoutAmounts();

    /// @notice Given Bounty id is not existing
    error Module__BountyManager__InvalidBountyId();

    /// @notice Given Claim id is not existing
    error Module__BountyManager__InvalidClaimId();

    /// @notice Given Contributors are either empty or their bountyAmount is zero
    error Module__BountyManager__InvalidContributors();

    /// @notice Claim is not trying to claim given bounty
    error Module__BountyManager__NotAccordingClaimToBounty();

    /// @notice Given Bounty id is already verified
    error Module__BountyManager__BountyAlreadyVerified();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new Bounty is added.
    event BountyAdded(
        uint indexed bountyId,
        uint indexed minimumPayoutAmount,
        uint indexed maximumPayoutAmount,
        bytes details
    );

    /// @notice Event emitted when a Bounty got updated.
    event BountyUpdated(
        uint indexed bountyId,
        uint indexed minimumPayoutAmount,
        uint indexed maximumPayoutAmount,
        bytes details
    );

    /// @notice Event emitted when a new Claim is added.
    event ClaimAdded(
        uint indexed claimId,
        uint indexed bountyId,
        Contributor[] indexed contributors,
        bytes details
    );

    /// @notice Event emitted when a Claim got updated.
    event ClaimUpdated(
        uint indexed claimId,
        uint indexed bountyId,
        Contributor[] indexed contributors,
        bytes details
    );

    /// @notice Event emitted when a Claim is verified.
    event ClaimVerified(uint indexed BountyId, uint indexed ClaimId);

    //--------------------------------------------------------------------------
    // Functions

    //----------------------------------
    // Bounty View Functions

    /// @notice Returns the Bounty instance with id `id`.
    /// @param bountyId The id of the Bounty to return.
    /// @return Bounty with id `id`.
    function getBountyInformation(uint bountyId)
        external
        view
        returns (Bounty memory);

    /// @notice Returns total list of Bounty ids.
    /// @dev List is in ascending order.
    /// @return List of Bounty ids.
    function listBountyIds() external view returns (uint[] memory);

    /// @notice Returns whether Bounty with id `id` exists.
    /// @param bountyId The id of the Bounty to test.
    /// @return True if Claim with id `id` exists, false otherwise.
    function isExistingBountyId(uint bountyId) external view returns (bool);

    /// @notice Returns the Claim instance with id `id`.
    /// @param claimId The id of the Claim to return.
    /// @return Claim with id `id`.
    function getClaimInformation(uint claimId)
        external
        view
        returns (Claim memory);

    /// @notice Returns total list of Claim ids.
    /// @dev List is in ascending order.
    /// @return List of Claim ids.
    function listClaimIds() external view returns (uint[] memory);

    /// @notice Returns whether Claim with id `id` exists.
    /// @param claimId The id of the Bounty to test.
    /// @return True if Claim with id `id` exists, false otherwise.
    function isExistingClaimId(uint claimId) external view returns (bool);

    /// @notice Returns a list of Claim ids in which contributor Address is used.
    /// @dev List is in ascending order.
    /// @dev Returns an empty .
    /// @param contributorAddrs claim ids are filtered by the contributor address
    /// @return List of Claim ids.
    function listClaimIdsForContributorAddress(address contributorAddrs)
        external
        view
        returns (uint[] memory);

    //----------------------------------
    // Bounty Mutating Functions

    /// @notice Adds a new Bounty.
    /// @dev Reverts if an argument invalid.
    /// @param minimumPayoutAmount The minimum amount of tokens the Bounty will pay out upon being claimed
    /// @param maximumPayoutAmount The maximum amount of tokens the Bounty will pay out upon being claimed
    /// @param details The Bounty's details.
    /// @return The newly added Bounty's id.
    function addBounty(
        uint minimumPayoutAmount,
        uint maximumPayoutAmount,
        bytes calldata details
    ) external returns (uint);

    /// @notice Updates a Bounty's informations.
    /// @dev Reverts if an argument invalid.
    /// @param bountyId The id of the Bounty that will be updated.
    /// @param minimumPayoutAmount The minimum amount of tokens the Bounty will pay out upon being claimed
    /// @param maximumPayoutAmount The maximum amount of tokens the Bounty will pay out upon being claimed
    /// @param details The Bounty's details.
    function updateBounty(
        uint bountyId,
        uint minimumPayoutAmount,
        uint maximumPayoutAmount,
        bytes calldata details
    ) external;

    /// @notice Adds a new Claim.
    /// @dev Reverts if an argument invalid.
    /// @param contributors The contributor information for the Claim
    /// @param details The Claim's details.
    /// @return The newly added Claim's id.
    function addClaim(
        uint bountyId,
        Contributor[] calldata contributors,
        bytes calldata details
    ) external returns (uint);

    /// @notice Updates a Claim's informations.
    /// @dev Reverts if an argument invalid.
    /// @param claimId The id of the Claim that will be updated.
    /// @param bountyId The id of the bounty the Claim wants to claim.
    /// @param contributors The contributor information for the Claim
    /// @param details The Claim's details.
    function updateClaim( //@todo because this might change the contributors list ill have to take another look at -> contributorAddressToClaimIds
        uint claimId,
        uint bountyId,
        Contributor[] calldata contributors,
        bytes calldata details
    ) external;

    /// @notice Completes a Bounty by verifying a claim.
    /// @dev Only callable by authorized addresses.
    /// @dev Reverts if id invalid.
    /// @param claimId The id of the Claim that wants to claim the Bounty.
    /// @param bountyId The id of the Bounty that will be claimed.
    function verifyClaim(uint claimId, uint bountyId) external;
}
