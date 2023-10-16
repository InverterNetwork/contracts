// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

interface IBancorVirtualSupplyBondingCurveFundingManager {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Reserve ratio can not be be bigger than 100% expressed in PPM
    error BancorVirtualSupplyBondingCurveFundingManager__InvalidReserveRatio();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when the reserve ratio for buying is updated
    event BuyReserveRatioSet(
        uint32 indexed newBuyReserveRatio, uint32 indexed oldBuyReserveRatio
    );

    /// @notice Event emitted when the reserve ratio for selling is updated
    event SellReserveRatioSet(
        uint32 indexed newSellReserveRatio, uint32 indexed oldSellReserveRatio
    );

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

    /// @notice Returns reserve ratio set for buying, used in the Bancor Formula contract
    /// @return Reserve Ratio for buying
    function getReserveRatioForBuying() external view returns (uint32);

    /// @notice Returns reserve ratio set for selling, used in the Bancor Formula contract
    /// @return Reserve Ratio for selling
    function getReserveRatioForSelling() external view returns (uint32);
}
