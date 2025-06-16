// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";

interface ILM_PC_FundingPot_v1 is IERC20PaymentClientBase_v2 {
    // --------------------------------------------------------------------------
    // Structs

    /// @notice Struct used to store information about a funding round.
    /// @param  roundStart Timestamp indicating when the round starts.
    /// @param  roundEnd Timestamp indicating when the round ends. If set to `0`, the round operates only based on `roundCap`.
    /// @param  roundCap Maximum contribution cap in collateral tokens. If set to `0`, the round operates only based on `roundEnd`.
    /// @param  hookContract Address of an optional hook contract to be called after round closure.
    /// @param  hookFunction Encoded function call to be executed on the `hookContract` after round closure.
    /// @param  autoClosure Indicates whether the hook closure coincides with the contribution span end.
    /// @param  accumulationMode Defines how caps accumulate across rounds (see AccumulationMode enum).
    /// @param  accessCriterias Mapping of access criteria IDs to their respective access criteria.
    struct Round {
        uint roundStart;
        uint roundEnd;
        uint roundCap;
        address hookContract;
        bytes hookFunction;
        bool autoClosure;
        AccumulationMode accumulationMode;
        mapping(uint32 id => AccessCriteria) accessCriterias;
    }

    /// @notice Struct used to store information about a funding round's access criteria.
    /// @param  accessCriteriaType Type of access criteria.
    /// @param  nftContract Address of the NFT contract.
    /// @param  merkleRoot Merkle root for the access criteria.
    /// @param  allowedAddresses Mapping of addresses to their access status.
    struct AccessCriteria {
        AccessCriteriaType accessCriteriaType;
        address nftContract; // NFT contract address (0x0 if unused)
        bytes32 merkleRoot; // Merkle root (0x0 if unused)
        mapping(address user => bool isAllowed) allowedAddresses; // Mapping of allowed addresses
    }

    /// @notice Struct used to store information about a funding round's access criteria privileges.
    /// @param  personalCap Personal cap for the access criteria.
    /// @param  overrideContributionSpan Whether to override the round contribution span.
    /// @param  start The start timestamp for for when the linear vesting starts.
    /// @param  cliff The time in seconds from start time at which the unlock starts.
    /// @param  end The end timestamp for when the linear vesting ends.
    struct AccessCriteriaPrivileges {
        uint personalCap;
        bool overrideContributionSpan;
        uint start;
        uint cliff;
        uint end;
    }

    /// @notice Struct used to specify previous round's access criteria for carry-over capacity.
    /// @param roundId The ID of the previous round.
    /// @param accessCriteriaId The ID of the access criteria in that round.
    /// @param merkleProof The Merkle proof needed to validate eligibility (if needed).
    struct UnspentPersonalRoundCap {
        uint32 roundId;
        uint8 accessCriteriaId;
        bytes32[] merkleProof;
    }

    /// @notice Struct to represent a user's complete eligibility information for a round.
    /// @param  isEligible Whether the user is eligible for the round through any criteria.
    /// @param  isNftHolder Whether the user is eligible through NFT holding.
    /// @param  isInMerkleTree Whether the user is eligible through Merkle proof.
    /// @param  isInAllowlist Whether the user is eligible through allowlist.
    /// @param  highestPersonalCap The highest personal cap the user can access.
    /// @param  canOverrideContributionSpan Whether the user has any criteria that can override contribution span.
    struct RoundUserEligibility {
        bool isEligible;
        bool isNftHolder;
        bool isInMerkleTree;
        bool isInAllowlist;
        uint highestPersonalCap;
        bool canOverrideContributionSpan;
    }

    // -------------------------------------------------------------------------
    // Enums

    /// @notice Enum used to identify the type of access criteria.
    enum AccessCriteriaType {
        UNSET, // 0
        OPEN, // 1
        NFT, // 2
        MERKLE, // 3
        LIST // 4

    }

    /// @notice Enum used to define how caps accumulate across rounds.
    /// @dev    Determines whether unused personal caps or round caps from previous
    ///         rounds can affect the limits of the current round.
    enum AccumulationMode {
        Disabled, // 0 - No accumulation. Personal and round caps are isolated to this round.
        Personal, // 1 - Only personal caps roll over from previous compatible rounds. Round cap is isolated.
        Total, // 2 - Only total round caps expand based on previous compatible rounds' undersubscription. Personal caps are isolated.
        All // 3 - Both personal caps roll over and total round caps expand based on previous compatible rounds.

    }

    // -------------------------------------------------------------------------
    // Events

    /// @notice Emitted when a new round is created.
    /// @dev    This event signals the creation of a new round with specific parameters.
    /// @param  roundId_ The unique identifier for the round.
    /// @param  roundStart_ The timestamp when the round starts.
    /// @param  roundEnd_ The timestamp when the round ends.
    /// @param  roundCap_ The maximum allocation or cap for the round.
    /// @param  hookContract_ The address of an optional hook contract for custom logic.
    /// @param  hookFunction_ The encoded function call for the hook.
    /// @param  autoClosure_ A boolean indicating whether a specific closure mechanism is enabled.
    /// @param  accumulationMode_ Defines how caps accumulate across rounds (see AccumulationMode enum).
    event RoundCreated(
        uint indexed roundId_,
        uint roundStart_,
        uint roundEnd_,
        uint roundCap_,
        address hookContract_,
        bytes hookFunction_,
        bool autoClosure_,
        AccumulationMode accumulationMode_
    );

    /// @notice Emitted when an existing round is edited.
    /// @dev    This event signals modifications to an existing round's parameters.
    /// @param  roundId_ The unique identifier of the round being edited.
    /// @param  roundStart_ The updated timestamp for when the round starts.
    /// @param  roundEnd_ The updated timestamp for when the round ends.
    /// @param  roundCap_ The updated maximum allocation or cap for the round.
    /// @param  hookContract_ The address of an optional hook contract for custom logic.
    /// @param  hookFunction_ The updated encoded function call for the hook.
    /// @param  autoClosure_ A boolean indicating whether a specific closure mechanism is enabled.
    /// @param accumulationMode_ The accumulation mode for this round (see AccumulationMode enum).
    event RoundEdited(
        uint indexed roundId_,
        uint roundStart_,
        uint roundEnd_,
        uint roundCap_,
        address hookContract_,
        bytes hookFunction_,
        bool autoClosure_,
        AccumulationMode accumulationMode_
    );

    /// @notice Emitted when access criteria is set for a round.
    /// @param  roundId_ The unique identifier of the round.
    /// @param  accessCriteriaId_ The identifier of the access criteria.
    event AccessCriteriaSet(uint32 indexed roundId_, uint8 accessCriteriaId_);

    /// @notice Emitted when access criteria is edited for a round.
    /// @param  roundId_ The unique identifier of the round.
    /// @param  accessCriteriaId_ The identifier of the access criteria.
    event AccessCriteriaEdited(
        uint32 indexed roundId_, uint8 accessCriteriaId_
    );

    /// @notice Emitted when access criteria privileges are set for a round.
    /// @param  roundId_ The unique identifier of the round.
    /// @param  accessCriteriaId_ The identifier of the access criteria.
    /// @param  personalCap_ The personal cap for the access criteria.
    /// @param  overrideContributionSpan_ Whether to override the round contribution span.
    /// @param  start_ The start timestamp for for when the linear vesting starts.
    /// @param  cliff_ The time in seconds from start time at which the unlock starts.
    /// @param  end_ The end timestamp for when the linear vesting ends.
    event AccessCriteriaPrivilegesSet(
        uint32 indexed roundId_,
        uint8 accessCriteriaId_,
        uint personalCap_,
        bool overrideContributionSpan_,
        uint start_,
        uint cliff_,
        uint end_
    );

    /// @notice Emitted when a contribution is made to a round.
    /// @param  roundId_ The ID of the round.
    /// @param  contributor_ The address of the contributor.
    /// @param  amount_ The amount contributed.
    event ContributionMade(uint32 roundId_, address contributor_, uint amount_);

    /// @notice Emitted when a round is closed.
    /// @param  roundId_ The ID of the round.
    /// @param  totalContributions_ The total contributions collected in the round.
    event RoundClosed(uint32 roundId_, uint totalContributions_);

    /// @notice Emitted when addresses are removed from an access criteria's allowed list.
    /// @param  roundId_ The ID of the round.
    /// @param  accessCriteriaId_ The ID of the access criteria.
    /// @param  addressesRemoved_ The addresses that were removed from the allowlist.
    event AllowlistedAddressesRemoved(
        uint32 roundId_, uint8 accessCriteriaId_, address[] addressesRemoved_
    );

    /// @notice Emitted when a payment order is created.
    /// @param  roundId_ The ID of the round.
    /// @param  contributor_ The address of the contributor.
    /// @param  accessCriteriaId_ The ID of the access criteria.
    /// @param  tokensForThisAccessCriteria_ The amount of tokens contributed for this access criteria.
    /// @param  start_ The start timestamp for for when the linear vesting starts.
    /// @param  cliff_ The time in seconds from start time at which the unlock starts.
    /// @param  end_ The end timestamp for when the linear vesting ends.
    event PaymentOrderCreated(
        uint32 roundId_,
        address contributor_,
        uint8 accessCriteriaId_,
        uint tokensForThisAccessCriteria_,
        uint start_,
        uint cliff_,
        uint end_
    );

    /// @notice Emitted when a contributor batch is processed.
    /// @param  roundId_ The ID of the round.
    /// @param  startIndex_ The starting index in the contributors array.
    /// @param  endIndex_ The ending index in the contributors array.
    event ContributorBatchProcessed(
        uint32 indexed roundId_, uint startIndex_, uint endIndex_
    );

    /// @notice Emitted when the global accumulation start round ID is updated.
    /// @param startRoundId The new round ID from which accumulation calculations will begin (inclusive, must be >= 1).
    event GlobalAccumulationStartSet(uint32 startRoundId);

    // -------------------------------------------------------------------------
    // Errors

    /// @notice Amount can not be zero.
    error Module__LM_PC_FundingPot__InvalidDepositAmount();

    /// @notice Round start time must be in the future.
    error Module__LM_PC_FundingPot__RoundStartMustBeInFuture();

    /// @notice Round must have either an end time or a funding cap.
    error Module__LM_PC_FundingPot__RoundMustHaveEndTimeOrCap();

    /// @notice Round end time must be after round start time.
    error Module__LM_PC_FundingPot__RoundEndMustBeAfterStart();

    /// @notice Round has already started and cannot be modified.
    error Module__LM_PC_FundingPot__RoundAlreadyStarted();

    /// @notice Thrown when a hook contract is specified with a hook function that has a non-empty implementation.
    error Module__LM_PC_FundingPot__HookFunctionRequiredWithHookContract();

    /// @notice Thrown when a hook function is specified without a hook contract.
    error Module__LM_PC_FundingPot__HookContractRequiredWithHookFunction();

    /// @notice Round does not exist.
    error Module__LM_PC_FundingPot__RoundNotCreated();

    /// @notice Incorrect access criteria.
    error Module__LM_PC_FundingPot__MissingRequiredAccessCriteriaData();

    /// @notice Invalid access criteria type.
    error Module__LM_PC_FundingPot__InvalidAccessCriteriaType();

    /// @notice Invalid times.
    error Module__LM_PC_FundingPot__InvalidTimes();

    /// @notice Round has not started yet.
    error Module__LM_PC_FundingPot__RoundHasNotStarted();

    /// @notice Round has already ended.
    error Module__LM_PC_FundingPot__RoundHasEnded();

    /// @notice User does not meet the NFT access criteria.
    error Module__LM_PC_FundingPot__AccessCriteriaNftFailed();

    /// @notice User does not meet the merkle proof access criteria.
    error Module__LM_PC_FundingPot__AccessCriteriaMerkleFailed();

    /// @notice User is not on the allowlist.
    error Module__LM_PC_FundingPot__AccessCriteriaListFailed();

    /// @notice Access not permitted.
    error Module__LM_PC_FundingPot__AccessNotPermitted();

    /// @notice User has reached their personal contribution cap.
    error Module__LM_PC_FundingPot__PersonalCapReached();

    /// @notice Round contribution cap has been reached.
    error Module__LM_PC_FundingPot__RoundCapReached();

    /// @notice Round Closure conditions are not met.
    error Module__LM_PC_FundingPot__ClosureConditionsNotMet();

    /// @notice Hook execution failed.
    error Module__LM_PC_FundingPot__HookExecutionFailed();

    /// @notice No contributions were made to the round.
    error Module__LM_PC_FundingPot__NoContributions();

    /// @notice Round is not closed.
    error Module__LM_PC_FundingPot__RoundNotClosed();

    /// @notice Invalid start index.
    error Module__LM_PC_FundingPot__InvalidStartIndex();

    /// @notice Invalid batch parameters.
    error Module__LM_PC_FundingPot__InvalidBatchParameters();

    /// @notice Start round ID must be greater than zero.
    error Module__LM_PC_FundingPot__StartRoundCannotBeZero();

    /// @notice Start round ID cannot be greater than the current round count.
    /// @param startRoundId_ The provided start round ID.
    /// @param currentRoundCount_ The current total number of rounds.
    error Module__LM_PC_FundingPot__StartRoundGreaterThanRoundCount(
        uint32 startRoundId_, uint32 currentRoundCount_
    );

    /// @notice Thrown when round IDs in UnspentPersonalRoundCap array are not strictly increasing.
    error Module__LM_PC_FundingPot__UnspentCapsRoundIdsNotStrictlyIncreasing();

    /// @notice Unspent caps must be from previous rounds.
    error Module__LM_PC_FundingPot__UnspentCapsMustBeFromPreviousRounds();

    /// @notice The round IDs for unspent caps must be contiguous.
    error Module__LM_PC_FundingPot__UnspentCapsRoundIdsNotContiguous();

    // -------------------------------------------------------------------------
    // Public - Getters

    /// @notice Retrieves the generic parameters of a specific funding round.
    /// @param  roundId_ The unique identifier of the round to retrieve.
    /// @return roundStart_ The timestamp when the round starts.
    /// @return roundEnd_ The timestamp when the round ends.
    /// @return roundCap_ The maximum contribution cap for the round.
    /// @return hookContract_ The address of the hook contract.
    /// @return hookFunction_ The encoded function call for the hook.
    /// @return autoClosure_ Whether hook closure coincides with contribution span end.
    /// @return accumulationMode_ The accumulation mode for the round.
    function getRoundGenericParameters(uint32 roundId_)
        external
        view
        returns (
            uint roundStart_,
            uint roundEnd_,
            uint roundCap_,
            address hookContract_,
            bytes memory hookFunction_,
            bool autoClosure_,
            AccumulationMode accumulationMode_
        );

    /// @notice Retrieves the access criteria for a specific funding round.
    /// @param  roundId_ The unique identifier of the round to retrieve.
    /// @param  accessCriteriaId_ The identifier of the access criteria to retrieve.
    /// @return isRoundOpen_ Whether anyone can contribute as part of the access criteria.
    /// @return nftContract_ The address of the NFT contract used for access control.
    /// @return merkleRoot_ The merkle root used for access verification.
    /// @return isList_ If the access criteria is a list, this will be true.
    function getRoundAccessCriteria(uint32 roundId_, uint8 accessCriteriaId_)
        external
        view
        returns (
            bool isRoundOpen_,
            address nftContract_,
            bytes32 merkleRoot_,
            bool isList_
        );

    /// @notice Retrieves the access criteria privileges for a specific funding round.
    /// @param  roundId_ The unique identifier of the round.
    /// @param  accessCriteriaId_ The identifier of the access criteria.
    /// @return personalCap_ The personal cap for the access criteria.
    /// @return overrideContributionSpan_ Whether to override the round contribution span.
    /// @return start_ The start timestamp for the access criteria.
    /// @return cliff_ The cliff timestamp for the access criteria.
    /// @return end_ The end timestamp for the access criteria.
    function getRoundAccessCriteriaPrivileges(
        uint32 roundId_,
        uint8 accessCriteriaId_
    )
        external
        view
        returns (
            uint personalCap_,
            bool overrideContributionSpan_,
            uint start_,
            uint cliff_,
            uint end_
        );

    /// @notice Retrieves the total number of funding rounds.
    /// @return roundCount_ The total number of funding rounds.
    function getRoundCount() external view returns (uint32 roundCount_);

    /// @notice Retrieves the closed status of a round.
    /// @param  roundId_ The ID of the round.
    /// @return The closed status of the round.
    function isRoundClosed(uint32 roundId_) external view returns (bool);

    /// @notice Gets eligibility information for a user in a specific round.
    /// @param  roundId_ The ID of the round to check eligibility for.
    /// @param  accessCriteriaId_ The ID of the access criteria to check eligibility for.
    /// @param  merkleProof_ The Merkle proof for validation if needed.
    /// @param  user_ The address of the user to check.
    /// @return isEligible Whether the user is eligible for the round through any criteria.
    /// @return remainingAmountAllowedToContribute The remaining contribution the user can make.
    function getUserEligibility(
        uint32 roundId_,
        uint8 accessCriteriaId_,
        bytes32[] memory merkleProof_,
        address user_
    )
        external
        view
        returns (bool isEligible, uint remainingAmountAllowedToContribute);

    /// @notice Retrieves the total contribution for a specific round.
    /// @param  roundId_ The ID of the round to check contributions for.
    /// @return The total contributions for the specified round.
    function getTotalRoundContribution(uint32 roundId_)
        external
        view
        returns (uint);

    /// @notice Retrieves the contribution amount for a specific user in a round.
    /// @param  roundId_ The ID of the round to check contributions for.
    /// @param  user_ The address of the user.
    /// @return The user's contribution amount for the specified round.
    function getUserContributionToRound(uint32 roundId_, address user_)
        external
        view
        returns (uint);

    /// @notice Retrieves the globally configured start round ID for accumulation calculations.
    /// @dev    Accumulation (both personal and total) will only consider previous rounds
    ///         with IDs greater than or equal to this value, provided the target round's
    ///         AccumulationMode allows it. Defaults to 1.
    /// @return The first round ID (inclusive) to consider for accumulation.
    function getGlobalAccumulationStartRoundId()
        external
        view
        returns (uint32);

    // -------------------------------------------------------------------------
    // Public - Mutating

    /// @notice Creates a new funding round.
    /// @dev    Only callable by funding pot admin.
    /// @param  roundStart_ Start timestamp for the round.
    /// @param  roundEnd_ End timestamp for the round (0 if using roundCap only).
    /// @param  roundCap_ Maximum contribution cap in collateral tokens (0 if using roundEnd only).
    /// @param  hookContract_ Address of contract to call after round closure.
    /// @param  hookFunction_ Encoded function call for the hook.
    /// @param  autoClosure_ Whether hook closure coincides with contribution span end.
    /// @param  accumulationMode_ Defines how caps accumulate across rounds (see AccumulationMode enum).
    /// @return The ID of the newly created round.
    function createRound(
        uint roundStart_,
        uint roundEnd_,
        uint roundCap_,
        address hookContract_,
        bytes memory hookFunction_,
        bool autoClosure_,
        AccumulationMode accumulationMode_
    ) external returns (uint32);

    /// @notice Edits an existing funding round.
    /// @dev    Only callable by funding pot admin and only before the round has started.
    /// @param  roundId_ ID of the round to edit.
    /// @param  roundStart_ New start timestamp.
    /// @param  roundEnd_ New end timestamp.
    /// @param  roundCap_ New maximum contribution cap.
    /// @param  hookContract_ New hook contract address.
    /// @param  hookFunction_ New encoded function call.
    /// @param  autoClosure_ New closure mechanism setting.
    /// @param  accumulationMode_ New accumulation mode setting.
    function editRound(
        uint32 roundId_,
        uint roundStart_,
        uint roundEnd_,
        uint roundCap_,
        address hookContract_,
        bytes memory hookFunction_,
        bool autoClosure_,
        AccumulationMode accumulationMode_
    ) external;

    /// @notice Set Access Control Check.
    /// @dev    Only callable by funding pot admin and only before the round has started.
    /// @param  roundId_ ID of the round.
    /// @param  accessCriteriaType_ access criteria type of the round.
    /// @param  accessCriteriaId_ ID of the access criteria.
    /// @param  nftContract_ Address of the NFT contract.
    /// @param  merkleRoot_ Merkle root for the access criteria.
    /// @param  allowedAddresses_ List of explicitly allowed addresses.
    /// @param  removedAddresses_ List of addresses to remove from the allowed list.
    function setAccessCriteria(
        uint32 roundId_,
        uint8 accessCriteriaType_,
        uint8 accessCriteriaId_,
        address nftContract_,
        bytes32 merkleRoot_,
        address[] memory allowedAddresses_,
        address[] memory removedAddresses_
    ) external;

    /// @notice Removes addresses from the allowed list for a specific access criteria.
    /// @dev    Only callable by funding pot admin and only before the round has started.
    /// @param  roundId_ ID of the round.
    /// @param  accessCriteriaId_ ID of the access criteria.
    /// @param  addressesToRemove_ List of addresses to remove from the allowed list.
    function removeAllowlistedAddresses(
        uint32 roundId_,
        uint8 accessCriteriaId_,
        address[] calldata addressesToRemove_
    ) external;

    /// @notice Set access criteria privileges.
    /// @dev    Only callable by funding pot admin and only before the round has started.
    /// @param  roundId_ ID of the round.
    /// @param  accessCriteriaId_ ID of the access criteria.
    /// @param  personalCap_ Personal cap for the access criteria.
    /// @param  overrideContributionSpan_ Whether to override the round contribution span.
    /// @param  start_ Start timestamp for the access criteria.
    /// @param  cliff_ Cliff timestamp for the access criteria.
    /// @param  end_ End timestamp for the access criteria.
    function setAccessCriteriaPrivileges(
        uint32 roundId_,
        uint8 accessCriteriaId_,
        uint personalCap_,
        bool overrideContributionSpan_,
        uint start_,
        uint cliff_,
        uint end_
    ) external;

    /// @notice Allows a user to contribute to a specific funding round.
    /// @dev    Verifies the contribution eligibility based on the provided Merkle proof.
    /// @param  user_ The address of the user to contribute for.
    /// @param  roundId_ The unique identifier of the funding round.
    /// @param  amount_ The amount of tokens being contributed.
    /// @param  accessCriteriaId_ The identifier for the access criteria to validate eligibility.
    /// @param  merkleProof_ The Merkle proof used to verify the contributor's eligibility.
    function contributeToRoundFor(
        address user_,
        uint32 roundId_,
        uint amount_,
        uint8 accessCriteriaId_,
        bytes32[] calldata merkleProof_
    ) external;

    /// @notice Allows a user to contribute to a round with unused capacity from previous rounds.
    /// @param  user_ The address of the user to contribute for.
    /// @param  roundId_ The ID of the round to contribute to.
    /// @param  amount_ The amount to contribute.
    /// @param  accessCriteriaId_ The ID of the access criteria to use for this contribution.
    /// @param  merkleProof_ The Merkle proof for validation if needed.
    /// @param  unspentPersonalRoundCaps_ Array of previous rounds and access criteria to calculate unused capacity from.
    function contributeToRoundFor(
        address user_,
        uint32 roundId_,
        uint amount_,
        uint8 accessCriteriaId_,
        bytes32[] calldata merkleProof_,
        UnspentPersonalRoundCap[] calldata unspentPersonalRoundCaps_
    ) external;

    /// @notice Closes a round.
    /// @param  roundId_ The ID of the round to close.
    function closeRound(uint32 roundId_) external;

    /// @notice Creates a batch of contributors for payment order creation.
    /// @param roundId_ The ID of the round to process contributors for.
    /// @param batchSize_ The number of contributors to process in this batch.
    function createPaymentOrdersForContributorsBatch(
        uint32 roundId_,
        uint batchSize_
    ) external;

    /// @notice Sets the global minimum round ID from which accumulation calculations should begin.
    /// @dev    Only callable by `FUNDING_POT_ADMIN_ROLE`. This setting affects all future
    ///         accumulation calculations across the module. The start round must be >= 1 and cannot exceed the current round count.
    /// @param  startRoundId_ The first round ID (inclusive, >= 1) to consider for accumulation.
    function setGlobalAccumulationStart(uint32 startRoundId_) external;
}
