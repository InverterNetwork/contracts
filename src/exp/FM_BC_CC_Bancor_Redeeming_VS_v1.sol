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
    /// @notice Thrown when the dispatcher is invalid.
    error InvalidDispatcher();

    /// @notice Thrown when the receiver is invalid.
    error InvalidReceiver();

    /// @notice Thrown when the issuance token amount is invalid.
    error InvalidIssuanceTokenAmount();

    /// @notice Thrown when the target chain ID is invalid.
    error InvalidTargetChainId();

    ICrossChainDispatcher internal _dispatcher;

    event DispatcherSet(address indexed dispatcher_);

    function setDispatcher(address dispatcher_) public virtual {
        if (address(dispatcher_) == address(0)) {
            revert InvalidDispatcher();
        }

        _dispatcher = ICrossChainDispatcher(dispatcher_);

        emit DispatcherSet(dispatcher_);
    }

    function buyForCrossChain(
        address receiver_,
        uint depositAmount_,
        uint minAmountOut_,
        uint32 targetChainId_
    ) public virtual validReceiver(receiver_) buyingIsEnabled {
        if (address(_dispatcher) == address(0)) {
            revert InvalidDispatcher();
        }

        (uint amountIssued, uint collateralFeeAmount) =
            _buyOrder(receiver_, depositAmount_, minAmountOut_);
        _addVirtualIssuanceAmount(amountIssued);
        _addVirtualCollateralAmount(depositAmount_ - collateralFeeAmount);

        _mintCrossChain(receiver_, amountIssued, targetChainId_);
    }

    function _mintCrossChain(
        address receiver_,
        uint issuanceTokenAmount_,
        uint32 targetChainId_
    ) internal virtual {
        if (address(receiver_) == address(0)) {
            revert InvalidReceiver();
        }

        if (issuanceTokenAmount_ == 0) {
            revert InvalidIssuanceTokenAmount();
        }

        if (targetChainId_ == 0) {
            revert InvalidTargetChainId();
        }

        if (address(_dispatcher) == address(0)) {
            revert InvalidDispatcher();
        }

        _dispatcher.dispatchMint(
            receiver_, issuanceTokenAmount_, targetChainId_
        );
    }

    /// @notice Handles issuance tokens by minting them to the receiver.
    /// @param  receiver_ The address that will receive the bought tokens.
    /// @param  issuanceTokenAmount_ The amount of issuance tokens to handle.
    function _handleIssuanceTokensAfterBuy(
        address receiver_,
        uint issuanceTokenAmount_
    ) internal virtual override {
        //_mint(_receiver, _issuanceTokenAmount);
    }
}
