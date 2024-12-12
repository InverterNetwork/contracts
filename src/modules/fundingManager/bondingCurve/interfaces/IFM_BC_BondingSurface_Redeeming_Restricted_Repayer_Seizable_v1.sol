// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

//Internal Dependencies
import {IFM_BC_BondingSurface_Redeeming_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_BondingSurface_Redeeming_v1.sol";
import {IRepayer_v1} from "@fm/bondingCurve/interfaces/IRepayer_v1.sol";
import {ILiquidityVaultController_v1} from
    "@lm/interfaces/ILiquidityVaultController_v1.sol";

/**
 * @title   Inverter Redeeming Restriced Repayer Seizable Bonding Surface Bonding Curve Funding Manager Interface
 *
 * @notice  This interface enables the fetching and setting of Bonding Surface relevant data
 *          with the added functionalities Restricted and Seizable
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @custom:version v1.0.0
 *
 * @custom:inverter-standard-version 0.1.0
 *
 * @author  Inverter Network
 */
interface IFM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1 is
    IFM_BC_BondingSurface_Redeeming_v1,
    IRepayer_v1
{
    //@note Should this maybe be IFM_BC_BondingSurface_Redeeming_Restricted_Seizable_v1 ? repayer is included in different Interface right?
    // -------------------------------------------------------------------------
    // Errors

    /// @notice Invalid address passed as argument
    error FM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1__InvalidInputAddress(
    );

    /// @notice Buy fee can not be set.
    error FM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1__InvalidFunctionality(
    );

    /// @notice Invalid Liquidity Vault Controller
    error FM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1__InvalidLiquidityVaultController(
        address invalidLiquidityVaultController
    );

    /// @notice Seize cannot be bigger than MAX_SEIZE = 1%
    error FM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1__InvalidSeize(
        uint64 seize
    );

    /// @notice Amount exeeds the seizable amount, defined by a percentage of total collateral
    error FM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1__InvalidSeizeAmount(
        uint amount
    );

    /// @notice Timestamp is still in the future, so a seize is not allowed
    error FM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1__SeizeTimeout(
        uint allowedTimestamp
    );

    // -------------------------------------------------------------------------
    // Events

    /// @notice Emits when the collateral has been seized, with the amount
    event CollateralSeized(uint amount);

    /// @notice Emits when seize percentage gets updated
    event SeizeChanged(uint64 currentSeize, uint64 newSeize);

    /// @notice Emits when Liquidity Vault Controller gets updated
    event LiquidityVaultControllerChanged(
        address newLiquidityVaultController, address oldLiquidityVaultController
    );

    /// @notice Emits when the token vault gets updated
    event TokenVaultSet(address tokenVault);

    /// @notice Emits when buy and sell restriction is set.
    event BuyAndSellIsRestricted();

    /// @notice Emits when buy and sell restriction is removed.
    event BuyAndSellIsUnrestricted();

    // ========================================================================
    // Public Getter Functions

    /// @notice  Compute how many tokens can be seized based on `currentSeize` and token balance.
    /// @return amount_ Maximum number of tokens that can be seized
    function getSeizableAmount() external view returns (uint amount_);

    /// @notice Returns the current seize percentage, which is seizable from the contract
    /// @return currentSeize_ The current seize percentage
    function getCurrentSeize() external view returns (uint64 currentSeize_);

    /// @notice Returns the address of the liquidity vault controller
    /// @return liquidityVaultController_ The address of the liquidity vault controller
    function getLiquidityVaultController()
        external
        view
        returns (address liquidityVaultController_);

    /// @notice Returns the last timestamp when the seize percentage was updated
    /// @return lastSeizeTimestamp_ The last timestamp when the seize percentage was updated
    function getLastSeizeTimestamp()
        external
        view
        returns (uint lastSeizeTimestamp_);

    /// @notice Returns the address of the token vault
    /// @return tokenVault_ The address of the token vault
    function getTokenVault() external view returns (address tokenVault_);

    /// @notice Returns whether buy and sell is restricted
    /// @return buyAndSellIsRestricted_ Whether buy and sell is restricted
    function isBuyAndSellRestricted()
        external
        view
        returns (bool buyAndSellIsRestricted_);

    // ========================================================================
    // Public Mutating Functions

    // Mutating - Token Manipulation Functions

    /// @notice Burn amount of tokens from message sender
    /// @param amount_ Amount token to be burned
    function burnIssuanceToken(uint amount_) external;

    /// @notice Burn `amount` tokens belonging to `owner`
    /// @param owner_ Address whose tokens will be burnt
    /// @param amount_ Burn amount
    function burnIssuanceTokenFor(address owner_, uint amount_) external;

    // -------------------------------------------------------------------------
    // Mutating - OnlyCoverManager Functions

    /// @notice Restricts buying and selling functionalities to the CURVE_INTERACTION_ROLE.
    /// @dev    Only callable by the COVER_MANAGER_ROLE.
    function restrictBuyAndSell() external;

    /// @notice Unrestricts buying and selling functionalities to the CURVE_INTERACTION_ROLE.
    /// @dev    Only callable by the COVER_MANAGER_ROLE.
    function unrestrictBuyAndSell() external;

    /// @notice Allows the COVER_MANAGER_ROLE to seize assets from this pool.
    /// @dev As the COVER_MANAGER_ROLE has ability to basically rug the projects, a timelock and max
    /// seizable percentage has been added
    /// @param amount_ Number of tokens to be removed from the pool
    function seize(uint amount_) external;

    /// @notice Adjust the seize percentage, which is seizable from the contract
    /// @param seize_ The seize in percentage, expressed as BPS
    function adjustSeize(uint64 seize_) external;

    /// @notice Sets a new liquidity valut controller address
    /// @param lp_ Address of the liquidity vault controller
    function setLiquidityVaultControllerContract(
        ILiquidityVaultController_v1 lp_
    ) external;

    // -------------------------------------------------------------------------
    // Mutating - OnlyOrchestratorAdmin Functions

    /// @notice Sets the token vault address.
    /// @dev    Only callable by OrchestratorAdmin
    /// @param tokenVault_ The address of the token vault.
    function setTokenVault(address tokenVault_) external;
}
