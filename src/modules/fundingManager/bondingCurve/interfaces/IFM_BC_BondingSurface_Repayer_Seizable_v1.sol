// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {ILiquidityPool} from
    "src/modules/logicModule/liquidityPool/ILiquidityPool.sol";

interface IFM_BC_BondingSurface_Repayer_Seizable_v1 {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Amount does not match the requirements
    error FM_BC_BondingSurface_Repayer_Seizable_v1__InvalidInputAmount();

    /// @notice Invalid address passed as argument
    error FM_BC_BondingSurface_Repayer_Seizable_v1__InvalidInputAddress();

    /// @notice Only set liquidity pool address can call this function
    error FM_BC_BondingSurface_Repayer_Seizable_v1__InvalidLiquidityPool(
        address caller
    );

    /// @notice Seize cannot be bigger than MAX_SEIZE = 1%
    error FM_BC_BondingSurface_Repayer_Seizable_v1__InvalidSeize(uint64 seize);

    /// @notice Fee percentage cannont be higher than ToDO: %
    error FM_BC_BondingSurface_Repayer_Seizable_v1__InvalidFeePercentage(
        uint fee
    );

    /// @notice Amount exeeds the seizable amount, defined by a percentage of total collateral
    error FM_BC_BondingSurface_Repayer_Seizable_v1__InvalidSeizeAmount(
        uint amount
    );

    /// @notice Timestamp is still in the future, so a seize is not allowed
    error FM_BC_BondingSurface_Repayer_Seizable_v1__SeizeTimeout(
        uint allowedTimestamp
    );

    /// @notice No capital is available.
    error FM_BC_BondingSurface_Repayer_Seizable_v1__NoCapitalAvailable();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Emits when the collateral has been seized, with the amount
    event CollateralSeized(uint amount);

    /// @notice Emits when the capital required gets updated
    event CapitalRequiredChanged(
        uint currentCapitalRequired, uint newCapitalRequired
    );

    /// @notice Emits when the Base Price Multiplier gets updated
    event BasePriceMultiplierChanged(
        uint currentBasePriceMultiplier, uint newBasePriceMultiplier
    );

    /// @notice Emits when seize percentage gets updated
    event SeizeChanged(uint64 currentSeize, uint64 newSeize);

    /// @notice Emits when basePriceToCapitalRatio gets updated
    event BasePriceToCapitalRatioChanged(
        uint currentBasePriceToCapitalRatio, uint newBasePriceToCapitalRatio
    );

    //--------------------------------------------------------------------------
    // Structs

    struct IssuanceToken {
        bytes32 name; // The name of the issuance token
        bytes32 symbol; // The symbol of the issuance token
        uint8 decimals; // The decimals used within the issuance token
    }

    struct BondingCurveProperties {
        uint capitalRequired; // The initial capital requirement for the formula contract
        address formula; // The formula contract used to calculate the issucance and redemption rate
        uint buyFee; // The buy fee expressed in base points
        uint sellFee; // The sell fee expressed in base points
        bool buyIsOpen; // The indicator used for enabling/disabling the buying functionalities on deployment
        bool sellIsOpen; // The indicator used for enabling/disabling the selling functionalties on deployment
        uint64 seize; // The current seize percentage expresses in BPS
        uint basePriceMultiplier; // Base price multiplier in the bonding curve formula
    }

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Sets a new liquidity pool address
    /// @param _lp Address of the liquidity pool
    function setLiquidityPoolContract(ILiquidityPool _lp) external;

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

    /// @dev Update the base price multiplier used for the bonding curve
    /// @param _newBasePriceMultiplier Base price multiplier used for price calculation
    function setBasePriceMultiplier(uint _newBasePriceMultiplier) external;

    /// @dev Update the capital required used for the bonding curve
    /// @param _newCapitalRequired Capital required needed to operate the protocol
    function setCapitalRequired(uint _newCapitalRequired) external;

    /// @notice Burn amount of tokens from message sender
    /// @param _amount Amount token to be burned
    function burnIssuanceToken(uint _amount) external;

    /// @notice Burn `amount` tokens belonging to `owner`
    /// @param _owner Address whose tokens will be burnt
    /// @param _amount Burn amount
    function burnIssuanceTokenFor(address _owner, uint _amount) external;

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
