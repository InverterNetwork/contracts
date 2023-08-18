// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

interface IRedeemingBondingCurveFundingManagerBase {
    function sellOrder(uint _depositAmount) external payable;

    function openSell() external;

    function closeSell() external;

    function updateSellFee(uint _fee) external;
}
