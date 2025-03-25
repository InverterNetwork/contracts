// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";

interface ILM_PC_FundingPot_v1 is IERC20PaymentClientBase_v2 {
    //--------------------------------------------------------------------------
    // Structs

    /// @notice Struct used to store information about a funding round.
    /// @param roundStart Timestamp indicating when the round starts.
    /// @param roundEnd Timestamp indicating when the round ends. If set to `0`, the round operates only based on `roundCap`.
    /// @param roundCap Maximum contribution cap in collateral tokens. If set to `0`, the round operates only based on `roundEnd`.
    /// @param hookContract Address of an optional hook contract to be called after round closure.
    /// @param hookFunction Encoded function call to be executed on the `hookContract` after round closure.
    /// @param closureMechanism Indicates whether the hook closure coincides with the contribution span end.
    /// @param globalAccumulativeCaps Indicates whether contribution caps accumulate globally across rounds.
    /// @param accessCriterias Mapping of access criteria IDs to their respective access criteria.
    struct Round {
        uint roundStart;
        uint roundEnd;
        uint roundCap;
        address hookContract;
        bytes hookFunction;
        bool closureMechanism;
        bool globalAccumulativeCaps;
        mapping(uint64 id => AccessCriteria) accessCriterias;
    }

    /// @notice Struct used to store information about a funding round's access criteria.
    /// @param nftContract Address of the NFT contract.
    /// @param merkleRoot Merkle root for the access criteria.
    /// @param allowedAddresses Mapping of addresses to their access status.
    struct AccessCriteria {
        AccessCriteriaId accessCriteriaId;
        address nftContract; // NFT contract address (0x0 if unused)
        bytes32 merkleRoot; // Merkle root (0x0 if unused)
        address[] allowedAddresses; // Explicit allowlist
    }

    // -------------------------------------------------------------------------
    // Enums

    /// @notice Enum used to identify the type of access criteria.
    enum AccessCriteriaId {
        OPEN, // 0
        NFT, // 1
        MERKLE, // 2
        LIST // 3

    }

    // -------------------------------------------------------------------------
    // Events

    /// @notice Emitted when a new round is created.
    /// @dev This event signals the creation of a new round with specific parameters.
    /// @param roundId The unique identifier for the round.
    /// @param roundStart The timestamp when the round starts.
    /// @param roundEnd The timestamp when the round ends.
    /// @param roundCap The maximum allocation or cap for the round.
    /// @param hookContract The address of an optional hook contract for custom logic.
    /// @param closureMechanism A boolean indicating whether a specific closure mechanism is enabled.
    /// @param globalAccumulativeCaps A boolean indicating whether global accumulative caps are enforced.
    event RoundCreated(
        uint indexed roundId,
        uint roundStart,
        uint roundEnd,
        uint roundCap,
        address hookContract,
        bool closureMechanism,
        bool globalAccumulativeCaps
    );

    /// @notice Emitted when an existing round is edited.
    /// @dev This event signals modifications to an existing round's parameters.
    /// @param roundId The unique identifier of the round being edited.
    /// @param roundStart The updated timestamp for when the round starts.
    /// @param roundEnd The updated timestamp for when the round ends.
    /// @param roundCap The updated maximum allocation or cap for the round.
    /// @param hookContract The address of an optional hook contract for custom logic.
    /// @param closureMechanism A boolean indicating whether a specific closure mechanism is enabled.
    /// @param globalAccumulativeCaps A boolean indicating whether global accumulative caps are enforced.
    event RoundEdited(
        uint indexed roundId,
        uint roundStart,
        uint roundEnd,
        uint roundCap,
        address hookContract,
        bool closureMechanism,
        bool globalAccumulativeCaps
    );

    /// @notice Emitted when access criteria is set for a round.
    /// @param roundId The unique identifier of the round.
    /// @param accessId The identifier of the access criteria.
    /// @param accessCriteria The access criteria.
    event AccessCriteriaSet(
        uint64 indexed roundId, uint8 accessId, AccessCriteria accessCriteria
    );

    // -------------------------------------------------------------------------
    // Errors

    /// @notice Amount can not be zero.
    error Module__LM_PC_FundingPot__InvalidDepositAmount();

    /// @notice Round does not exist
    error Module__LM_PC_FundingPot__RoundDoesNotExist();

    /// @notice Round start time must be in the future
    error Module__LM_PC_FundingPot__RoundStartMustBeInFuture();

    /// @notice Round must have either an end time or a funding cap
    error Module__LM_PC_FundingPot__RoundMustHaveEndTimeOrCap();

    /// @notice Round end time must be after round start time
    error Module__LM_PC_FundingPot__RoundEndMustBeAfterStart();

    /// @notice Round has already started and cannot be modified
    error Module__LM_PC_FundingPot__RoundAlreadyStarted();

    /// @notice Hook function is required when a hook contract is provided
    error Module__LM_PC_FundingPot__HookFunctionRequiredWithContract();

    /// @notice Thrown when a hook contract is specified without a hook function.
    error Module__LM_PC_FundingPot__HookFunctionRequiredWithHookContract();

    /// @notice Thrown when a hook function is specified without a hook contract.
    error Module__LM_PC_FundingPot__HookContractRequiredWithHookFunction();

    /// @notice Round does not exist
    error Module__LM_PC_FundingPot__RoundNotCreated();

    /// @notice Incorrect access criteria
    error Module__LM_PC_FundingPot__MissingRequiredAccessCriteriaData();

    // -------------------------------------------------------------------------
    // Public - Getters

    /// @notice Retrieves the generic parameters of a specific funding round.
    /// @param _roundId The unique identifier of the round to retrieve.
    /// @return roundStart The timestamp when the round starts
    /// @return roundEnd The timestamp when the round ends
    /// @return roundCap The maximum contribution cap for the round
    /// @return hookContract The address of the hook contract
    /// @return hookFunction The encoded function call for the hook
    /// @return closureMechanism Whether hook closure coincides with contribution span end
    /// @return globalAccumulativeCaps Whether caps accumulate globally across rounds
    function getRoundGenericParameters(uint64 _roundId)
        external
        view
        returns (
            uint roundStart,
            uint roundEnd,
            uint roundCap,
            address hookContract,
            bytes memory hookFunction,
            bool closureMechanism,
            bool globalAccumulativeCaps
        );

    /// @notice Retrieves the access criteria for a specific funding round.
    /// @param _roundId The unique identifier of the round to retrieve.
    /// @param _id The identifier of the access criteria to retrieve.
    /// @return isOpen Whether the access criteria is open
    /// @return nftContract The address of the NFT contract used for access control
    /// @return merkleRoot The merkle root used for access verification
    /// @return allowedAddresses The list of explicitly allowed addresses
    function getRoundAccessCriteria(uint64 _roundId, uint8 _id)
        external
        view
        returns (
            bool isOpen,
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        );

    /// @notice Retrieves the total number of funding rounds.
    /// @return The total number of funding rounds.
    function getRoundCount() external view returns (uint64);

    // -------------------------------------------------------------------------
    // Public - Mutating

    /// @notice Creates a new funding round
    /// @dev Only callable by funding pot admin
    /// @param _roundStart Start timestamp for the round
    /// @param _roundEnd End timestamp for the round (0 if using roundCap only)
    /// @param _roundCap Maximum contribution cap in collateral tokens (0 if using roundEnd only)
    /// @param _hookContract Address of contract to call after round closure
    /// @param _hookFunction Encoded function call for the hook
    /// @param _closureMechanism Whether hook closure coincides with contribution span end
    /// @param _globalAccumulativeCaps Whether caps accumulate globally
    /// @return The ID of the newly created round
    function createRound(
        uint _roundStart,
        uint _roundEnd,
        uint _roundCap,
        address _hookContract,
        bytes memory _hookFunction,
        bool _closureMechanism,
        bool _globalAccumulativeCaps
    ) external returns (uint64);

    /// @notice Edits an existing funding round
    /// @dev Only callable by funding pot admin and only before the round has started
    /// @param _roundId ID of the round to edit
    /// @param _roundStart New start timestamp
    /// @param _roundEnd New end timestamp
    /// @param _roundCap New maximum contribution cap
    /// @param _hookContract New hook contract address
    /// @param _hookFunction New encoded function call
    /// @param _closureMechanism New closure mechanism setting
    /// @param _globalAccumulativeCaps New global accumulative caps setting
    function editRound(
        uint64 _roundId,
        uint _roundStart,
        uint _roundEnd,
        uint _roundCap,
        address _hookContract,
        bytes memory _hookFunction,
        bool _closureMechanism,
        bool _globalAccumulativeCaps
    ) external;

    /// @notice Set Access Control Check
    /// @dev Only callable by funding pot admin and only before the round has started
    /// @param _roundId ID of the round
    /// @param _accessId ID of the access criteria
    /// @param _accessCriteria Access criteria to set
    function setAccessCriteriaForRound(
        uint64 _roundId,
        uint8 _accessId,
        AccessCriteria memory _accessCriteria
    ) external;
}
