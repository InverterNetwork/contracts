// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// Internal Dependencies
import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";

// SuT
import {
    BondingCurveFundingManagerBase,
    IBondingCurveFundingManagerBase
} from
    "src/modules/fundingManager/bondingCurveFundingManager/BondingCurveFundingManagerBase.sol";
import {IBancorFormula} from
    "src/modules/fundingManager/bondingCurveFundingManager/formula/IBancorFormula.sol";
import {Module} from "src/modules/base/Module.sol";
import {IFundingManager} from "src/modules/fundingManager/IFundingManager.sol";
// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

contract BondingCurveFundingManagerMock is BondingCurveFundingManagerBase {
    IBancorFormula public formula;

    function init(
        IOrchestrator orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override(Module) initializer {
        __Module_init(orchestrator_, metadata);

        (
            bytes32 _name,
            bytes32 _symbol,
            uint8 _decimals,
            address _formula,
            uint _buyFee,
            bool _buyIsOpen
        ) = abi.decode(
            configData, (bytes32, bytes32, uint8, address, uint, bool)
        );

        __ERC20_init(
            string(abi.encodePacked(_name)), string(abi.encodePacked(_symbol))
        );

        formula = IBancorFormula(_formula);

        _setTokenDecimals(_decimals);

        _setBuyFee(_buyFee);

        if (_buyIsOpen == true) _openBuy();
    }

    function _issueTokensFormulaWrapper(uint _depositAmount)
        internal
        pure
        override(BondingCurveFundingManagerBase)
        returns (uint)
    {
        // Since this is a mock, we will always mint the same amount of tokens as have been deposited
        // Integration tests using the actual Formula can be found in the BancorFormulaFundingManagerTest.t.sol
        return _depositAmount;
    }

    function getStaticPriceForBuying()
        external
        view
        override(BondingCurveFundingManagerBase)
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

    function call_BPS() external pure returns (uint) {
        return BPS;
    }

    // Since the init calls are not registered for coverage, we call expose setDecimals to get to 100% test coverage.
    function call_setDecimals(uint8 _newDecimals) external {
        _setTokenDecimals(_newDecimals);
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
        uint _projectFee
    )
        external
        pure
        returns (uint netAmount, uint protocolFeeAmount, uint projectFeeAmount)
    {
        return
            _calculateNetAndSplitFees(_totalAmount, _protocolFee, _projectFee);
    }

    //--------------------------------------------------------------------------
    // Will be removed once we update base fundingManager

    /// @inheritdoc IFundingManager
    function token() public view returns (IERC20) {
        return __Module_orchestrator.fundingManager().token();
    }
}
