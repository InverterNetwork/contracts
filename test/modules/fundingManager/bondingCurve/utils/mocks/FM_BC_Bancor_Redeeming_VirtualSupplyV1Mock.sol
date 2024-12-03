// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// Internal Dependencies
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";

// SuT
import {
    FM_BC_Bancor_Redeeming_VirtualSupply_v1,
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1,
    FM_BC_Tools
} from "@fm/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IBancorFormula} from "@fm/bondingCurve/interfaces/IBancorFormula.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol";

contract FM_BC_Bancor_Redeeming_VirtualSupplyV1Mock is
    FM_BC_Bancor_Redeeming_VirtualSupply_v1
{
    // -------------------------------------------------------------------------
    // The FM_BC_Bancor_Redeeming_VirtualSupply_v1 is not abstract, so all the necessary functions are already implemented
    // The goal of this mock is to provide direct access to internal functions for testing purposes.

    // -------------------------------------------------------------------------
    // Override Functions

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

    function call_setVirtualIssuanceSupply(uint _newSupply) external {
        _setVirtualIssuanceSupply(_newSupply);
    }

    function call_convertAmountToRequiredDecimal(
        uint _amount,
        uint8 _tokenDecimals,
        uint8 _requiredDecimals
    ) external pure returns (uint) {
        return FM_BC_Tools._convertAmountToRequiredDecimal(
            _amount, _tokenDecimals, _requiredDecimals
        );
    }

    // Note: this function returns the virtual issuance supply in the same format it will be fed to the Bancor formula
    function call_getFormulaVirtualIssuanceSupply()
        external
        view
        returns (uint)
    {
        return FM_BC_Tools._convertAmountToRequiredDecimal(
            virtualIssuanceSupply, issuanceTokenDecimals, 18
        );
    }

    // Note: this function returns the virtual collateral supply in the same format it will be fed to the Bancor formula
    function call_getFormulaVirtualCollateralSupply()
        external
        view
        returns (uint)
    {
        return FM_BC_Tools._convertAmountToRequiredDecimal(
            virtualCollateralSupply, collateralTokenDecimals, 18
        );
    }

    function call_calculateNetAndSplitFees(
        uint _totalAmount,
        uint _protocolFee,
        uint _workflowFee
    )
        external
        pure
        returns (uint netAmount, uint protocolFeeAmount, uint workflowFeeAmount)
    {
        return
            _calculateNetAndSplitFees(_totalAmount, _protocolFee, _workflowFee);
    }

    function call_handleCollateralTokensBeforeBuy(
        address _provider,
        uint _amount
    ) external {
        _handleCollateralTokensBeforeBuy(_provider, _amount);
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
