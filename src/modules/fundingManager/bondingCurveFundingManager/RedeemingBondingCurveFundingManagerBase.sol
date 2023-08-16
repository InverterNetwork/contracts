// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

// Internal Dependencies
// import {Module} from "src/modules/base/Module.sol";
import {BondingCurveFundingManagerBase} from
    "src/modules/fundingManager/bondingCurveFundingManager/BondingCurveFundingManagerBase.sol";
import {IRedeemingBondingCurveFundingManagerBase} from
    "src/modules/fundingManager/bondingCurveFundingManager/IRedeemingBondingCurveFundingManagerBase.sol";

abstract contract RedeemingBondingCurveFundingManagerBase is
    IRedeemingBondingCurveFundingManagerBase,
    BondingCurveFundingManagerBase
{
    //--------------------------------------------------------------------------
    // Storage
    bool public sellIsOpen;
    uint public sellFee;

    //--------------------------------------------------------------------------
    // Public Functions
    function sellOrder(uint _depositAmount) external payable virtual {
        // Q: Deduct fee from token or collateral?
        _redeemTokens(_depositAmount);
    }

    function openSell() external onlyOrchestratorOwnerOrManager {
        // Function to set the PAMM Sell functionality to open
        _openSell();
    }

    function closeSell() external onlyOrchestratorOwnerOrManager {
        // Function to set the PAMM Sell functionality to close
        _closeSell();
    }

    function updateSellFee(uint _fee) external onlyOrchestratorOwnerOrManager {
        // Should update the Sell fee of the contract
        _updateSellFee(_fee);
    }

    //--------------------------------------------------------------------------
    // Internal Functions Implemented in Downstream Contract
    function _redeemTokensFormulaWrapper(uint _depositAmount)
        internal
        virtual
        returns (uint);

    //--------------------------------------------------------------------------
    // Internal Functions

    function _openSell() internal {
        sellIsOpen = true;
    }

    function _closeSell() internal {
        sellIsOpen = false;
    }

    function _updateSellFee(uint _fee) internal {
        sellFee = _fee;
    }

    function _redeemTokens(uint _depositAmount)
        internal
        returns (uint redeemAmount)
    {
        redeemAmount = _redeemTokensFormulaWrapper(_depositAmount);
        // Transfer amount to msg.sender
    }
}
