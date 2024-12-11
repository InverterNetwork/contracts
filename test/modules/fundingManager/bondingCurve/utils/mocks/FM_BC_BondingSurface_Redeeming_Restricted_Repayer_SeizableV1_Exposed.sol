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

contract FM_BC_BondingSurface_Redeeming_Restricted_Repayer_SeizableV1_Exposed is
    FM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1
{
    // -------------------------------------------------------------------------
    // The goal of this mock is to provide direct access to internal functions for testing purposes.

    // -------------------------------------------------------------------------
    // Mock access for modifiers

    function exposed_onlyLiquidityVaultControllerModifier()
        external
        onlyLiquidityVaultController
    {}

    // -------------------------------------------------------------------------
    // Mock access for internal functions

    function exposed_checkBuyAndSellRestrictionsModifier() external view {
        _checkBuyAndSellRestrictionsModifier();
    }

    function exposed_getRepayableAmount()
        external
        view
        returns (uint repayableAmount_)
    {
        return _getRepayableAmount();
    }

    function exposed_getCapitalAvailable()
        external
        view
        returns (uint capitalAvailable_)
    {
        return _getCapitalAvailable();
    }

    function exposed_setSeize(uint64 seize_) external {
        _setSeize(seize_);
    }

    function exposed_setTokenVault(address tokenVault_) external {
        _setTokenVault(tokenVault_);
    }

    function exposed_getSmallerCaCr()
        external
        view
        returns (uint smallerCaCr_)
    {
        return _getSmallerCaCr();
    }

    function exposed_mint(address account_, uint amount_) external {
        _mint(account_, amount_);
    }

    function exposed_projectCollateralFeeCollected(uint amount_)
        external
        returns (uint projectCollateralFeeCollected_)
    {
        return projectCollateralFeeCollected = amount_;
    }

    function exposed_projectFeeCollected(uint workflowFeeAmount_) external {
        _projectFeeCollected(workflowFeeAmount_);
    }
}
