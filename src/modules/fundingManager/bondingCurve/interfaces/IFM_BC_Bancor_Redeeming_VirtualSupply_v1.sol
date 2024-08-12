// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IFM_BC_Bancor_Redeeming_VirtualSupply_v1 {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Reserve ratio can not be be bigger than 100% expressed in PPM.
    error Module__FM_BC_Bancor_Redeeming_VirtualSupply__InvalidReserveRatio();

    /// @notice To avoid destructive precision loss when using the Bancor Formula,
    ///         the Token decimals should:
    //              - Not be lower than 7 decimals.
    //              - Higher or equal to the collateral token decimals.
    error Module__FM_BC_Bancor_Redeeming_VirtualSupply__InvalidTokenDecimal();

    /// @notice Invalid Bancor Formula contract
    error Module__FM_BC_Bancor_Redeeming_VirtualSupply__InvalidBancorFormula();

    /// @notice Buying and Selling must be closed before changing the virtual supply.
    error Module__FM_BC_Bancor_Redeeming_VirtualSupply__CurveInteractionsMustBeClosed(
    );
    /// @notice Funding manager does not hold the amount of collateral the payment client tries to transfer.
    error Module__FM_BC_Bancor_Redeeming_VirtualSupply__InvalidOrchestratorTokenWithdrawAmount(
    );

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when the reserve ratio for buying is updated.
    /// @param newBuyReserveRatio The new reserve ratio for buying.
    /// @param oldBuyReserveRatio The old reserve ratio for buying.
    event BuyReserveRatioSet(
        uint32 newBuyReserveRatio, uint32 oldBuyReserveRatio
    );

    /// @notice Event emitted when the reserve ratio for selling is updated.
    /// @param newSellReserveRatio The new reserve ratio for selling.
    /// @param oldSellReserveRatio The old reserve ratio for selling.
    event SellReserveRatioSet(
        uint32 newSellReserveRatio, uint32 oldSellReserveRatio
    );

    //--------------------------------------------------------------------------
    // Structs
    struct BondingCurveProperties {
        /// @notice The formula contract used to calculate the issucance and redemption rate
        address formula;
        /// @notice The reserve ratio, expressed in PPM, used for issuance on the bonding curve
        uint32 reserveRatioForBuying;
        /// @notice The reserve ratio, expressed in PPM, used for redeeming on the bonding curve
        uint32 reserveRatioForSelling;
        /// @notice The buy fee expressed in base points
        uint buyFee;
        /// @notice The sell fee expressed in base points
        uint sellFee;
        /// @notice The indicator used for enabling/disabling the buying functionalities on deployment
        bool buyIsOpen;
        /// @notice The indicator used for enabling/disabling the selling functionalties on deployment
        bool sellIsOpen;
        /// @notice The initial virtual issuance token supply
        uint initialIssuanceSupply;
        /// @notice The initial virtual collateral token supply
        uint initialCollateralSupply;
    }

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Set the reserve ratio used for issuing tokens on a bonding curve.
    /// @dev This function can only be called by the Orchestrator_v1 admin.
    /// @param _reserveRatio The new reserve ratio for buying, expressed in PPM.
    function setReserveRatioForBuying(uint32 _reserveRatio) external;

    /// @notice Set the reserve ratio used for redeeming tokens on a bonding curve.
    /// @dev This function can only be called by the Orchestrator_v1 admin.
    /// @param _reserveRatio The new reserve ratio for selling, expressed in PPM.
    function setReserveRatioForSelling(uint32 _reserveRatio) external;

    /// @notice Returns reserve ratio set for buying, used in the Bancor Formula contract.
    /// @return Reserve Ratio for buying.
    function getReserveRatioForBuying() external view returns (uint32);

    /// @notice Returns reserve ratio set for selling, used in the Bancor Formula contract.
    /// @return Reserve Ratio for selling.
    function getReserveRatioForSelling() external view returns (uint32);
}
