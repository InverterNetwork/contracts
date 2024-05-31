// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// Internal Dependencies
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";

// SuT
import {
    RedeemingBondingCurveBase_v1,
    IRedeemingBondingCurveBase_v1
} from "@fm/bondingCurve/abstracts/RedeemingBondingCurveBase_v1.sol";
import {BondingCurveBase_v1} from
    "@fm/bondingCurve/abstracts/BondingCurveBase_v1.sol";

import {IBancorFormula} from "@fm/bondingCurve/interfaces/IBancorFormula.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

contract RedeemingBondingCurveBaseV1Mock is RedeemingBondingCurveBase_v1 {
    IBancorFormula public formula;

    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata);

        (
            address _issuanceToken,
            address _formula,
            uint _buyFee,
            bool _buyIsOpen,
            bool _sellIsOpen
        ) = abi.decode(configData, (address, address, uint, bool, bool));

        _setIssuanceToken(_issuanceToken);

        formula = IBancorFormula(_formula);

        _setBuyFee(_buyFee);

        if (_buyIsOpen) _openBuy();

        if (_sellIsOpen) _openSell();
    }

    function _issueTokensFormulaWrapper(uint _depositAmount)
        internal
        pure
        override
        returns (uint)
    {
        // Since this is a mock, we will always mint the same amount of tokens as have been deposited
        // Integration tests using the actual Formula can be found in the BancorFormulaFundingManagerTest.t.sol
        return _depositAmount;
    }

    function _redeemTokensFormulaWrapper(uint _depositAmount)
        internal
        pure
        override(RedeemingBondingCurveBase_v1)
        returns (uint)
    {
        // Since this is a mock, we will always redeem the same amount of tokens as have been deposited
        // Integration tests using the actual Formula can be found in the BancorFormulaFundingManagerTest.t.sol
        return _depositAmount;
    }

    function call_calculateSaleReturn(uint _depositAmount)
        external
        view
        returns (uint)
    {
        return _calculateSaleReturn(_depositAmount);
    }

    function getStaticPriceForSelling()
        external
        view
        override(RedeemingBondingCurveBase_v1)
        returns (uint)
    {}

    function getStaticPriceForBuying()
        external
        view
        override(BondingCurveBase_v1)
        returns (uint)
    {}

    //--------------------------------------------------------------------------
    // Mock access for internal functions

    function call_BPS() external pure returns (uint) {
        return BPS;
    }

    function call_sellOrder(
        address _receiver,
        uint _depositAmount,
        uint _minAmountOut
    )
        external
        returns (uint totalCollateralTokenMovedOut, uint issuanceFeeAmount)
    {
        return _sellOrder(_receiver, _depositAmount, _minAmountOut);
    }

    function call_getSellFeesAndTreasuryAddresses()
        external
        view
        returns (
            address collateralTreasury,
            address issuanceTreasury,
            uint collateralSellFeePercentage,
            uint issuanceSellFeePercentage
        )
    {
        return _getSellFeesAndTreasuryAddresses();
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
}
