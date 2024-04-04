// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// Internal Dependencies
import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";

// SuT
import {
    RedeemingBondingCurveBase,
    IRedeemingBondingCurveBase
} from
    "src/modules/fundingManager/bondingCurve/abstracts/RedeemingBondingCurveBase.sol";
import {BondingCurveBase} from
    "src/modules/fundingManager/bondingCurve/abstracts/BondingCurveBase.sol";

import {IBancorFormula} from
    "src/modules/fundingManager/bondingCurve/interfaces/IBancorFormula.sol";
import {Module} from "src/modules/base/Module.sol";
import {IFundingManager} from "src/modules/fundingManager/IFundingManager.sol";
// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

contract RedeemingBondingCurveBaseMock is RedeemingBondingCurveBase {
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
            bool _buyIsOpen,
            bool _sellIsOpen
        ) = abi.decode(
            configData, (bytes32, bytes32, uint8, address, uint, bool, bool)
        );

        __ERC20_init(
            string(abi.encodePacked(_name)), string(abi.encodePacked(_symbol))
        );

        formula = IBancorFormula(_formula);

        _setTokenDecimals(_decimals);

        _setBuyFee(_buyFee);

        if (_buyIsOpen == true) _openBuy();

        if (_sellIsOpen == true) _openSell();
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
        override(RedeemingBondingCurveBase)
        returns (uint)
    {
        // Since this is a mock, we will always redeem the same amount of tokens as have been deposited
        // Integration tests using the actual Formula can be found in the BancorFormulaFundingManagerTest.t.sol
        return _depositAmount;
    }

    function getStaticPriceForSelling()
        external
        view
        override(RedeemingBondingCurveBase)
        returns (uint)
    {}

    function getStaticPriceForBuying()
        external
        view
        override(BondingCurveBase)
        returns (uint)
    {}

    //--------------------------------------------------------------------------
    // Mock access for internal functions

    function call_BPS() external pure returns (uint) {
        return BPS;
    }

    //--------------------------------------------------------------------------
    // Will be removed once we update base fundingManager

    /// @inheritdoc IFundingManager
    function token() public view returns (IERC20) {
        return __Module_orchestrator.fundingManager().token();
    }
}
