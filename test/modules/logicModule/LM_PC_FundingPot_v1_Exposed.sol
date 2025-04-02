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
     * @notice Exposes the internal _getUserPersonalCap function for testing
     */
    function exposed_getUserPersonalCapForRound(
        uint64 roundId_,
        uint8 accessId_,
        address user_
    ) external view returns (uint) {
        return _getUserPersonalCapForRound(roundId_, accessId_, user_);
    }

    /**
     * @notice Exposes the internal _getUnusedCapacityFromPreviousRounds function for testing
     */
    function exposed_getUserUnusedCapacityFromPreviousRounds(
        address user_,
        uint64 currentRoundId_
    ) external view returns (uint) {
        return _getUserUnusedCapacityFromPreviousRounds(user_, currentRoundId_);
    }
}
