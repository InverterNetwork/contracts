// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal
import {LM_PC_FundingPot_v1} from
    "src/modules/logicModule/LM_PC_FundingPot_v1.sol";

// Access Mock of the LM_PC_FundingPot_v1 contract for Testing.
contract LM_PC_FundingPot_v1_Exposed is LM_PC_FundingPot_v1 {
    // Use the `exposed_` prefix for functions to expose internal functions for
    // testing.

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
     * @notice Exposes the internal _validateAndAdjustCapsWithUnspentCap function for testing
     */
    function exposed_validateAndAdjustCapsWithUnspentCap(
        address user_,
        uint32 roundId_,
        uint amount_,
        uint8 accessCriteriaId__,
        bool canOverrideContributionSpan_,
        uint unspentPersonalCap_
    ) external view returns (uint) {
        return _validateAndAdjustCapsWithUnspentCap(
            user_,
            roundId_,
            amount_,
            accessCriteriaId__,
            canOverrideContributionSpan_,
            unspentPersonalCap_
        );
    }

    /**
     * @notice Exposes the internal _validateAccessCriteria function for testing
     */
    function exposed_validateAccessCriteria(
        uint32 roundId_,
        uint8 accessId_,
        bytes32[] calldata merkleProof_,
        address user_
    ) external view {
        _validateAccessCriteria(roundId_, accessId_, merkleProof_, user_);
    }

    /**
     * @notice Exposes the internal _checkAccessCriteriaEligibility function for testing
     */
    function exposed_checkAccessCriteriaEligibility(
        uint32 roundId_,
        uint8 accessCriteriaId_,
        bytes32[] memory merkleProof_,
        address user_
    ) external view returns (bool) {
        return _checkAccessCriteriaEligibility(
            roundId_, accessCriteriaId_, merkleProof_, user_
        );
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
        uint32 roundId_
    ) external pure returns (bool) {
        return _validateMerkleProof(root_, merkleProof_, user_, roundId_);
    }

    /**
     * @notice Exposes the internal _calculateUnusedCapacityFromPreviousRounds function for testing
     */
    function exposed_calculateUnusedCapacityFromPreviousRounds(uint32 roundId_)
        external
        view
        returns (uint)
    {
        return _calculateUnusedCapacityFromPreviousRounds(roundId_);
    }

    function exposed_contributeToRoundFor(
        address user_,
        uint32 roundId_,
        uint amount_,
        uint8 accessCriteriaId__,
        bytes32[] memory merkleProof_,
        uint unspentPersonalCap_
    ) external {
        _contributeToRoundFor(
            user_,
            roundId_,
            amount_,
            accessCriteriaId__,
            merkleProof_,
            unspentPersonalCap_
        );
    }

    /**
     * @notice Exposes the internal _closeRound function for testing
     */
    function exposed_closeRound(uint32 roundId_) external {
        _closeRound(roundId_);
    }

    /**
     * @notice Exposes the internal _checkRoundClosureConditions function for testing
     */
    function exposed_checkRoundClosureConditions(uint32 roundId_)
        external
        view
        returns (bool)
    {
        return _checkRoundClosureConditions(roundId_);
    }

    /**
     * @notice Exposes the internal _buyBondingCurveToken function for testing
     */
    function exposed_buyBondingCurveToken(uint32 roundId_) external {
        return _buyBondingCurveToken(roundId_);
    }

    /**
     * @notice Exposes the internal _createPaymentOrdersForContributors function for testing
     */
    function exposed_createPaymentOrdersForContributors(
        uint32 roundId_,
        uint startIndex_,
        uint batchSize_
    ) external {
        return _createPaymentOrdersForContributors(
            roundId_, startIndex_, batchSize_
        );
    }
}
