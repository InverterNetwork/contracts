// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {ILiquidityVaultController} from
    "@lm/interfaces/ILiquidityVaultController.sol";

interface IFM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1 {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Invalid address passed as argument
    error FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__InvalidInputAddress(
    );

    /// @notice Buy fee can not be set.
    error FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__InvalidFunctionality(
    );

    /// @notice Invalid Liquidity Vault Controller
    error FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__InvalidLiquidityVaultController(
        address invalidLiquidityVaultController
    );

    /// @notice Seize cannot be bigger than MAX_SEIZE = 1%
    error FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__InvalidSeize(
        uint64 seize
    );

    /// @notice Amount exeeds the seizable amount, defined by a percentage of total collateral
    error FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__InvalidSeizeAmount(
        uint amount
    );

    /// @notice Timestamp is still in the future, so a seize is not allowed
    error FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__SeizeTimeout(
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
    // Functions

    /// @notice Sets a new liquidity valut controller address
    /// @param _lp Address of the liquidity vault controller
    function setLiquidityVaultControllerContract(ILiquidityVaultController _lp)
        external;

    /// @notice  Compute how many tokens can be seized based on `currentSeize` and token balance.
    /// @return uint Maximum number of tokens that can be seized
    function seizable() external view returns (uint);

    /// @notice Adjust the seize percentage, which is seizable from the contract
    /// @param _seize The seize in percentage, expressed as BPS
    function adjustSeize(uint64 _seize) external;

    /// @notice Allows the COVER_MANAGER_ROLE to seize assets from this pool.
    /// @dev As the COVER_MANAGER_ROLE has ability to basically rug the projects, a timelock and max
    /// seizable percentage has been added
    /// @param _amount Number of tokens to be removed from the pool
    function seize(uint _amount) external;

    /// @notice Burn amount of tokens from message sender
    /// @param _amount Amount token to be burned
    function burnIssuanceToken(uint _amount) external;

    /// @notice Burn `amount` tokens belonging to `owner`
    /// @param _owner Address whose tokens will be burnt
    /// @param _amount Burn amount
    function burnIssuanceTokenFor(address _owner, uint _amount) external;

    /// @notice Restricts buying and selling functionalities to the CURVE_INTERACTION_ROLE.
    /// @dev    Only callable by the COVER_MANAGER_ROLE.
    function restrictBuyAndSell() external;

    /// @notice Unrestricts buying and selling functionalities to the CURVE_INTERACTION_ROLE.
    /// @dev    Only callable by the COVER_MANAGER_ROLE.
    function unrestrictBuyAndSell() external;

    /// @notice Sets the token vault address.
    /// @dev    Only callable by OrchestratorAdmin
    /// @param _tokenVault The address of the token vault.
    function setTokenVault(address _tokenVault) external;
}
