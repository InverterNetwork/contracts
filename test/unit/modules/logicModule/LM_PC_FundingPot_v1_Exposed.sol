// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal
import {LM_PC_FundingPot_v1} from
    "src/modules/logicModule/LM_PC_FundingPot_v1.sol";

// Access Mock of the PP_Template_v1 contract for Testing.
contract LM_PC_FundingPot_v1_Exposed is LM_PC_FundingPot_v1 {
    // Use the `exposed_` prefix for functions to expose internal functions for
    // testing.

    function exposed_getTotalRoundContributions(uint64 roundId_)
        external
        view
        returns (uint)
    {
        return _getTotalRoundContribution(roundId_);
    }

    function exposed_getUserContributionToRound(uint64 roundId_, address user_)
        external
        view
        returns (uint)
    {
        return _getUserContributionToRound(roundId_, user_);
    }

    /**
     * @notice Exposes the internal _getUserPersonalCapForRound function for testing
     */
    function exposed_getUserPersonalCapForRound(
        uint64 roundId_,
        uint8 accessId_,
        address user_
    ) external view returns (uint) {
        return _getUserPersonalCapForRound(roundId_, accessId_, user_);
    }

    /**
     * @notice Exposes the internal _getUserUnusedCapacityFromPreviousRounds function for testing
     */
    function exposed_getUserUnusedCapacityFromPreviousRounds(
        address user_,
        uint64 currentRoundId_
    ) external view returns (uint) {
        return _getUserUnusedCapacityFromPreviousRounds(user_, currentRoundId_);
    }

    /**
     * @notice Exposes the internal _validTimes function for testing
     */
    function exposed_validTimes(uint start_, uint cliff_, uint end_)
        external
        pure
        returns (bool)
    {
        return _validTimes(start_, cliff_, end_);
    }

    /**
     * @notice Exposes the internal _validateRoundContribution function for testing
     */
    function exposed_validateRoundContribution(
        uint64 roundId_,
        uint8 accessCriteriaId_,
        bytes32[] calldata merkleProof_,
        uint amount_,
        address user_
    ) external view returns (uint) {
        return _validateRoundContribution(
            roundId_, accessCriteriaId_, merkleProof_, amount_, user_
        );
    }

    /**
     * @notice Exposes the internal _validateAndAdjustCaps function for testing
     */
    function exposed_validateAndAdjustCaps(
        uint64 roundId_,
        uint amount_,
        uint8 accessId_,
        bool canOverrideContributionSpan_
    ) external view returns (uint) {
        return _validateAndAdjustCaps(
            roundId_, amount_, accessId_, canOverrideContributionSpan_
        );
    }

    /**
     * @notice Exposes the internal _validateAccessCriteria function for testing
     */
    function exposed_validateAccessCriteria(
        uint64 roundId_,
        uint8 accessId_,
        bytes32[] calldata merkleProof_,
        address user_
    ) external view {
        _validateAccessCriteria(roundId_, accessId_, merkleProof_, user_);
    }

    /**
     * @notice Exposes the internal _checkAllowedAddressList function for testing
     */
    function exposed_checkAllowedAddressList(
        address[] memory allowedAddresses_,
        address sender_
    ) external pure returns (bool) {
        return _checkAllowedAddressList(allowedAddresses_, sender_);
    }

    /**
     * @notice Exposes the internal _checkNftOwnership function for testing
     */
    function exposed_checkNftOwnership(address nftContract_, address user_)
        external
        view
        returns (bool)
    {
        return _checkNftOwnership(nftContract_, user_);
    }

    /**
     * @notice Exposes the internal _validateMerkleProof function for testing
     */
    function exposed_validateMerkleProof(
        bytes32 root_,
        bytes32[] memory merkleProof_,
        address user_,
        uint64 roundId_
    ) external pure returns (bool) {
        return _validateMerkleProof(root_, merkleProof_, user_, roundId_);
    }
}
