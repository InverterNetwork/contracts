// SPDX-License-Identifier: LGPL-3.0-only

pragma solidity 0.8.19;

interface IMarketMaker {
    /// @dev this interface is WIP

    function addCollateralToken(address _collateral) external;

    function removeCollateralToken(address _collateral) external;

    function buyOrder(uint amount) external;

    function sellOrder(uint amount) external;
}
