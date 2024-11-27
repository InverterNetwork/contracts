// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// Internal Dependencies
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";

// SuT
import {FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.sol";

import {
    FM_BC_Bancor_Redeeming_VirtualSupply_v1,
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1,
    FM_BC_Tools
} from "@fm/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IBancorFormula} from "@fm/bondingCurve/interfaces/IBancorFormula.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol";

contract FM_BC_Restricted_Bancor_Redeeming_VirtualSupplyV1Mock is
    FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1
{
    // -------------------------------------------------------------------------
    // The FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 is not abstract, so all the necessary functions are already implemented
    // The goal of this mock is to provide direct access to internal functions for testing purposes.

    // -------------------------------------------------------------------------
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

    function call_issuanceTokenDecimals() external view returns (uint8) {
        return issuanceTokenDecimals;
    }

    // Since the init calls are not registered for coverage, we call expose setIssuanceToken to get to 100% test coverage.
    function call_setIssuanceToken(address _newIssuanceToken) external {
        _setIssuanceToken(_newIssuanceToken);
    }
    /*
    function call_staticPricePPM(
        uint _issuanceSupply,
        uint _collateralSupply,
        uint32 _reserveRatio
    ) external pure returns (uint) {
        return
            _staticPricePPM(_issuanceSupply, _collateralSupply, _reserveRatio);
    }
    */

    function call_convertAmountToRequiredDecimal(
        uint _amount,
        uint8 _tokenDecimals,
        uint8 _requiredDecimals
    ) external pure returns (uint) {
        return FM_BC_Tools._convertAmountToRequiredDecimal(
            _amount, _tokenDecimals, _requiredDecimals
        );
    }

    // Note: this function returns the virtual token supply in the same format it will be fed to the Bancor formula
    function call_getFormulaVirtualIssuanceSupply()
        external
        view
        returns (uint)
    {
        uint decimalConvertedVirtualIssuanceSupply = FM_BC_Tools
            ._convertAmountToRequiredDecimal(
            virtualIssuanceSupply, issuanceTokenDecimals, 18
        );
        return decimalConvertedVirtualIssuanceSupply;
    }

    function call_setVirtualIssuanceSupply(uint _newSupply) external {
        _setVirtualIssuanceSupply(_newSupply);
    }

    // Note: this function returns the virtual collateral supply in the same format it will be fed to the Bancor formula
    function call_getFormulaVirtualCollateralSupply()
        external
        view
        returns (uint)
    {
        uint decimalConvertedVirtualCollateralSupply = FM_BC_Tools
            ._convertAmountToRequiredDecimal(
            virtualCollateralSupply, collateralTokenDecimals, 18
        );
        return decimalConvertedVirtualCollateralSupply;
    }

    function call_handleIssuanceTokensAfterBuy(address _receiver, uint _amount)
        external
    {
        _handleIssuanceTokensAfterBuy(_receiver, _amount);
    }

    function call_handleCollateralTokensAfterSell(
        address _receiver,
        uint _amount
    ) external {
        _handleCollateralTokensAfterSell(_receiver, _amount);
    }

    // -------------------------------------------------------------------------
    // Helper Functions

    function setProjectCollateralFeeCollectedHelper(uint _amount) external {
        projectCollateralFeeCollected = _amount;
    }
}
