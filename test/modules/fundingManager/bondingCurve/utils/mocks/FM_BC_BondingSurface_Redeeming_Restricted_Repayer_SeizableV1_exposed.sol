// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// Internal Dependencies
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";

// SuT
import {
    FM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1,
    IFM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1
} from
    "@fm/bondingCurve/FM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol";

contract FM_BC_BondingSurface_Redeeming_Restricted_Repayer_SeizableV1_exposed is
    FM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1
{
    //--------------------------------------------------------------------------
    // The goal of this mock is to provide direct access to internal functions for testing purposes.

    //--------------------------------------------------------------------------
    // Mock access for modifiers

    function exposed_onlyLiquidityVaultControllerModifier()
        external
        onlyLiquidityVaultController
    {}

    //--------------------------------------------------------------------------
    // Mock access for internal functions

    function exposed_checkBuyAndSellRestrictionsModifier() external view {
        _checkBuyAndSellRestrictionsModifier();
    }

    function exposed_getRepayableAmount() external view returns (uint) {
        return _getRepayableAmount();
    }

    function exposed_getCapitalAvailable() external view returns (uint) {
        return _getCapitalAvailable();
    }

    function exposed_setSeize(uint64 _seize) external {
        _setSeize(_seize);
    }

    function exposed_setTokenVault(address _tokenVault) external {
        _setTokenVault(_tokenVault);
    }

    function exposed_getSmallerCaCr() external view returns (uint) {
        return _getSmallerCaCr();
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

    function exposed_projectFeeCollected(uint _workflowFeeAmount) external {
        _projectFeeCollected(_workflowFeeAmount);
    }
}
