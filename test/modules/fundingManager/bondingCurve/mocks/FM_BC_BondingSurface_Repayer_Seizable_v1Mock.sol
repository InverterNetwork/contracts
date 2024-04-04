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
}
