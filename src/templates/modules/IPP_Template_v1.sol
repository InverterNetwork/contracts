// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies

// External Dependencies

interface IPP_Template_v1 {
    //--------------------------------------------------------------------------
    // Structs

    //--------------------------------------------------------------------------
    // Events

    /// @notice Emit when new payout amount has been set.
    /// @param oldPayoutAmount Old payout amount.
    /// @param newPayoutAmount Newly set payout amount.
    event NewPayoutAmountMultiplierSet(
        uint indexed oldPayoutAmount, uint indexed newPayoutAmount
    );

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Amount can not be zero.
    error Module__PP_Template_InvalidAmount();

    /// @notice Client is not valid.
    error Module__PP_Template__NotValidClient();

    //--------------------------------------------------------------------------
    // Public (Getter)

    /// @notice Returns the payout amount for each payment order.
    /// @param payoutAmount The payout amount.
    function getPayoutAmountMultiplier() external returns (uint payoutAmount);

    //--------------------------------------------------------------------------
    // Public (Mutation)
}
