// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

//Internal Dependencies
import {ModuleTest, IModule, IOrchestrator} from "test/modules/ModuleTest.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

// SuT
import {
    BondingCurveFundingManager,
    IFundingManager
} from "src/modules/fundingManager/BondingCurveFundingManager.sol";
import {PrimaryMarketMaker} from
    "src/modules/fundingManager/bondingCurve/PrimaryMarketMaker.sol";
import {BancorFormula} from
    "src/modules/fundingManager/bondingCurve/BancorFormula.sol";

contract BondingCurveFundingManagerTest is ModuleTest {
    // Instance
    BondingCurveFundingManager fundingManager;
    PrimaryMarketMaker marketMaker;
    BancorFormula formula;

    // Other constants.
    bytes32 private constant NAME = "BCRG Token";
    bytes32 private constant SYMBOL = "BCRG";
    uint private constant INITAL_VIRTUAL_SUPPLY = 1000e18;

    function setUp() public {
        //Add Module to Mock Orchestrator

        address impl = address(new BondingCurveFundingManager());
        fundingManager = BondingCurveFundingManager(Clones.clone(impl));
        formula = new BancorFormula();
        marketMaker =
            new PrimaryMarketMaker(address(fundingManager), address(formula));

        _setUpOrchestrator(fundingManager);

        //Init Module
        fundingManager.init(
            _orchestrator,
            _METADATA,
            abi.encode(
                NAME, SYMBOL, INITAL_VIRTUAL_SUPPLY, address(marketMaker)
            )
        );
    }

    //--------------------------------------------------------------------------
    // Test: Initialization

    //This function also tests all the getters
    //--------------------------------------------------------------------------
    // Tests: Initialization

    function testInit() public override(ModuleTest) {
        assertEq(fundingManager.name(), string(abi.encodePacked(NAME)));
        assertEq(fundingManager.symbol(), string(abi.encodePacked(SYMBOL)));
        assertEqUint(fundingManager.totalVirtualSupply(), INITAL_VIRTUAL_SUPPLY);
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        fundingManager.init(_orchestrator, _METADATA, abi.encode());
    }
    //--------------------------------------------------------------------------
    // Test: Set Virtual Value

    function testSetVirtualSupplyFails(uint amount, address user) public {
        vm.assume(user != address(this));
        vm.prank(user);
        vm.expectRevert();
        fundingManager.setVirtualSupply(amount);
    }

    function testSetVirtualSupplySuccess(uint amount) public {
        uint currentVirtualSupply = fundingManager.totalVirtualSupply();
        vm.assume(amount != currentVirtualSupply);
        fundingManager.setVirtualSupply(amount);
        assertEq(fundingManager.totalVirtualSupply(), amount);
    }
}
