// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {IRedeemingIssuanceBase_v2} from
    "@fm/bondingCurve/interfaces/IRedeemingIssuanceBase_v2.sol";

/**
 * @title   Inverter Redeeming Bonding Surface Funding Manager Interface
 *
 * @notice  This interface enables the fetching and setting of Bonding Surface
 *          relevant data.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @custom:version  v2.0.0
 *
 * @custom:inverter-standard-version    v0.1.0
 *
 * @author  Inverter Network
 */
interface IFM_BC_BondingSurface_Redeeming_v2 is
    IFundingManager_v1,
    IRedeemingIssuanceBase_v2
{
    // ========================================================================
    // Errors

    /// @notice Invalid Bonding Surface Formula contract.
    error FM_BC_BondingSurface_Redeeming_v2__InvalidBondingSurfaceFormula();

    /// @notice Amount does not match the requirements.
    error FM_BC_BondingSurface_Redeeming_v2__InvalidInputAmount();

    /// @notice No capital is available.
    error FM_BC_BondingSurface_Redeeming_v2__NoCapitalAvailable();

    /// @notice The minimum reserve has been reached.
    error FM_BC_BondingSurface_Redeeming_v2__MinReserveReached();

    // ========================================================================
    // Events

    /// @notice Emits when the capital required gets updated.
    event CapitalRequiredChanged(
        uint currentCapitalRequired, uint newCapitalRequired
    );

    /// @notice Emits when the Base Price Multiplier gets updated.
    event BasePriceMultiplierChanged(
        uint currentBasePriceMultiplier, uint newBasePriceMultiplier
    );

    /// @notice Emits when basePriceToCapitalRatio gets updated.
    event BasePriceToCapitalRatioChanged(
        uint currentBasePriceToCapitalRatio, uint newBasePriceToCapitalRatio
    );

    // ========================================================================
    // Structs

    /// @notice The bonding curve properties.
    /// @param  formula  The formula contract used to calculate the issucance
    ///         and redemption rate.
    /// @param  capitalRequired  The initial capital requirement for the
    ///         formula contract.
    /// @param  basePriceMultiplier  Base price multiplier in the bonding curve
    ///         formula.
    /// @param  buyFee       The buy fee expressed in base points.
    /// @param  sellFee      The sell fee expressed in base points.
    /// @param  buyIsOpen    The indicator used for enabling/disabling
    ///         the buying functionalities on deployment.
    /// @param  sellIsOpen   The indicator used for enabling/disabling
    ///         the selling functionalties on deployment.
    struct BondingCurveProperties {
        address formula;
        uint capitalRequired;
        uint basePriceMultiplier;
        uint buyFee;
        uint sellFee;
        bool buyIsOpen;
        bool sellIsOpen;
    }

    // ========================================================================
    // Public Getter Functions

    /// @notice Returns the formula contract used to calculate the issuance and
    ///         redemption rate.
    /// @return formula_ The formula contract address.
    function getBondingSurfaceFormula()
        external
        view
        returns (address formula_);

    /// @notice Returns the initial capital requirement for the formula
    ///         contract.
    /// @return capitalRequired The capital required.
    function getCapitalRequired()
        external
        view
        returns (uint capitalRequired);

    /// @notice Returns the base price multiplier.
    /// @return basePriceMultiplier_ The base price multiplier.
    function getBasePriceMultiplier()
        external
        view
        returns (uint basePriceMultiplier_);

    /// @notice Returns the base price to capital ratio.
    /// @return basePriceToCapitalRatio_ The base price to capital ratio.
    function getBasePriceToCapitalRatio()
        external
        view
        returns (uint basePriceToCapitalRatio_);

    /// @notice Calculates the ratio of base price multiplier to capital
    ///         required.
    /// @dev    Calls _calculateBasePriceToCapitalRatio internally.
    ///         Reverts if ratio exceeds 1e36.
    /// @param  capitalRequired_ The capital required.
    /// @param  basePriceMultiplier_ The base price multiplier.
    /// @return basePriceToCapitalRatio_ The calculated price to capital ratio.
    function calculateBasePriceToCapitalRatio(
        uint capitalRequired_,
        uint basePriceMultiplier_
    ) external view returns (uint basePriceToCapitalRatio_);

    // ========================================================================
    // Public Mutating Functions

    // ------------------------------------------------------------------------
    // Mutating - Permissioned Functions

    /// @notice Update the capital required used for the bonding curve.
    /// @dev    Function access controlled by authorizer.
    /// @param  newCapitalRequired_ The new capital required.
    function setCapitalRequired(uint newCapitalRequired_) external;

    /// @notice Update the base price multiplier used for the bonding curve.
    /// @dev    Function access controlled by authorizer.
    /// @param  newBasePriceMultiplier_ The new base price multiplier.
    function setBasePriceMultiplier(uint newBasePriceMultiplier_) external;
}
