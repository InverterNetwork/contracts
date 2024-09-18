// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// Internal Dependencies
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";

// SuT
import {
    FM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1,
    IFM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1
} from
    "src/modules/fundingManager/bondingCurve/FM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol";

contract FM_BC_BondingSurface_Redeemable_Repayer_SeizableV1Mock is
    FM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1
{
    //--------------------------------------------------------------------------
    // The goal of this mock is to provide direct access to internal functions for testing purposes.

    //--------------------------------------------------------------------------
    // Mock access for internal functions

    function exposed_getSmallerCaCr() external view returns (uint) {
        return _getSmallerCaCr();
    }

    function exposed_updateVariables() external {
        _updateVariables();
    }

    function exposed_getRepayableAmount() external view returns (uint) {
        return _getRepayableAmount();
    }

    function exposed_calculateBasePriceToCapitalRatio(
        uint _capitalRequired,
        uint _basePriceMultiplier
    ) external pure returns (uint) {
        return _calculateBasePriceToCapitalRatio(
            _capitalRequired, _basePriceMultiplier
        );
    }

    function exposed_getCapitalAvailable() external view returns (uint) {
        return _getCapitalAvailable();
    }

    function exposed_setCapitalRequired(uint _newCapitalRequired) external {
        _setCapitalRequired(_newCapitalRequired);
    }

    function exposed_setBasePriceMultiplier(uint _newBasePriceMultiplier)
        external
    {
        _setBasePriceMultiplier(_newBasePriceMultiplier);
    }

    function exposed_setSeize(uint64 _seize) external {
        _setSeize(_seize);
    }

    function exposed_issueTokensFormulaWrapper(uint _depositAmount)
        external
        view
        returns (uint)
    {
        return _issueTokensFormulaWrapper(_depositAmount);
    }

    function exposed_redeemTokensFormulaWrapper(uint _depositAmount)
        external
        view
        returns (uint)
    {
        return _redeemTokensFormulaWrapper(_depositAmount);
    }

    function exposed_projectCollateralFeeCollected(uint _amount)
        external
        returns (uint)
    {
        return projectCollateralFeeCollected = _amount;
    }

    function exposed_mint(address _account, uint _amount) external {
        _mint(_account, _amount);
    }

    function exposed_isBuyAndSellRestrictedModifier() external view {
        _isBuyAndSellRestrictedModifier();
    }
}
