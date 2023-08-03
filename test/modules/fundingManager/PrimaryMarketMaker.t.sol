// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {PrimaryMarketMaker} from
    "src/modules/fundingManager/bondingCurve/PrimaryMarketMaker.sol";
import {BancorFormula} from
    "src/modules/fundingManager/bondingCurve/BancorFormula.sol";

contract PrimaryMarketMakerTest is Test {
    PrimaryMarketMaker marketMaker;
    BancorFormula formula;
    address fundingManagerMock;

    function setUp() public {
        fundingManagerMock = address(this);
        formula = new BancorFormula();
        marketMaker =
            new PrimaryMarketMaker(fundingManagerMock, address(formula));
    }

    function testOnlyControllerFail(address _invalid) public {
        vm.assume(_invalid != fundingManagerMock);
        vm.prank(_invalid);
        vm.expectRevert();
        marketMaker.buyOrder(0);
    }

    function testOnlyControllerSuccess() public {
        marketMaker.buyOrder(0);
    }
}
