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

    function call_updateVariables() external {
        _updateVariables();
    }

    function call__getRepayableAmount() external view returns (uint) {
        return _getRepayableAmount();
    }

    function call_calculateBasePriceToCaptialRatio(
        uint _capitalRequired,
        uint _basePriceMultiplier
    ) external pure returns (uint) {
        return _calculateBasePriceToCaptialRatio(
            _capitalRequired, _basePriceMultiplier
        );
    }

    function call_getCaptialAvailable() external view returns (uint) {
        return _getCaptialAvailable();
    }

    function call_setCaptialRequired(uint _newCapitalRequired) external {
        _setCapitalRequired(_newCapitalRequired);
    }

    function call_setBaseMultiplier(uint _newBasePriceMultiplier) external {
        _setBaseMultiplier(_newBasePriceMultiplier);
    }

    function call_setSeize(uint64 _seize) external {
        _setSeize(_seize);
    }

    function call_issueTokensFormulaWrapper(uint _depositAmount)
        external
        view
        returns (uint)
    {
        return _issueTokensFormulaWrapper(_depositAmount);
    }

    function call_redeemTokensFormulaWrapper(uint _depositAmount)
        external
        view
        returns (uint)
    {
        return _redeemTokensFormulaWrapper(_depositAmount);
    }

    function call_mintIssuanceTokenToAddressHelper(
        address _account,
        uint _amount
    ) public {
        _mint(_account, _amount);
    }
}
