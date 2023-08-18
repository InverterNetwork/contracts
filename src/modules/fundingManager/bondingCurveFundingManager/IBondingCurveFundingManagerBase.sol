// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

interface IBondingCurveFundingManagerBase {
    function buyOrder(uint _depositAmount) external payable;

    function openBuy() external;

    function closeBuy() external;

    function updateBuyFee(uint _fee) external;
}
