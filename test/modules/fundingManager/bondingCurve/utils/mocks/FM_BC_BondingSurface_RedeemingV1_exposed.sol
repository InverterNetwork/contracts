// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// Internal Dependencies
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";

// SuT
import {FM_BC_BondingSurface_Redeeming_v1} from
    "@fm/bondingCurve/FM_BC_BondingSurface_Redeeming_v1.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol";

contract FM_BC_BondingSurface_RedeemingV1_exposed is
    FM_BC_BondingSurface_Redeeming_v1
{
    //--------------------------------------------------------------------------
    // The goal of this mock is to provide direct access to internal functions for testing purposes.

    //--------------------------------------------------------------------------
    // Mock access for internal functions

    function exposed_calculateBasePriceToCapitalRatio(
        uint _capitalRequired,
        uint _basePriceMultiplier
    ) external pure returns (uint) {
        return _calculateBasePriceToCapitalRatio(
            _capitalRequired, _basePriceMultiplier
        );
    }

    function exposed_issueTokensFormulaWrapper(uint _depositAmount)
        external
        view
        returns (uint)
    {
        return _issueTokensFormulaWrapper(_depositAmount);
    }

    function exposed_getCapitalAvailable() external view returns (uint) {
        return _getCapitalAvailable();
    }

    function exposed_redeemTokensFormulaWrapper(uint _depositAmount)
        external
        view
        returns (uint)
    {
        return _redeemTokensFormulaWrapper(_depositAmount);
    }

    function exposed_setBasePriceMultiplier(uint _newBasePriceMultiplier)
        external
    {
        _setBasePriceMultiplier(_newBasePriceMultiplier);
    }

    function exposed_setCapitalRequired(uint _newCapitalRequired) external {
        _setCapitalRequired(_newCapitalRequired);
    }

    function exposed_updateVariables() external {
        _updateVariables();
    }

    function exposed_mint(address _account, uint _amount) external {
        _mint(_account, _amount);
    }

    function exposed_projectCollateralFeeCollected(uint _amount)
        external
        returns (uint)
    {
        return projectCollateralFeeCollected = _amount;
    }

    function exposed_formulaTokenIn(
        uint _depositAmount,
        uint _capitalAvailable,
        uint _basePriceToCapitalRatio
    ) external view returns (uint _redeemAmount) {
        return formula.tokenIn(
            _depositAmount, _capitalAvailable, _basePriceToCapitalRatio
        );
    }
}
