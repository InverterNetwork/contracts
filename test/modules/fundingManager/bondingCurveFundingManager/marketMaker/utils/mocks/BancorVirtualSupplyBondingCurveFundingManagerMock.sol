// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// Internal Dependencies
import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";

// SuT
import {
    BancorVirtualSupplyBondingCurveFundingManager,
    IBancorVirtualSupplyBondingCurveFundingManager
} from
    "src/modules/fundingManager/bondingCurveFundingManager/BancorVirtualSupplyBondingCurveFundingManager.sol";
import {IBancorFormula} from
    "src/modules/fundingManager/bondingCurveFundingManager/formula/IBancorFormula.sol";
import {Module} from "src/modules/base/Module.sol";

contract BancorVirtualSupplyBondingCurveFundingManagerMock is
    BancorVirtualSupplyBondingCurveFundingManager
{
    //--------------------------------------------------------------------------
    // The BancorVirtualSupplyBondingCurveFundingManager is not abstract, so all the necessary functions are already implemented
    // The goal of this mock is to provide direct access to internal functions for testing purposes.


    //--------------------------------------------------------------------------
    // Mock access for internal functions

    function call_BPS() external pure returns (uint) {
        return BPS;
    }

    function call_PPM() external pure returns (uint32) {
        return PPM;
    }

    function call_reserveRatioForBuying() external view returns (uint32) {
        return reserveRatioForBuying;
    }

    function call_reserveRatioForSelling() external view returns (uint32) {
        return reserveRatioForSelling;
    }
    function call_convertAmountToRequiredDecimal(
        uint _amount,
        uint8 _tokenDecimals,
        uint8 _requiredDecimals
    ) external pure returns (uint) {
        return _convertAmountToRequiredDecimal(_amount, _tokenDecimals, _requiredDecimals);
    }

}
