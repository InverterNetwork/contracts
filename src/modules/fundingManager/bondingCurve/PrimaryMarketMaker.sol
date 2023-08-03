// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

import {BancorFormula} from
    "src/modules/fundingManager/bondingCurve/BancorFormula.sol";
import {IMarketMaker} from
    "src/modules/fundingManager/bondingCurve/IMarketMaker.sol";

contract PrimaryMarketMaker is IMarketMaker {
    error OnlyController();

    address controller;
    BancorFormula formula;

    modifier onlyController() {
        if (msg.sender != controller) revert OnlyController();
        _;
    }

    constructor(address _controller, address _formula) {
        controller = _controller;
        formula = BancorFormula(_formula);
    }

    function buyOrder(uint amount) external onlyController {
        // Do Something
    }

    function sellOrder(uint amount) external onlyController {
        // Do Something Here
    }
    function removeCollateralToken(address _collateral)
        external
        onlyController
    {
        // Do something here
    }
    function addCollateralToken(address _collateral) external onlyController {
        // Do something here
    }
}
