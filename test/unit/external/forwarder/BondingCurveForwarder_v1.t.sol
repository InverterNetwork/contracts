// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// SuT
import {BondingCurveForwarder_v1} from
    "src/external/forwarder/BondingCurveForwarder_v1.sol";
import {FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.sol";

import {Clones} from "@oz/proxy/Clones.sol";

import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";
import {
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1,
    FM_BC_Bancor_Redeeming_VirtualSupply_v1
} from "@fm/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {BancorFormula} from "@fm/bondingCurve/formulas/BancorFormula.sol";
import {ModuleTest} from "@unitTest/modules/ModuleTest.sol";
import {IModule_v1} from "@unitTest/modules/ModuleTest.sol";

contract BondingCurveForwarderV1Tests is ModuleTest {
    string internal constant NAME = "Bonding Curve Token";
    string internal constant SYMBOL = "BCT";
    uint8 internal constant DECIMALS = 18;
    uint internal constant MAX_SUPPLY = type(uint).max;

    uint internal constant INITIAL_ISSUANCE_SUPPLY = 195_642_169e16;
    uint internal constant INITIAL_COLLATERAL_SUPPLY = 39_097_931e16;
    uint32 internal constant RESERVE_RATIO_FOR_BUYING = 333_333;
    uint32 internal constant RESERVE_RATIO_FOR_SELLING = 333_333;
    uint internal constant BUY_FEE = 0;
    uint internal constant SELL_FEE = 0;
    bool internal constant BUY_IS_OPEN = true;
    bool internal constant SELL_IS_OPEN = true;

    BondingCurveForwarder_v1 public forwarder;
    FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 public
        bondingCurveFundingManager;
    address public formula;

    ERC20Issuance_v1 public issuanceToken;

    address internal admin_address = address(0xA1BA);
    address internal non_admin_address = address(0xB0B);

    function setUp() public {
        // Deploy contracts
        issuanceToken = new ERC20Issuance_v1(NAME, SYMBOL, DECIMALS, MAX_SUPPLY);
        issuanceToken.setMinter(address(this), true);

        BancorFormula bancorFormula = new BancorFormula();
        formula = address(bancorFormula);

        IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties memory
            bc_properties;

        bc_properties.formula = formula;
        bc_properties.reserveRatioForBuying = RESERVE_RATIO_FOR_BUYING;
        bc_properties.reserveRatioForSelling = RESERVE_RATIO_FOR_SELLING;
        bc_properties.buyFee = BUY_FEE;
        bc_properties.sellFee = SELL_FEE;
        bc_properties.buyIsOpen = BUY_IS_OPEN;
        bc_properties.sellIsOpen = SELL_IS_OPEN;
        bc_properties.initialIssuanceSupply = INITIAL_ISSUANCE_SUPPLY;
        bc_properties.initialCollateralSupply = INITIAL_COLLATERAL_SUPPLY;

        address impl =
            address(new FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1());

        bondingCurveFundingManager =
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(Clones.clone(impl));

        _setUpOrchestrator(bondingCurveFundingManager);

        _authorizer.grantRole(_authorizer.getAdminRole(), admin_address);

        // Init Module
        bondingCurveFundingManager.init(
            _orchestrator,
            _METADATA,
            abi.encode(
                address(issuanceToken),
                bc_properties,
                _token // fetching from ModuleTest.sol (specifically after the _setUpOrchestrator function call)
            )
        );

        // we grant minting rights to the bonding curve
        issuanceToken.setMinter(address(bondingCurveFundingManager), true);

        address forwarderImpl = address(new BondingCurveForwarder_v1());
        forwarder = BondingCurveForwarder_v1(Clones.clone(forwarderImpl));
        forwarder.initialize(address(bondingCurveFundingManager), admin_address);

        bytes32 CURVE_INTERACTION_ROLE =
            bondingCurveFundingManager.CURVE_INTERACTION_ROLE();
        bondingCurveFundingManager.grantModuleRole(
            CURVE_INTERACTION_ROLE, address(forwarder)
        );
    }

    function testBuy(uint depositAmount) public {
        depositAmount = _bound_for_decimal_conversion(
            depositAmount,
            1e16,
            1e28,
            _token.decimals(),
            issuanceToken.decimals()
        );
        _token.mint(address(this), depositAmount);
        _token.approve(address(forwarder), depositAmount);
        uint initialBalance = issuanceToken.balanceOf(address(this));
        forwarder.buy(depositAmount, 1);
        uint finalBalance = issuanceToken.balanceOf(address(this));
        assertTrue(finalBalance > initialBalance);
    }

    function testSell(uint depositAmount) public {
        depositAmount = _bound_for_decimal_conversion(
            depositAmount,
            1e16,
            1e28,
            _token.decimals(),
            issuanceToken.decimals()
        );
        // First, buy some tokens to collateralize the curve
        _token.mint(address(this), depositAmount);
        _token.approve(address(forwarder), depositAmount);
        forwarder.buy(depositAmount, 1);

        // Now, sell the tokens we just received
        uint sellAmount = issuanceToken.balanceOf(address(this));
        assertTrue(sellAmount > 0, "No issuance tokens to sell");
        issuanceToken.approve(address(forwarder), sellAmount);

        uint initialBalance = _token.balanceOf(address(this));
        forwarder.sell(sellAmount, 1);
        uint finalBalance = _token.balanceOf(address(this));
        assertTrue(finalBalance > initialBalance);
    }

    function testBuyFor(uint depositAmount) public {
        depositAmount = _bound_for_decimal_conversion(
            depositAmount,
            1e16,
            1e28,
            _token.decimals(),
            issuanceToken.decimals()
        );
        address receiver = address(0x1337);
        _token.mint(address(receiver), depositAmount);
        uint initialBalance = issuanceToken.balanceOf(receiver);

        vm.startPrank(receiver);
        _token.approve(address(forwarder), depositAmount);

        forwarder.buyFor(receiver, depositAmount, 1);
        vm.stopPrank();

        uint finalBalance = issuanceToken.balanceOf(receiver);
        assertTrue(finalBalance > initialBalance);
    }

    function testSellTo(uint depositAmount) public {
        depositAmount = _bound_for_decimal_conversion(
            depositAmount,
            1e16,
            1e28,
            _token.decimals(),
            issuanceToken.decimals()
        );
        address sellerAndReceiver = address(0x1337);

        // The seller first buys tokens
        vm.startPrank(sellerAndReceiver);
        _token.mint(sellerAndReceiver, depositAmount);
        _token.approve(address(forwarder), depositAmount);
        forwarder.buy(depositAmount, 1);

        // Now the seller sells the tokens, and the collateral goes to themself
        uint sellAmount = issuanceToken.balanceOf(sellerAndReceiver);
        assertTrue(sellAmount > 0, "No issuance tokens to sell");
        issuanceToken.approve(address(forwarder), sellAmount);

        uint initialBalance = _token.balanceOf(sellerAndReceiver);
        forwarder.sellTo(sellerAndReceiver, sellAmount, 1);
        uint finalBalance = _token.balanceOf(sellerAndReceiver);
        vm.stopPrank();
        assertTrue(finalBalance > initialBalance);
    }

    function testDirectBuyFails() public {
        uint depositAmount = 1 ether;
        _token.mint(address(this), depositAmount);
        _token.approve(address(bondingCurveFundingManager), depositAmount);
        vm.expectRevert();
        bondingCurveFundingManager.buy(depositAmount, 0);
    }

    function testUpdateBondingCurve() public {
        // Deploy a new bonding curve
        address newImpl =
            address(new FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1());
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 newBondingCurve =
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(
            Clones.clone(newImpl)
        );

        // Set up new bonding curve (reusing same config)
        IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties memory
            bc_properties;
        bc_properties.formula = formula;
        bc_properties.reserveRatioForBuying = RESERVE_RATIO_FOR_BUYING;
        bc_properties.reserveRatioForSelling = RESERVE_RATIO_FOR_SELLING;
        bc_properties.buyFee = BUY_FEE;
        bc_properties.sellFee = SELL_FEE;
        bc_properties.buyIsOpen = BUY_IS_OPEN;
        bc_properties.sellIsOpen = SELL_IS_OPEN;
        bc_properties.initialIssuanceSupply = INITIAL_ISSUANCE_SUPPLY;
        bc_properties.initialCollateralSupply = INITIAL_COLLATERAL_SUPPLY;

        newBondingCurve.init(
            _orchestrator,
            _METADATA,
            abi.encode(address(issuanceToken), bc_properties, _token)
        );

        // Grant minting rights and role
        issuanceToken.setMinter(address(newBondingCurve), true);
        bytes32 CURVE_INTERACTION_ROLE =
            newBondingCurve.CURVE_INTERACTION_ROLE();
        newBondingCurve.grantModuleRole(
            CURVE_INTERACTION_ROLE, address(forwarder)
        );

        // Update bonding curve as admin
        vm.startPrank(admin_address);
        address oldBondingCurve = address(forwarder.restrictedBondingCurve());

        vm.expectEmit(true, true, false, true);
        emit BondingCurveUpdated(oldBondingCurve, address(newBondingCurve));

        forwarder.updateBondingCurve(address(newBondingCurve));
        vm.stopPrank();

        // Verify the bonding curve was updated
        assertEq(
            address(forwarder.restrictedBondingCurve()),
            address(newBondingCurve)
        );
    }

    function testUpdateBondingCurveOnlyOwner() public {
        address newBondingCurve = address(0x123);

        vm.startPrank(non_admin_address);
        vm.expectRevert();
        forwarder.updateBondingCurve(newBondingCurve);
        vm.stopPrank();
    }

    function testUpdateBondingCurveInvalidAddress() public {
        vm.startPrank(admin_address);
        vm.expectRevert();
        forwarder.updateBondingCurve(address(0));
        vm.stopPrank();
    }

    function testUpdateApprovals() public {
        vm.startPrank(admin_address);

        vm.expectEmit(true, true, true, true);
        emit ApprovalsUpdated(
            address(forwarder.restrictedBondingCurve()),
            address(forwarder.collateralToken()),
            address(forwarder.issuanceToken())
        );

        forwarder.updateApprovals();
        vm.stopPrank();
    }

    function testUpdateApprovalsOnlyOwner() public {
        vm.startPrank(non_admin_address);
        vm.expectRevert();
        forwarder.updateApprovals();
        vm.stopPrank();
    }

    function testInitializeInvalidBondingCurve() public {
        address testForwarderImpl = address(new BondingCurveForwarder_v1());
        BondingCurveForwarder_v1 testForwarder =
            BondingCurveForwarder_v1(Clones.clone(testForwarderImpl));

        vm.expectRevert();
        testForwarder.initialize(address(0), admin_address);
    }

    function testCannotReinitialize() public {
        vm.expectRevert();
        forwarder.initialize(address(bondingCurveFundingManager), admin_address);
    }

    // Events to test
    event BondingCurveUpdated(
        address indexed oldBondingCurve, address indexed newBondingCurve
    );
    event ApprovalsUpdated(
        address indexed bondingCurve,
        address indexed collateralToken,
        address indexed issuanceToken
    );

    function testInit() public override {}
    function testReinitFails() public override {}
}
