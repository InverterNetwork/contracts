// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// Internal Dependencies
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";

// SuT
import {FM_BC_BondingSurface_Redeeming_v1} from
    "@fm/bondingCurve/FM_BC_BondingSurface_Redeeming_v1.sol";
import {Module_v2} from "src/modules/base/Module_v2.sol";

contract FM_BC_BondingSurface_RedeemingV1_Exposed is
    FM_BC_BondingSurface_Redeeming_v1
{
    // -------------------------------------------------------------------------
    // The goal of this mock is to provide direct access to internal functions for testing purposes.

    // -------------------------------------------------------------------------
    // Mock access for internal functions

    function exposed_calculateBasePriceToCapitalRatio(
        uint capitalRequired_,
        uint basePriceMultiplier_
    ) external pure returns (uint) {
        return _calculateBasePriceToCapitalRatio(
            capitalRequired_, basePriceMultiplier_
        );
    }

    function exposed_issueTokensFormulaWrapper(uint depositAmount_)
        external
        view
        returns (uint mintAmount_)
    {
        return _issueTokensFormulaWrapper(depositAmount_);
    }

    function exposed_getCapitalAvailable()
        external
        view
        returns (uint capitalAvailable_)
    {
        return _getCapitalAvailable();
    }

    function exposed_redeemTokensFormulaWrapper(uint depositAmount_)
        external
        view
        returns (uint redeemAmount_)
    {
        return _redeemTokensFormulaWrapper(depositAmount_);
    }

    function exposed_processCollateralTokensForBuyOperation(uint _amount)
        external
    {
        _processCollateralTokensForBuyOperation(_amount);
    }

    function exposed_handleIssuanceTokensAfterBuy(
        address _receiver,
        uint _amount
    ) external {
        _handleIssuanceTokensAfterBuy(_receiver, _amount);
    }

    function exposed_handleCollateralTokensAfterSell(
        address _receiver,
        uint _amount
    ) external {
        _handleCollateralTokensAfterSell(_receiver, _amount);
    }

    function exposed_setBasePriceMultiplier(uint newBasePriceMultiplier_)
        external
    {
        _setBasePriceMultiplier(newBasePriceMultiplier_);
    }

    function exposed_setCapitalRequired(uint newCapitalRequired_) external {
        _setCapitalRequired(newCapitalRequired_);
    }

    function exposed_updateVariables() external {
        _updateVariables();
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

    function exposed_formulaTokenIn(
        uint depositAmount_,
        uint capitalAvailable_,
        uint basePriceToCapitalRatio_
    ) external view returns (uint amount_) {
        return _formula.tokenIn(
            depositAmount_, capitalAvailable_, basePriceToCapitalRatio_
        );
    }
}
