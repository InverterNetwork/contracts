// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {ILiquidityVaultController} from
    "@lm/interfaces/ILiquidityVaultController.sol";

interface IFM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1 {
    //--------------------------------------------------------------------------
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

    //--------------------------------------------------------------------------
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

    //--------------------------------------------------------------------------
    // Getter Functions

    /// @notice  Compute how many tokens can be seized based on `currentSeize` and token balance.
    /// @return amount Maximum number of tokens that can be seized
    function getSeizableAmount() external view returns (uint amount);

    /// @notice Returns the current seize percentage, which is seizable from the contract
    /// @return currentSeize The current seize percentage
    function getCurrentSeize() external view returns (uint64 currentSeize);

    /// @notice Returns the address of the liquidity vault controller
    /// @return liquidityVaultController The address of the liquidity vault controller
    function getLiquidityVaultController()
        external
        view
        returns (address liquidityVaultController);

    /// @notice Returns the last timestamp when the seize percentage was updated
    /// @return lastSeizeTimestamp The last timestamp when the seize percentage was updated
    function getLastSeizeTimestamp()
        external
        view
        returns (uint lastSeizeTimestamp);

    /// @notice Returns the address of the token vault
    /// @return tokenVault The address of the token vault
    function getTokenVault() external view returns (address tokenVault);

    /// @notice Returns whether buy and sell is restricted
    /// @return buyAndSellIsRestricted Whether buy and sell is restricted
    function isBuyAndSellRestricted()
        external
        view
        returns (bool buyAndSellIsRestricted);
    //--------------------------------------------------------------------------
    // Mutating Functions

    /// @notice Sets a new liquidity valut controller address
    /// @param lp_ Address of the liquidity vault controller
    function setLiquidityVaultControllerContract(ILiquidityVaultController lp_)
        external;

    /// @notice Adjust the seize percentage, which is seizable from the contract
    /// @param seize_ The seize in percentage, expressed as BPS
    function adjustSeize(uint64 seize_) external;

    /// @notice Allows the COVER_MANAGER_ROLE to seize assets from this pool.
    /// @dev As the COVER_MANAGER_ROLE has ability to basically rug the projects, a timelock and max
    /// seizable percentage has been added
    /// @param amount_ Number of tokens to be removed from the pool
    function seize(uint amount_) external;

    /// @notice Burn amount of tokens from message sender
    /// @param amount_ Amount token to be burned
    function burnIssuanceToken(uint amount_) external;

    /// @notice Burn `amount` tokens belonging to `owner`
    /// @param owner_ Address whose tokens will be burnt
    /// @param amount_ Burn amount
    function burnIssuanceTokenFor(address owner_, uint amount_) external;

    /// @notice Restricts buying and selling functionalities to the CURVE_INTERACTION_ROLE.
    /// @dev    Only callable by the COVER_MANAGER_ROLE.
    function restrictBuyAndSell() external;

    /// @notice Unrestricts buying and selling functionalities to the CURVE_INTERACTION_ROLE.
    /// @dev    Only callable by the COVER_MANAGER_ROLE.
    function unrestrictBuyAndSell() external;

    /// @notice Sets the token vault address.
    /// @dev    Only callable by OrchestratorAdmin
    /// @param tokenVault_ The address of the token vault.
    function setTokenVault(address tokenVault_) external;
}
