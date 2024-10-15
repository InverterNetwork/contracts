// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice The feature is deactivated in this implementation.
    error Module__FM_BC_Restricted_Bancor_Redeeming_VirtualSupply__FeatureDeactivated(
    );

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Returns constant CURVE_INTERACTION_ROLE.
    /// @return Role that allows interactions with the bonding curve.
    function CURVE_INTERACTION_ROLE() external view returns (bytes32);
}
