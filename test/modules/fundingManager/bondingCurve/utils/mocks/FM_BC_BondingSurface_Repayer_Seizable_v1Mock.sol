// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// Internal Dependencies
import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";

// SuT
import {
    FM_BC_BondingSurface_Repayer_Seizable_v1,
    IFM_BC_BondingSurface_Repayer_Seizable_v1
} from
    "src/modules/fundingManager/bondingCurve/FM_BC_BondingSurface_Repayer_Seizable_v1.sol";
import {Module} from "src/modules/base/Module.sol";

contract FM_BC_BondingSurface_Repayer_Seizable_v1Mock is
    FM_BC_BondingSurface_Repayer_Seizable_v1
{
    //--------------------------------------------------------------------------
    // The goal of this mock is to provide direct access to internal functions for testing purposes.

    //--------------------------------------------------------------------------
    // Mock access for internal functions

    function call_getSmallerCaCr() external view returns (uint) {
        return _getSmallerCaCr();
    }

    function call_getRepayableAmount() external view returns (uint) {
        return _getRepayableAmount();
    }

    function call_updateVariables() external {
        _updateVariables();
    }

    function call__getRepayableAmount() external view returns (uint) {
        return _getRepayableAmount();
    }

    function call_calculateBasePriceToCapitalRatio(
        uint _capitalRequired,
        uint _basePriceMultiplier
    ) external pure returns (uint) {
        return _calculateBasePriceToCapitalRatio(
            _capitalRequired, _basePriceMultiplier
        );
    }

    function call_getCapitalAvailable() external view returns (uint) {
        return _getCapitalAvailable();
    }

    function call_setCapitalRequired(uint _newCapitalRequired) external {
        _setCapitalRequired(_newCapitalRequired);
    }

    function call_setBasePriceMultiplier(uint _newBasePriceMultiplier)
        external
    {
        _setBasePriceMultiplier(_newBasePriceMultiplier);
    }

    function call_setSeize(uint64 _seize) external {
        _setSeize(_seize);
    }

    function call_issueTokensFormulaWrapper(uint _depositAmount)
        external
        view
        returns (uint)
    {
        return _issueTokensFormulaWrapper(_depositAmount);
    }

    function call_redeemTokensFormulaWrapper(uint _depositAmount)
        external
        view
        returns (uint)
    {
        return _redeemTokensFormulaWrapper(_depositAmount);
    }

    function call_mintIssuanceTokenToAddressHelper(
        address _account,
        uint _amount
    ) public {
        _mint(_account, _amount);
    }
}
