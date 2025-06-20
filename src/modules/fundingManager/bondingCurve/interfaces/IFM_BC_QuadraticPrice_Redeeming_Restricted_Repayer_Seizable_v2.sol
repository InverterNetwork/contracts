// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

//Internal Dependencies
import {IFM_BC_QuadraticPrice_Redeeming_v2} from
    "@fm/bondingCurve/interfaces/IFM_BC_QuadraticPrice_Redeeming_v2.sol";
import {IRepayer_v1} from "@fm/bondingCurve/interfaces/IRepayer_v1.sol";

/**
 * @title   Inverter Redeeming Restriced Repayer Seizable Quadratic Price Formula
 *     Bonding Curve Funding Manager Interface
 *
 * @notice  This interface enables the fetching and setting of Quadratic Price Formula
 *          relevant data with the added functionalities Restricted and
 *          Seizable.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @custom:version  v2.0.0
 *
 * @custom:former-name IFM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v2
 *
 * @custom:inverter-standard-version    v0.1.0
 *
 * @author  Inverter Network
 */
interface IFM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2 is
    IFM_BC_QuadraticPrice_Redeeming_v2,
    IRepayer_v1
{
    // ========================================================================
    // Errors

    /// @notice Invalid address passed as argument.
    error FM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2__InvalidInputAddress(
    );

    /// @notice Buy fee can not be set.
    error FM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2__InvalidFunctionality(
    );

    /// @notice Invalid Liquidity Vault Controller.
    error FM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2__InvalidLiquidityVaultController(
        address invalidLiquidityVaultController
    );

    /// @notice Seize cannot be bigger than MAX_SEIZE = 1%.
    error FM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2__InvalidSeize(
        uint64 seize
    );

    /// @notice Amount exeeds the seizable amount, defined by a percentage of
    ///         total collateral.
    error FM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2__InvalidSeizeAmount(
        uint amount
    );

    /// @notice Timestamp is still in the future, so a seize is not allowed.
    error FM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2__SeizeTimeout(
        uint allowedTimestamp
    );

    // ========================================================================
    // Events

    /// @notice Emits when the collateral has been seized, with the amount.
    event CollateralSeized(uint amount);

    /// @notice Emits when seize percentage gets updated.
    event SeizeChanged(uint64 currentSeize, uint64 newSeize);

    /// @notice Emits when Liquidity Vault Controller gets updated.
    event LiquidityVaultControllerChanged(
        address newLiquidityVaultController, address oldLiquidityVaultController
    );

    /// @notice Emits when the token vault gets updated.
    event TokenVaultSet(address tokenVault);

    /// @notice Emits when buy and sell restriction is removed.
    event BuyAndSellIsUnrestricted();

    // ========================================================================
    // Public Getter Functions

    /// @notice Compute how many tokens can be seized based on `currentSeize`
    ///         and token balance.
    /// @return amount_ Maximum number of tokens that can be seized.
    function getSeizableAmount() external view returns (uint amount_);

    /// @notice Returns the current seize percentage, which is seizable from
    ///         the contract.
    /// @return currentSeize_ The current seize percentage.
    function getCurrentSeize() external view returns (uint64 currentSeize_);

    /// @notice Returns the address of the liquidity vault controller.
    /// @return liquidityVaultController_ The address of the liquidity vault
    ///         controller.
    function getLiquidityVaultController()
        external
        view
        returns (address liquidityVaultController_);

    /// @notice Returns the last timestamp when the seize percentage was
    ///         updated.
    /// @return lastSeizeTimestamp_ The last timestamp when the seize
    ///         percentage was updated.
    function getLastSeizeTimestamp()
        external
        view
        returns (uint lastSeizeTimestamp_);

    /// @notice Returns the address of the token vault.
    /// @return tokenVault_ The address of the token vault.
    function getTokenVault() external view returns (address tokenVault_);

    // ========================================================================
    // Public Mutating Functions

    // -------------------------------------------------------------------------
    // Mutating - Permissioned Functions

    /// @notice Burn amount of tokens from message sender.
    /// @dev    Function access controlled by authorizer.
    /// @param  amount_ Amount token to be burned.
    function burnIssuanceToken(uint amount_) external;

    /// @notice Burn `amount` tokens belonging to `owner`.
    /// @dev    Function access controlled by authorizer.
    /// @param  owner_ Address whose tokens will be burnt.
    /// @param  amount_ Burn amount.
    function burnIssuanceTokenFor(address owner_, uint amount_) external;

    /// @notice Seizes assets from this pool.
    /// @dev    Function access controlled by authorizer.
    /// @dev    This function has a timelock and max.
    ///         seizable percentage to prevent rugging the projects.
    /// @param  amount_ Number of tokens to be removed from the pool.
    function seize(uint amount_) external;

    /// @notice Adjust the seize percentage, which is seizable from the
    ///         contract.
    /// @dev    Function access controlled by authorizer.
    /// @param  seize_ The seize in percentage, expressed as BPS.
    function adjustSeize(uint64 seize_) external;

    /// @notice Sets a new liquidity valut controller address.
    /// @dev    Function access controlled by authorizer.
    /// @param  lvc_ Address of the liquidity vault controller.
    function setLiquidityVaultControllerContract(address lvc_) external;

    /// @notice Sets the Repayable amount.
    /// @dev    Function access controlled by authorizer.
    /// @param  amount_ The new Repayable amount.
    function setRepayableAmount(uint amount_) external;

    /// @notice Sets the token vault address.
    /// @dev    Function access controlled by authorizer.
    /// @param  tokenVault_ The address of the token vault.
    function setTokenVault(address tokenVault_) external;
}
