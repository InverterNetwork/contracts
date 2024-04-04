// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IFM_BC_Bancor_Redeeming_VirtualIssuance_VirtualCollateral_v1 {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Reserve ratio can not be be bigger than 100% expressed in PPM
    error FM_BC_Bancor_Redeeming_VirtualIssuance_VirtualCollateral_v1__InvalidReserveRatio(
    );

    /// @notice Token decimal should not be lower than 7 decimals due to destructive precision loss
    /// when using the Bancor Formula contract otherwise.
    error FM_BC_Bancor_Redeeming_VirtualIssuance_VirtualCollateral_v1__InvalidTokenDecimal(
    );

    error FM_BC_Bancor_Redeeming_VirtualIssuance_VirtualCollateral_v1__InvalidDepositAmount(
    );

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when the reserve ratio for buying is updated
    /// @param newBuyReserveRatio The new reserve ratio for buying
    /// @param oldBuyReserveRatio The old reserve ratio for buying
    event BuyReserveRatioSet(
        uint32 indexed newBuyReserveRatio, uint32 indexed oldBuyReserveRatio
    );

    /// @notice Event emitted when the reserve ratio for selling is updated
    /// @param newSellReserveRatio The new reserve ratio for selling
    /// @param oldSellReserveRatio The old reserve ratio for selling
    event SellReserveRatioSet(
        uint32 indexed newSellReserveRatio, uint32 indexed oldSellReserveRatio
    );

    //--------------------------------------------------------------------------
    // Structs
    struct IssuanceToken {
        bytes32 name; // The name of the issuance token
        bytes32 symbol; // The symbol of the issuance token
        uint8 decimals; // The decimals used within the issuance token
    }

    struct BondingCurveProperties {
        address formula; // The formula contract used to calculate the issucance and redemption rate
        uint32 reserveRatioForBuying; // The reserve ratio, expressed in PPM, used for issuance on the bonding curve
        uint32 reserveRatioForSelling; // The reserve ratio, expressed in PPM, used for redeeming on the bonding curve
        uint buyFee; // The buy fee expressed in base points
        uint sellFee; // The sell fee expressed in base points
        bool buyIsOpen; // The indicator used for enabling/disabling the buying functionalities on deployment
        bool sellIsOpen; // The indicator used for enabling/disabling the selling functionalties on deployment
        uint initialIssuanceSupply; // The initial virtual issuance token supply
        uint initialCollateralSupply; // The initial virtual collateral token supply
    }

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
