// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";

interface ILM_PC_Bounties_v2 is IERC20PaymentClientBase_v2 {
    //--------------------------------------------------------------------------
    // Structs

    /// @notice Struct used to store information about a bounty.
    /// @param  minimumPayoutAmount Minimum amount of tokens that can be paid out upon fulfillment of the bounty.
    /// @param  maximumPayoutAmount Maximum amount of tokens that can be paid out upon fulfillment of the bounty.
    /// @param  details Arbitrary data to store Bounty details if necessary. CAN be empty.
    /// @param  locked If locked, the Bounty is no longer available for a claim.
    struct Bounty {
        uint minimumPayoutAmount;
        uint maximumPayoutAmount;
        bytes details;
        bool locked;
    }

    /// @notice Struct used to store information about a Bounty contributor.
    /// @param  addr The contributor's address.
    /// @param  claimAmount The amount of tokens the Contributor gets upon claiming the bounty.
    struct Contributor {
        address addr;
        uint claimAmount;
    }

    /// @notice Struct used to store information about a Bounty Claim.
    /// @param  bountyId The id of the bounty this claim belongs to.
    /// @param  contributors The contributors of the claim. MUST not be empty.
    /// @param  details Arbitrary data to store Claim details if necessary. CAN be empty.
    /// @param  claimed Whether this Claim claimed its bounty already.
    struct Claim {
        uint bountyId;
        Contributor[] contributors;
        bytes details;
        bool claimed;
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Access only to addresses that are listed as contributors in the according claim.
    error Module__LM_PC_Bounty__OnlyClaimContributor();

    /// @notice Given payoutAmounts are either zero or maximumPayoutAmount is smaller than minimumPayoutAmount.
    error Module__LM_PC_Bounty__InvalidPayoutAmounts();

    /// @notice Given array lengths are invalid.
    error Module__LM_PC_Bounty__InvalidArrayLengths();

    /// @notice Given Bounty id is not existing.
    error Module__LM_PC_Bounty__InvalidBountyId();

    /// @notice Given Claim id is not existing.
    error Module__LM_PC_Bounty__InvalidClaimId();

    /// @notice Given Contributors list is empty.
    error Module__LM_PC_Bounty__InvalidContributorsLength();

    /// @notice Given claim Amount for contributor is zero.
    error Module__LM_PC_Bounty__InvalidContributorAmount();

    /// @notice Given Contributor address is invalid.
    error Module__LM_PC_Bounty__InvalidContributorAddress();

    /// @notice Given total claims of contributors exceed or are below the given payout amounts of the bounty.
    error Module__LM_PC_Bounty__ClaimExceedsGivenPayoutAmounts();

    /// @notice Given Bounty id is Locked.
    error Module__LM_PC_Bounty__BountyLocked();

    /// @notice Given Claim id got already claimed.
    error Module__LM_PC_Bounty__AlreadyClaimed();

    /// @notice The given Contributors are not the same as in the claim. This might be connected to a tried front
    ///         run of the given transaction.
    error Module__LM_PC_Bounty__ContributorsChanged();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new Bounty is added.
    /// @param  bountyId The id of the newly added Bounty.
    /// @param  minimumPayoutAmount The minimum amount of tokens the Bounty will pay out upon being claimed.
    /// @param  maximumPayoutAmount The maximum amount of tokens the Bounty will pay out upon being claimed.
    /// @param  details The Bounty's details.
    event BountyAdded(
        uint indexed bountyId,
        uint minimumPayoutAmount,
        uint maximumPayoutAmount,
        bytes details
    );

    /// @notice Event emitted when a Bounty got updated.
    /// @param  bountyId The id of the updated Bounty.
    /// @param  details The Bounty's details.
    event BountyUpdated(uint indexed bountyId, bytes details);

    /// @notice Event emitted when a Bounty gets locked.
    /// @param  bountyId The id of the locked Bounty.
    event BountyLocked(uint indexed bountyId);

    /// @notice Event emitted when a new Claim is added.
    /// @param  claimId The id of the newly added Claim.
    /// @param  bountyId The id of the Bounty that got claimed.
    /// @param  contributors The contributor information for the Claim.
    /// @param  details The Claim's details.
    event ClaimAdded(
        uint indexed claimId,
        uint indexed bountyId,
        Contributor[] contributors,
        bytes details
    );

    /// @notice Event emitted when Claim Contributors got updated.
    /// @param  claimId The id of the Claim that got updated.
    /// @param  contributors The contributor information for the Claim.
    event ClaimContributorsUpdated(
        uint indexed claimId, Contributor[] contributors
    );

    /// @notice Event emitted when Claim Details got updated.
    /// @param  claimId The id of the Claim that got updated.
    /// @param  details The Claim's details.
    event ClaimDetailsUpdated(uint indexed claimId, bytes details);

    /// @notice Event emitted when a Claim is verified.
    /// @param  claimId The id of the Claim that got verified.
    event ClaimVerified(uint indexed claimId);

    //--------------------------------------------------------------------------
    // Functions

    //----------------------------------
    // Bounty View Functions

    /// @notice Returns the Bounty instance with id `id`.
    /// @param  bountyId The id of the Bounty to return.
    /// @return Bounty with id `id`.
    function getBountyInformation(uint bountyId)
        external
        view
        returns (Bounty memory);

    /// @notice Returns total list of Bounty ids.
    /// @dev	List is in ascending order.
    /// @return List of Bounty ids.
    function listBountyIds() external view returns (uint[] memory);

    /// @notice Returns whether Bounty with id `id` exists.
    /// @param  bountyId The id of the Bounty to test.
    /// @return True if Claim with id `id` exists, false otherwise.
    function isExistingBountyId(uint bountyId) external view returns (bool);

    /// @notice Returns the Claim instance with id `id`.
    /// @param  claimId The id of the Claim to return.
    /// @return Claim with id `id`.
    function getClaimInformation(uint claimId)
        external
        view
        returns (Claim memory);

    /// @notice Returns total list of Claim ids.
    /// @dev	List is in ascending order.
    /// @return List of Claim ids.
    function listClaimIds() external view returns (uint[] memory);

    /// @notice Returns whether Claim with id `id` exists.
    /// @param  claimId The id of the Bounty to test.
    /// @return True if Claim with id `id` exists, false otherwise.
    function isExistingClaimId(uint claimId) external view returns (bool);

    /// @notice Returns a list of Claim ids in which contributor Address is used.
    /// @dev	List is in ascending order.
    /// @dev	Returns an empty .
    /// @param  contributorAddrs claim ids are filtered by the contributor address.
    /// @return List of Claim ids.
    function listClaimIdsForContributorAddress(address contributorAddrs)
        external
        view
        returns (uint[] memory);

    //----------------------------------
    // Bounty Mutating Functions

    /// @notice Adds a new Bounty.
    /// @dev	Reverts if an argument invalid.
    /// @param  minimumPayoutAmount The minimum amount of tokens the Bounty will pay out upon being claimed.
    /// @param  maximumPayoutAmount The maximum amount of tokens the Bounty will pay out upon being claimed.
    /// @param  details The Bounty's details.
    /// @return The newly added Bounty id.
    function addBounty(
        uint minimumPayoutAmount,
        uint maximumPayoutAmount,
        bytes calldata details
    ) external returns (uint);

    /// @notice Adds a new array of Bounties.
    /// @dev    Reverts if an argument invalid.
    /// @param  minimumPayoutAmounts The array of minimum amount of tokens the Bounty will pay out upon being claimed
    /// @param  maximumPayoutAmounts The array of maximum amount of tokens the Bounty will pay out upon being claimed
    /// @param  detailArray The array of Bounty's details.
    /// @return ids The newly added array of Bounty ids.
    function addBountyBatch(
        uint[] calldata minimumPayoutAmounts,
        uint[] calldata maximumPayoutAmounts,
        bytes[] calldata detailArray
    ) external returns (uint[] memory ids);

    /// @notice Updates a Bounty's informations.
    /// @dev	Reverts if an argument invalid.
    /// @param  bountyId The id of the Bounty that will be updated.
    /// @param  details The Bounty's details.
    function updateBounty(uint bountyId, bytes calldata details) external;

    /// @notice Locks the Bounty so it cant be claimed.
    /// @dev	Only callable by authorized addresses.
    /// @dev	Reverts if id invalid.
    /// @param  bountyId The id of the Bounty that will be locked.
    function lockBounty(uint bountyId) external;

    /// @notice Adds a new Claim.
    /// @dev	Reverts if an argument invalid.
    /// @param  bountyId The id of the bounty this claim belongs to.
    /// @param  contributors The contributor information for the Claim.
    /// @param  details The Claim's details.
    /// @return The newly added Claim's id.
    function addClaim(
        uint bountyId,
        Contributor[] calldata contributors,
        bytes calldata details
    ) external returns (uint);

    /// @notice Updates a Claim's contributor informations.
    /// @dev	Reverts if an argument invalid.
    /// @param  claimId The id of the Claim that will be updated.
    /// @param  contributors The contributor information for the Claim.
    function updateClaimContributors(
        uint claimId,
        Contributor[] calldata contributors
    ) external;

    /// @notice Updates a Claim Details.
    /// @param  claimId The id of the Claim that will be updated.
    /// @param  details The Claim's details.
    function updateClaimDetails(uint claimId, bytes calldata details)
        external;

    /// @notice Completes a Bounty by verifying a claim.
    /// @dev	Only callable by authorized addresses.
    /// @dev	Reverts if id invalid.
    /// @dev	contributors should be copied out of the given Claim. The parameter is used to prevent front running.
    /// @param  claimId The id of the Claim that wants to claim the Bounty.
    /// @param  contributors The contributor information for the Claim.
    function verifyClaim(uint claimId, Contributor[] calldata contributors)
        external;
}
