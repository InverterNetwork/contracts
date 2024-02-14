// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// Internal Dependencies
import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";

// SuT
import {
    ToposBondingCurveFundingManager,
    IToposBondingCurveFundingManager
} from
    "src/modules/fundingManager/bondingCurveFundingManager/ToposBondingCurveFundingManager.sol";
import {Module} from "src/modules/base/Module.sol";

contract ToposBondingCurveFundingManagerMock is
    ToposBondingCurveFundingManager
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
