// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IFM_BC_BondingSurface_Redeeming_v1 {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Invalid Bonding Surface Formula contract
    error FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__InvalidBondingSurfaceFormula(
    );

    /// @notice Amount does not match the requirements
    error FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__InvalidInputAmount(
    );

    /// @notice Invalid address passed as argument
    error FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__InvalidInputAddress(
    );

    /// @notice Buy fee can not be set.
    error FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__InvalidFunctionality(
    );

    /// @notice Fee percentage cannont be higher than ToDO: %
    error FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__InvalidFeePercentage(
        uint fee
    );

    /// @notice No capital is available.
    error FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__NoCapitalAvailable(
    );

    //--------------------------------------------------------------------------
    // Events

    /// @notice Emits when the capital required gets updated
    event CapitalRequiredChanged(
        uint currentCapitalRequired, uint newCapitalRequired
    );

    /// @notice Emits when the Base Price Multiplier gets updated
    event BasePriceMultiplierChanged(
        uint currentBasePriceMultiplier, uint newBasePriceMultiplier
    );

    /// @notice Emits when basePriceToCapitalRatio gets updated
    event BasePriceToCapitalRatioChanged(
        uint currentBasePriceToCapitalRatio, uint newBasePriceToCapitalRatio
    );

    /// @notice Emits when buy and sell restriction is set.
    event BuyAndSellIsRestricted();

    /// @notice Emits when buy and sell restriction is removed.
    event BuyAndSellIsUnrestricted();

    //--------------------------------------------------------------------------
    // Structs

    /// @notice The bonding curve properties.
    /// @param capitalRequired The initial capital requirement for the formula contract
    /// @param formula The formula contract used to calculate the issucance and redemption rate
    /// @param buyFee The buy fee expressed in base points
    /// @param sellFee The sell fee expressed in base points
    /// @param buyIsOpen The indicator used for enabling/disabling the buying functionalities on deployment
    /// @param sellIsOpen The indicator used for enabling/disabling the selling functionalties on deployment
    /// @param seize The current seize percentage expresses in BPS
    /// @param basePriceMultiplier Base price multiplier in the bonding curve formula
    /// @param buyAndSellIsRestricted The indicator used for restrict/unrestrict buying and selling functionalities to the CURVE_INTERACTION_ROLE
    struct BondingCurveProperties {
        uint capitalRequired;
        address formula;
        uint buyFee;
        uint sellFee;
        bool buyIsOpen;
        bool sellIsOpen;
        uint64 seize; //@todo needs to be removed here
        uint basePriceMultiplier;
        bool buyAndSellIsRestricted;
    }

    //--------------------------------------------------------------------------
    // Functions

    /// @dev Update the base price multiplier used for the bonding curve
    /// @param _newBasePriceMultiplier Base price multiplier used for price calculation
    function setBasePriceMultiplier(uint _newBasePriceMultiplier) external;

    /// @dev Update the capital required used for the bonding curve
    /// @param _newCapitalRequired Capital required needed to operate the protocol
    function setCapitalRequired(uint _newCapitalRequired) external;

    /// @notice Calculates the ratio of base price multiplier to capital required.
    /// @dev Calls `_calculateBasePriceToCapitalRatio` internally. Reverts if ratio exceeds 1e36.
    /// @param _capitalRequired The capital required.
    /// @param _basePriceMultiplier The base price multiplier.
    /// @return _basePriceToCapitalRatio The calculated price to capital ratio.
    function calculateBasePriceToCapitalRatio(
        uint _capitalRequired,
        uint _basePriceMultiplier
    ) external view returns (uint _basePriceToCapitalRatio);

    /// @notice Restricts buying and selling functionalities to the CURVE_INTERACTION_ROLE.
    /// @dev    Only callable by the COVER_MANAGER_ROLE.
    function restrictBuyAndSell() external;

    /// @notice Unrestricts buying and selling functionalities to the CURVE_INTERACTION_ROLE.
    /// @dev    Only callable by the COVER_MANAGER_ROLE.
    function unrestrictBuyAndSell() external;
}
