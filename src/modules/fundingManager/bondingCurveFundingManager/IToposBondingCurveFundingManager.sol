// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {ILiquidityPool} from
    "src/modules/logicModule/liquidityPool/ILiquidityPool.sol";

interface IToposBondingCurveFundingManager {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Amount does not match the requirements
    error ToposBondingCurveFundingManager__InvalidInputAmount();

    /// @notice Invalid address passed as argument
    error ToposBondingCurveFundingManager__InvalidInputAddress();

    /// @notice Only set liquidity pool address can call this function
    error ToposBondingCurveFundingManager__InvalidLiquidityPool(address caller);

    //--------------------------------------------------------------------------
    // Events

    //--------------------------------------------------------------------------
    // Structs

    struct IssuanceToken {
        bytes32 name; // The name of the issuance token
        bytes32 symbol; // The symbol of the issuance token
        uint8 decimals; // The decimals used within the issuance token
    }

    struct BondingCurveProperties {
        uint capitalRequirements;
    }

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Sets a new liquidity pool address
    /// @param _lp Address of the liquidity pool
    function setLiquidityPoolContract(ILiquidityPool _lp) external;
}
