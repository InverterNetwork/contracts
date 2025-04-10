// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import {FM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "src/modules/fundingManager/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";

import {
    BondingCurveBase_v1,
    IBondingCurveBase_v1
} from "@fm/bondingCurve/abstracts/BondingCurveBase_v1.sol";

import {ICrossChainDispatcher} from "src/exp/CrossChainDispatcher.sol";

contract FM_BC_CC_Bancor_Redeeming_VS_v1 is
    FM_BC_Bancor_Redeeming_VirtualSupply_v1
{
    ICrossChainDispatcher public dispatcher;

    function setDispatcher(address _dispatcher) public virtual {
        require(address(_dispatcher) != address(0), "Invalid dispatcher");
        dispatcher = ICrossChainDispatcher(_dispatcher);
    }

    function buyForCrossChain(
        address _receiver,
        uint _depositAmount,
        uint _minAmountOut,
        uint32 targetChainId
    ) public virtual validReceiver(_receiver) buyingIsEnabled {
        (uint amountIssued, uint collateralFeeAmount) =
            _buyOrder(_receiver, _depositAmount, _minAmountOut);
        _addVirtualIssuanceAmount(amountIssued);
        _addVirtualCollateralAmount(_depositAmount - collateralFeeAmount);

        _mintCrossChain(_receiver, amountIssued, targetChainId);
    }

    function _mintCrossChain(
        address _receiver,
        uint _issuanceTokenAmount,
        uint32 targetChainId
    ) internal virtual {
        dispatcher.dispatchMint(_receiver, _issuanceTokenAmount, targetChainId);
    }

    /// @notice Handles issuance tokens by minting them to the receiver.
    /// @param  _receiver The address that will receive the bought tokens.
    /// @param  _issuanceTokenAmount The amount of issuance tokens to handle.
    function _handleIssuanceTokensAfterBuy(
        address _receiver,
        uint _issuanceTokenAmount
    ) internal virtual override {
        //_mint(_receiver, _issuanceTokenAmount);
    }
}
