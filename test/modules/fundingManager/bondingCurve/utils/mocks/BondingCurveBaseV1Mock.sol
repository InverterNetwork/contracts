// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// Internal Dependencies
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";

// SuT
import {
    BondingCurveBase_v1,
    IBondingCurveBase_v1
} from "@fm/bondingCurve/abstracts/BondingCurveBase_v1.sol";
import {IBancorFormula} from "@fm/bondingCurve/interfaces/IBancorFormula.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

contract BondingCurveBaseV1Mock is BondingCurveBase_v1 {
    IBancorFormula public formula;

    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata);

        // NOTE: The final BancorBondingCurve deploys an issuance token on intialization. or ease of testing, these mocks of the abstract contracts receive the address of a pre-deployed one

        (
            address _issuanceToken,
            address _formula,
            uint _buyFee,
            bool _buyIsOpen
        ) = abi.decode(configData, (address, address, uint, bool));

        _setIssuanceToken(address(_issuanceToken));

        formula = IBancorFormula(_formula);

        _setBuyFee(_buyFee);

        if (_buyIsOpen) _openBuy();
    }

    function _issueTokensFormulaWrapper(uint _depositAmount)
        internal
        pure
        override(BondingCurveBase_v1)
        returns (uint)
    {
        // Since this is a mock, we will always mint the same amount of tokens as have been deposited
        // Integration tests using the actual Formula can be found in the BancorFormulaFundingManagerTest.t.sol
        return _depositAmount;
    }

    function getStaticPriceForBuying()
        external
        view
        override(BondingCurveBase_v1)
        returns (uint)
    {}

    //--------------------------------------------------------------------------
    // Mock access for internal functions

    function call_calculateNetAmountAndFee(uint _depositAmount, uint _feePct)
        external
        pure
        returns (uint, uint)
    {
        return _calculateNetAmountAndFee(_depositAmount, _feePct);
    }

    function call_calculatePurchaseReturn(uint _depositAmount)
        external
        view
        returns (uint)
    {
        return _calculatePurchaseReturn(_depositAmount);
    }

    function call_withdrawProjectCollateralFee(address _receiver, uint _amount)
        public
    {
        _withdrawProjectCollateralFee(_receiver, _amount);
    }

    function call_BPS() external pure returns (uint) {
        return BPS;
    }

    function call_buyOrder(
        address _receiver,
        uint _depositAmount,
        uint _minAmountOut
    )
        external
        returns (uint totalIssuanceTokenMinted, uint collateralFeeAmount)
    {
        return _buyOrder(_receiver, _depositAmount, _minAmountOut);
    }

    function call_processProtocolFeeViaTransfer(
        address _treasury,
        IERC20 _token,
        uint _feeAmount
    ) external {
        _processProtocolFeeViaTransfer(_treasury, _token, _feeAmount);
    }

    function call_processProtocolFeeViaMinting(
        address _treasury,
        uint _feeAmount
    ) external {
        _processProtocolFeeViaMinting(_treasury, _feeAmount);
    }

    function call_getBuyFeesAndTreasuryAddresses()
        external
        view
        returns (
            address collateralTreasury,
            address issuanceTreasury,
            uint collateralBuyFeePercentage,
            uint issuanceBuyFeePercentage
        )
    {
        return _getBuyFeesAndTreasuryAddresses();
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

    // Since the init calls are not registered for coverage, we call expose setIssuanceToken to get to 100% test coverage.
    function call_setIssuanceToken(address _newIssuanceToken) external {
        _setIssuanceToken(_newIssuanceToken);
    }

    //--------------------------------------------------------------------------
    // Helper function

    function setProjectCollateralFeeCollectedHelper(uint _amount) external {
        projectCollateralFeeCollected = _amount;
    }
}
