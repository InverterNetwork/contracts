// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IFM_BC_BondingSurface_Redeeming_v1 {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Invalid Bonding Surface Formula contract
    error FM_BC_BondingSurface_Redeeming_v1__InvalidBondingSurfaceFormula();

    /// @notice Amount does not match the requirements
    error FM_BC_BondingSurface_Redeeming_v1__InvalidInputAmount();

    /// @notice No capital is available.
    error FM_BC_BondingSurface_Redeeming_v1__NoCapitalAvailable();

    /// @notice The minimum reserve has been reached.
    error FM_BC_BondingSurface_Redeeming_v1__MinReserveReached();

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

    //--------------------------------------------------------------------------
    // Structs

    /// @notice The bonding curve properties.
    /// @param formula The formula contract used to calculate the issucance and redemption rate
    /// @param capitalRequired The initial capital requirement for the formula contract
    /// @param basePriceMultiplier Base price multiplier in the bonding curve formula
    /// @param buyFee The buy fee expressed in base points
    /// @param sellFee The sell fee expressed in base points
    /// @param buyIsOpen The indicator used for enabling/disabling the buying functionalities on deployment
    /// @param sellIsOpen The indicator used for enabling/disabling the selling functionalties on deployment
    struct BondingCurveProperties {
        address formula;
        uint capitalRequired;
        uint basePriceMultiplier;
        uint buyFee;
        uint sellFee;
        bool buyIsOpen;
        bool sellIsOpen;
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
}
