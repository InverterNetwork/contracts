// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

import {
    FM_BC_Bancor_Redeeming_VirtualSupply_v1,
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1,
    FM_BC_Tools
} from "@fm/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";

import {FM_BC_Bancor_Redeeming_VirtualSupply_Native_v1} from
    "@fm/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_Native_v1.sol";

contract FM_BC_Bancor_Redeeming_VirtualSupply_NativeV1Mock is
    FM_BC_Bancor_Redeeming_VirtualSupply_Native_v1
{
    function exposed_reserveRatioForBuying() external view returns (uint32) {
        return reserveRatioForBuying;
    }

    function exposed_reserveRatioForSelling() external view returns (uint32) {
        return reserveRatioForSelling;
    }

    function exposed_collateralTokenDecimals() external view returns (uint8) {
        return collateralTokenDecimals;
    }

    function exposed_convertAmountToRequiredDecimal(
        uint _amount,
        uint8 _tokenDecimals,
        uint8 _requiredDecimals
    ) external pure returns (uint) {
        return FM_BC_Tools._convertAmountToRequiredDecimal(
            _amount, _tokenDecimals, _requiredDecimals
        );
    }

    // Note: this function returns the virtual issuance supply in the same format it will be fed to the Bancor formula
    function exposed_getFormulaVirtualIssuanceSupply()
        external
        view
        returns (uint)
    {
        return FM_BC_Tools._convertAmountToRequiredDecimal(
            virtualIssuanceSupply, issuanceTokenDecimals, 18
        );
    }

    // Note: this function returns the virtual collateral supply in the same format it will be fed to the Bancor formula
    function exposed_getFormulaVirtualCollateralSupply()
        external
        view
        returns (uint)
    {
        return FM_BC_Tools._convertAmountToRequiredDecimal(
            virtualCollateralSupply, collateralTokenDecimals, 18
        );
    }
}
