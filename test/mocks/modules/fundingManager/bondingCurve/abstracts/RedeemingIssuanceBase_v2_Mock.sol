// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// Internal Dependencies
import {IOrchestrator_v2} from
    "src/orchestrator/interfaces/IOrchestrator_v2.sol";

// SuT
import {
    RedeemingIssuanceBase_v2,
    IRedeemingIssuanceBase_v2
} from "@fm/bondingCurve/abstracts/RedeemingIssuanceBase_v2.sol";
import {
    IssuanceBase_v2,
    IIssuanceBase_v2
} from "@fm/bondingCurve/abstracts/IssuanceBase_v2.sol";

import {IBancorFormula} from "@fm/bondingCurve/interfaces/IBancorFormula.sol";
import {Module_v2} from "src/modules/base/Module_v2.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

contract RedeemingIssuanceBase_v2_Mock is RedeemingIssuanceBase_v2 {
    IBancorFormula public formula;

    // -------------------------------------------------------------------------
    // Override Functions

    function init(
        IOrchestrator_v2 orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override(Module_v2) initializer {
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

        buyIsOpen = _buyIsOpen;

        sellIsOpen = _sellIsOpen;
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
        override(RedeemingIssuanceBase_v2)
        returns (uint)
    {
        // Since this is a mock, we will always redeem the same amount of tokens as have been deposited
        // Integration tests using the actual Formula can be found in the BancorFormulaFundingManagerTest.t.sol
        return _depositAmount;
    }

    uint public distributeIssuanceTokenFunctionCalled;

    function _handleIssuanceTokensAfterBuy(
        address _receiver,
        uint _issuanceTokenAmount
    ) internal virtual override {
        _mint(_receiver, _issuanceTokenAmount);
        distributeIssuanceTokenFunctionCalled++;
    }

    uint public distributeCollateralTokenAfterSellFunctionCalled;

    function _handleCollateralTokensAfterSell(address, uint)
        internal
        virtual
        override
    {
        distributeCollateralTokenAfterSellFunctionCalled++;
    }

    uint public processCollateralTokensForBuyOperationFunctionCalled;

    function _processCollateralTokensForBuyOperation(uint /*_amount*/ )
        internal
        virtual
        override
    {
        processCollateralTokensForBuyOperationFunctionCalled++;
    }

    function getStaticPriceForSelling()
        external
        view
        override(RedeemingIssuanceBase_v2)
        returns (uint)
    {}

    function getStaticPriceForBuying()
        external
        view
        override(IssuanceBase_v2, IIssuanceBase_v2)
        returns (uint)
    {}

    // -------------------------------------------------------------------------
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
