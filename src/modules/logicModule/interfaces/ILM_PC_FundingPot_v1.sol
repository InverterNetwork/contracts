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
    /// @param  globalAccumulativeCaps Indicates whether contribution caps accumulate globally across rounds.
    /// @param  accessCriterias Mapping of access criteria IDs to their respective access criteria.
    struct Round {
        uint roundStart;
        uint roundEnd;
        uint roundCap;
        address hookContract;
        bytes hookFunction;
        bool autoClosure;
        bool globalAccumulativeCaps;
        mapping(uint64 id => AccessCriteria) accessCriterias;
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
        address[] allowedAddresses; // Explicit allowlist
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
    /// @param  globalAccumulativeCaps_ A boolean indicating whether global accumulative caps are enforced.
    event RoundCreated(
        uint indexed roundId_,
        uint roundStart_,
        uint roundEnd_,
        uint roundCap_,
        address hookContract_,
        bytes hookFunction_,
        bool autoClosure_,
        bool globalAccumulativeCaps_
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
    /// @param  globalAccumulativeCaps_ A boolean indicating whether global accumulative caps are enforced.
    event RoundEdited(
        uint indexed roundId_,
        uint roundStart_,
        uint roundEnd_,
        uint roundCap_,
        address hookContract_,
        bytes hookFunction_,
        bool autoClosure_,
        bool globalAccumulativeCaps_
    );

    /// @notice Emitted when access criteria is set for a round.
    /// @param  roundId_ The unique identifier of the round.
    /// @param  accessId_ The identifier of the access criteria.
    /// @param  accessCriteria_ The access criteria.
    event AccessCriteriaSet(
        uint64 indexed roundId_, uint8 accessId_, AccessCriteria accessCriteria_
    );

    /// @notice Emitted when access criteria is edited for a round.
    /// @param  roundId_ The unique identifier of the round.
    /// @param  accessId_ The identifier of the access criteria.
    /// @param  accessCriteria_ The access criteria.
    event AccessCriteriaEdited(
        uint64 indexed roundId_, uint8 accessId_, AccessCriteria accessCriteria_
    );

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

    /// @notice Hook function is required when a hook contract is provided.
    error Module__LM_PC_FundingPot__HookFunctionRequiredWithContract();

    /// @notice Thrown when a hook contract is specified without a hook function.
    error Module__LM_PC_FundingPot__HookFunctionRequiredWithHookContract();

    /// @notice Thrown when a hook function is specified without a hook contract.
    error Module__LM_PC_FundingPot__HookContractRequiredWithHookFunction();

    /// @notice Round does not exist.
    error Module__LM_PC_FundingPot__RoundNotCreated();

    /// @notice Incorrect access criteria.
    error Module__LM_PC_FundingPot__MissingRequiredAccessCriteriaData();

    /// @notice Invalid access criteria ID.
    error Module__LM_PC_FundingPot__InvalidAccessCriteriaId();

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
    /// @return globalAccumulativeCaps_ Whether caps accumulate globally across rounds.
    function getRoundGenericParameters(uint64 roundId_)
        external
        view
        returns (
            uint roundStart_,
            uint roundEnd_,
            uint roundCap_,
            address hookContract_,
            bytes memory hookFunction_,
            bool autoClosure_,
            bool globalAccumulativeCaps_
        );

    /// @notice Retrieves the access criteria for a specific funding round.
    /// @param  roundId_ The unique identifier of the round to retrieve.
    /// @param  accessCriteriaId_ The identifier of the access criteria to retrieve.
    /// @return isOpen_ Whether the access criteria is open.
    /// @return nftContract_ The address of the NFT contract used for access control.
    /// @return merkleRoot_ The merkle root used for access verification.
    /// @return allowedAddresses_ The list of explicitly allowed addresses.
    function getRoundAccessCriteria(uint64 roundId_, uint8 accessCriteriaId_)
        external
        view
        returns (
            bool isOpen_,
            address nftContract_,
            bytes32 merkleRoot_,
            address[] memory allowedAddresses_
        );

    /// @notice Retrieves the total number of funding rounds.
    /// @return roundCount_ The total number of funding rounds.
    function getRoundCount() external view returns (uint64 roundCount_);

    /// @notice Retrieves the total number of access criteria for a specific round.
    /// @param  roundId_ The unique identifier of the round.
    /// @return accessCriteriaCount_ The total number of access criteria for the round.
    function getRoundAccessCriteriaCount(uint64 roundId_)
        external
        view
        returns (uint8 accessCriteriaCount_);

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
    /// @param  globalAccumulativeCaps_ Whether caps accumulate globally.
    /// @return The ID of the newly created round.
    function createRound(
        uint roundStart_,
        uint roundEnd_,
        uint roundCap_,
        address hookContract_,
        bytes memory hookFunction_,
        bool autoClosure_,
        bool globalAccumulativeCaps_
    ) external returns (uint64);

    /// @notice Edits an existing funding round.
    /// @dev    Only callable by funding pot admin and only before the round has started.
    /// @param  roundId_ ID of the round to edit.
    /// @param  roundStart_ New start timestamp.
    /// @param  roundEnd_ New end timestamp.
    /// @param  roundCap_ New maximum contribution cap.
    /// @param  hookContract_ New hook contract address.
    /// @param  hookFunction_ New encoded function call.
    /// @param  autoClosure_ New closure mechanism setting.
    /// @param  globalAccumulativeCaps_ New global accumulative caps setting.
    function editRound(
        uint64 roundId_,
        uint roundStart_,
        uint roundEnd_,
        uint roundCap_,
        address hookContract_,
        bytes memory hookFunction_,
        bool autoClosure_,
        bool globalAccumulativeCaps_
    ) external;

    /// @notice Set Access Control Check.
    /// @dev    Only callable by funding pot admin and only before the round has started.
    /// @param  roundId_ ID of the round.
    /// @param  accessCriteria_ Access criteria to set.
    function setAccessCriteriaForRound(
        uint64 roundId_,
        AccessCriteria memory accessCriteria_
    ) external;

    /// @notice Edits an existing access criteria for a round.
    /// @dev    Only callable by funding pot admin and only before the round has started.
    /// @param  roundId_ ID of the round.
    /// @param  accessCriteriaId_ ID of the access criteria.
    /// @param  accessCriteria_ New access criteria.
    function editAccessCriteriaForRound(
        uint64 roundId_,
        uint8 accessCriteriaId_,
        AccessCriteria memory accessCriteria_
    ) external;
}
