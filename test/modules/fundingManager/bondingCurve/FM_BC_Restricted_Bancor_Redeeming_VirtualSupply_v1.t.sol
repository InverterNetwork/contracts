// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// SuT
import {FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.sol";

import {Clones} from "@oz/proxy/Clones.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";
import {ERC20Issuance_v1} from "@fm/bondingCurve/tokens/ERC20Issuance_v1.sol";

import {
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1,
    FM_BC_Bancor_Redeeming_VirtualSupply_v1,
    IFundingManager_v1
} from "@fm/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {BancorFormula} from "@fm/bondingCurve/formulas/BancorFormula.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";

import {ERC20Issuance_v1} from "@fm/bondingCurve/tokens/ERC20Issuance_v1.sol";

import {
    FM_BC_Bancor_Redeeming_VirtualSupplyV1Test,
    ModuleTest,
    IModule_v1
} from
    "test/modules/fundingManager/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.t.sol";
import {FM_BC_Bancor_Redeeming_VirtualSupplyV1Mock} from
    "test/modules/fundingManager/bondingCurve/utils/mocks/FM_BC_Bancor_Redeeming_VirtualSupplyV1Mock.sol";
import {FM_BC_Restricted_Bancor_Redeeming_VirtualSupplyV1Mock} from
    "test/modules/fundingManager/bondingCurve/utils/mocks/FM_BC_Restricted_Bancor_Redeeming_VirtualSupplyV1Mock.sol";
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract FM_BC_Restricted_Bancor_Redeeming_VirtualSupplyV1UpstreamTests is
    FM_BC_Bancor_Redeeming_VirtualSupplyV1Test
{
    function setUp() public override {
        // Deploy contracts
        IBondingCurveBase_v1.IssuanceToken memory issuanceToken_properties;
        IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties memory
            bc_properties;

        BancorFormula bancorFormula = new BancorFormula();
        formula = address(bancorFormula);

        issuanceToken_properties.name = NAME;
        issuanceToken_properties.symbol = SYMBOL;
        issuanceToken_properties.decimals = DECIMALS;
        issuanceToken_properties.maxSupply = MAX_SUPPLY;

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
            address(new FM_BC_Restricted_Bancor_Redeeming_VirtualSupplyV1Mock());

        bondingCurveFundingManager =
            FM_BC_Bancor_Redeeming_VirtualSupplyV1Mock(Clones.clone(impl));

        _setUpOrchestrator(bondingCurveFundingManager);

        _authorizer.grantRole(_authorizer.getOwnerRole(), owner_address);

        // Init Module
        bondingCurveFundingManager.init(
            _orchestrator,
            _METADATA,
            abi.encode(
                issuanceToken_properties,
                owner_address,
                bc_properties,
                _token // fetching from ModuleTest.sol (specifically after the _setUpOrchestrator function call)
            )
        );

        issuanceToken =
            ERC20Issuance_v1(bondingCurveFundingManager.getIssuanceToken());

        // Grant necessary roles for the Upstream tests to pass

        bytes32 CURVE_INTERACTION_ROLE = "CURVE_USER";
        address buyer = makeAddr("buyer");
        address seller = makeAddr("seller");

        address[] memory targets = new address[](3);
        targets[0] = buyer;
        targets[1] = seller;
        targets[2] = owner_address;

        bondingCurveFundingManager.grantModuleRoleBatched(
            CURVE_INTERACTION_ROLE, targets
        );
    }

    // Override to test deactivation
    function testTransferOrchestratorToken(address to, uint amount)
        public
        override
    {
        vm.assume(to != address(0) && to != address(bondingCurveFundingManager));

        _token.mint(address(bondingCurveFundingManager), amount);

        vm.startPrank(address(_orchestrator));
        {
            vm.expectRevert(
                abi.encodeWithSelector(
                    FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1
                        .Module__FM_BC_Restricted_Bancor_Redeeming_VirtualSupply__FeatureDeactivated
                        .selector
                )
            );

            bondingCurveFundingManager.transferOrchestratorToken(to, amount);
        }
        vm.stopPrank();

        assertEq(_token.balanceOf(to), 0);
        assertEq(_token.balanceOf(address(bondingCurveFundingManager)), amount);
    }

    // Override to test deactivation
    function testMintIssuanceTokenTo(uint amount) public override {
        assertEq(issuanceToken.balanceOf(non_owner_address), 0);

        vm.startPrank(address(owner_address));
        {
            vm.expectRevert(
                abi.encodeWithSelector(
                    FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1
                        .Module__FM_BC_Restricted_Bancor_Redeeming_VirtualSupply__FeatureDeactivated
                        .selector
                )
            );

            bondingCurveFundingManager.mintIssuanceTokenTo(
                non_owner_address, amount
            );
        }
        vm.stopPrank();

        assertEq(_token.balanceOf(non_owner_address), 0);
    }
}

contract FM_BC_Restricted_Bancor_Redeeming_VirtualSupplyV1Tests is
    ModuleTest
{
    string internal constant NAME = "Bonding Curve Token";
    string internal constant SYMBOL = "BCT";
    uint8 internal constant DECIMALS = 18;
    uint internal constant MAX_SUPPLY = type(uint).max;

    uint internal constant INITIAL_ISSUANCE_SUPPLY = 1;
    uint internal constant INITIAL_COLLATERAL_SUPPLY = 1;
    uint32 internal constant RESERVE_RATIO_FOR_BUYING = 200_000;
    uint32 internal constant RESERVE_RATIO_FOR_SELLING = 200_000;
    uint internal constant BUY_FEE = 0;
    uint internal constant SELL_FEE = 0;
    bool internal constant BUY_IS_OPEN = true;
    bool internal constant SELL_IS_OPEN = true;

    FM_BC_Restricted_Bancor_Redeeming_VirtualSupplyV1Mock
        bondingCurveFundingManager;
    address formula;

    ERC20Issuance_v1 issuanceToken;

    address owner_address = address(0xA1BA);
    address non_owner_address = address(0xB0B);

    function setUp() public {
        // Deploy contracts
        IBondingCurveBase_v1.IssuanceToken memory issuanceToken_properties;
        IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties memory
            bc_properties;

        BancorFormula bancorFormula = new BancorFormula();
        formula = address(bancorFormula);

        issuanceToken_properties.name = NAME;
        issuanceToken_properties.symbol = SYMBOL;
        issuanceToken_properties.decimals = DECIMALS;
        issuanceToken_properties.maxSupply = MAX_SUPPLY;

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
            address(new FM_BC_Restricted_Bancor_Redeeming_VirtualSupplyV1Mock());

        bondingCurveFundingManager =
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupplyV1Mock(
            Clones.clone(impl)
        );

        _setUpOrchestrator(bondingCurveFundingManager);

        _authorizer.grantRole(_authorizer.getOwnerRole(), owner_address);

        // Init Module
        bondingCurveFundingManager.init(
            _orchestrator,
            _METADATA,
            abi.encode(
                issuanceToken_properties,
                owner_address,
                bc_properties,
                _token // fetching from ModuleTest.sol (specifically after the _setUpOrchestrator function call)
            )
        );

        issuanceToken =
            ERC20Issuance_v1(bondingCurveFundingManager.getIssuanceToken());

        // Since we tested the success case in the Upstream tests, we now only need to verify revert on unauthorized calls
    }

    function testInit() public override {
        assertEq(
            issuanceToken.name(),
            string(abi.encodePacked(NAME)),
            "Name has not been set correctly"
        );
        assertEq(
            issuanceToken.symbol(),
            string(abi.encodePacked(SYMBOL)),
            "Symbol has not been set correctly"
        );
        assertEq(
            issuanceToken.decimals(),
            DECIMALS,
            "Decimals has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManager.call_collateralTokenDecimals(),
            _token.decimals(),
            "Collateral token decimals has not been set correctly"
        );
        assertEq(
            address(bondingCurveFundingManager.formula()),
            formula,
            "Formula has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManager.getVirtualIssuanceSupply(),
            INITIAL_ISSUANCE_SUPPLY,
            "Virtual token supply has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManager.getVirtualCollateralSupply(),
            INITIAL_COLLATERAL_SUPPLY,
            "Virtual collateral supply has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManager.call_reserveRatioForBuying(),
            RESERVE_RATIO_FOR_BUYING,
            "Reserve ratio for buying has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManager.call_reserveRatioForSelling(),
            RESERVE_RATIO_FOR_SELLING,
            "Reserve ratio for selling has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManager.buyFee(),
            BUY_FEE,
            "Buy fee has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManager.buyIsOpen(),
            BUY_IS_OPEN,
            "Buy-is-open has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManager.buyFee(),
            SELL_FEE,
            "Sell fee has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManager.buyIsOpen(),
            SELL_IS_OPEN,
            "Sell-is-open has not been set correctly"
        );
    }

    function testReinitFails() public override {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        bondingCurveFundingManager.init(_orchestrator, _METADATA, abi.encode());
    }

    function testBuyFor_FailsIfCallerNotAuthorized() public {
        address _buyer = makeAddr("buyer");
        address _receiver = makeAddr("receiver");
        uint _depositAmount = 1;

        bytes32 _roleId = _authorizer.generateRoleId(
            address(bondingCurveFundingManager), "CURVE_USER"
        );

        vm.startPrank(_buyer);
        {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IModule_v1.Module__CallerNotAuthorized.selector,
                    _roleId,
                    _buyer
                )
            );
            bondingCurveFundingManager.buyFor(
                _receiver, _depositAmount, _depositAmount
            );
        }
    }

    function testBuy_FailsIfCallerNotAuthorized() public {
        address _buyer = makeAddr("buyer");
        uint _depositAmount = 1;

        bytes32 _roleId = _authorizer.generateRoleId(
            address(bondingCurveFundingManager), "CURVE_USER"
        );

        vm.startPrank(_buyer);
        {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IModule_v1.Module__CallerNotAuthorized.selector,
                    _roleId,
                    _buyer
                )
            );
            bondingCurveFundingManager.buy(_depositAmount, _depositAmount);
        }
    }

    function testSellFor_FailsIfCallerNotAuthorized() public {
        address _seller = makeAddr("seller");
        address _receiver = makeAddr("receiver");
        uint _sellAmount = 1;

        bytes32 _roleId = _authorizer.generateRoleId(
            address(bondingCurveFundingManager), "CURVE_USER"
        );

        vm.startPrank(_seller);
        {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IModule_v1.Module__CallerNotAuthorized.selector,
                    _roleId,
                    _seller
                )
            );
            bondingCurveFundingManager.sellFor(
                _receiver, _sellAmount, _sellAmount
            );
        }
    }

    function testSell_FailsIfCallerNotAuthorized() public {
        address _seller = makeAddr("seller");
        uint _sellAmount = 1;

        bytes32 _roleId = _authorizer.generateRoleId(
            address(bondingCurveFundingManager), "CURVE_USER"
        );

        vm.startPrank(_seller);
        {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IModule_v1.Module__CallerNotAuthorized.selector,
                    _roleId,
                    _seller
                )
            );
            bondingCurveFundingManager.sell(_sellAmount, _sellAmount);
        }
    }

    function testMintIssuanceTokenTo_FailsIfCallerNotAuthorized() public {
        address _minter = makeAddr("minter");
        address _receiver = makeAddr("receiver");
        uint _mintAmount = 1;

        bytes32 _roleId = _authorizer.getOwnerRole();

        vm.startPrank(_minter);
        {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IModule_v1.Module__CallerNotAuthorized.selector,
                    _roleId,
                    _minter
                )
            );
            bondingCurveFundingManager.mintIssuanceTokenTo(
                _receiver, _mintAmount
            );
        }
    }
}
