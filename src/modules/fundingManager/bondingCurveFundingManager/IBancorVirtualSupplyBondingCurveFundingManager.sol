// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

interface IBancorVirtualSupplyBondingCurveFundingManager {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Reserve ratio can not be be bigger than 100% expressed in PPM
    error BancorVirtualSupplyBondingCurveFundingManager__InvalidReserveRatio();

    //--------------------------------------------------------------------------
    // Events

    // TODO: Contract still needs events. Where are events needed?

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Mints a specified amount of Issuance Tokens to a designated receiver address.
    /// @dev This function is restricted to be called only by the Orchestrator Owner.
    ///      It uses the internal _mint function to mint the tokens.
    /// @param _receiver The address that will receive the newly minted tokens.
    /// @param _amount The amount of tokens to be minted.
    function mintIssuanceTokenTo(address _receiver, uint _amount) external;

    /// @notice Set the reserve ratio used for issuing tokens on a bonding curve.
    /// @dev This function can only be called by the Orchestrator owner, or Manager.
    /// @param _reserveRatio The new reserve ratio for buying, expressed in PPM.
    function setReserveRatioForBuying(uint32 _reserveRatio) external;

    /// @notice Set the reserve ratio used for redeeming tokens on a bonding curve.
    /// @dev This function can only be called by the Orchestrator owner, or Manager.
    /// @param _reserveRatio The new reserve ratio for selling, expressed in PPM.
    function setReserveRatioForSelling(uint32 _reserveRatio) external;
}
