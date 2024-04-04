// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// Internal Dependencies
import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";

// SuT
import {
    FM_BC_Bancor_Redeeming_VirtualIssuance_VirtualCollateral_v1,
    IFM_BC_Bancor_Redeeming_VirtualIssuance_VirtualCollateral_v1
} from
    "src/modules/fundingManager/bondingCurve/FM_BC_Bancor_Redeeming_VirtualIssuance_VirtualCollateral_v1.sol";
import {IBancorFormula} from
    "src/modules/fundingManager/bondingCurve/interfaces/IBancorFormula.sol";
import {Module} from "src/modules/base/Module.sol";

contract FM_BC_Bancor_Redeeming_VirtualIssuance_VirtualCollateral_v1Mock is
    FM_BC_Bancor_Redeeming_VirtualIssuance_VirtualCollateral_v1
{
    //--------------------------------------------------------------------------
    // The FM_BC_Bancor_Redeeming_VirtualIssuance_VirtualCollateral_v1 is not abstract, so all the necessary functions are already implemented
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

    function call_collateralTokenDecimals() external view returns (uint8) {
        return collateralTokenDecimals;
    }

    // Since the init calls are not registered for coverage, we call expose setDecimals to get to 100% test coverage.
    function call_setDecimals(uint8 _newDecimals) external {
        _setTokenDecimals(_newDecimals);
    }

    function call_staticPricePPM(
        uint _issuanceTokenSupply,
        uint _collateralSupply,
        uint32 _reserveRatio
    ) external pure returns (uint) {
        return _staticPricePPM(
            _issuanceTokenSupply, _collateralSupply, _reserveRatio
        );
    }

    function call_convertAmountToRequiredDecimal(
        uint _amount,
        uint8 _tokenDecimals,
        uint8 _requiredDecimals
    ) external pure returns (uint) {
        return _convertAmountToRequiredDecimal(
            _amount, _tokenDecimals, _requiredDecimals
        );
    }

    function call_mintIssuanceToken(uint _amount, address _receiver) external {
        _mint(_receiver, _amount);
    }
}
