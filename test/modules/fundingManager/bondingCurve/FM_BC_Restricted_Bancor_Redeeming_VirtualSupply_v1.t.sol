// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// SuT
import {FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.sol";

import {Clones} from "@oz/proxy/Clones.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";
import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";

import {
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1,
    FM_BC_Bancor_Redeeming_VirtualSupply_v1,
    IFundingManager_v1
} from "@fm/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {BancorFormula} from "@fm/bondingCurve/formulas/BancorFormula.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {ERC20PaymentClientBaseV2Mock} from
    "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV2Mock.sol";

import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";

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
        issuanceToken = new ERC20Issuance_v1(
            NAME, SYMBOL, DECIMALS, MAX_SUPPLY, address(this)
        );

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
            address(new FM_BC_Restricted_Bancor_Redeeming_VirtualSupplyV1Mock());

        bondingCurveFundingManager =
            FM_BC_Bancor_Redeeming_VirtualSupplyV1Mock(Clones.clone(impl));

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

        // Grant necessary roles for the Upstream tests to pass

        bytes32 CURVE_INTERACTION_ROLE = "CURVE_USER";
        address buyer = makeAddr("buyer");
        address seller = makeAddr("seller");

        address[] memory targets = new address[](3);
        targets[0] = buyer;
        targets[1] = seller;
        targets[2] = admin_address;

        bondingCurveFundingManager.grantModuleRoleBatched(
            CURVE_INTERACTION_ROLE, targets
        );
    }

    function testTransferOrchestratorToken_FailsGivenNotEnoughCollateralInFM(
        address to,
        uint amount,
        uint projectCollateralFeeCollected
    ) public override {
        // Temp test override, as in dev branch we have already removed the restriction
        // to call the transferOrchestratorToken() function
    }
}

contract FM_BC_Restricted_Bancor_Redeeming_VirtualSupplyV1Tests is
    ModuleTest
{
    string internal constant NAME = "Bonding Curve Token";
    string internal constant SYMBOL = "BCT";
    uint8 internal constant DECIMALS = 18;
    uint internal constant MAX_SUPPLY = type(uint).max;

    uint internal constant INITIAL_ISSUANCE_SUPPLY = 10;
    uint internal constant INITIAL_COLLATERAL_SUPPLY = 30;
    uint32 internal constant RESERVE_RATIO_FOR_BUYING = 333_333;
    uint32 internal constant RESERVE_RATIO_FOR_SELLING = 333_333;
    uint internal constant BUY_FEE = 0;
    uint internal constant SELL_FEE = 0;
    bool internal constant BUY_IS_OPEN = true;
    bool internal constant SELL_IS_OPEN = true;

    FM_BC_Restricted_Bancor_Redeeming_VirtualSupplyV1Mock
        bondingCurveFundingManager;
    address formula;

    ERC20Issuance_v1 issuanceToken;

    address admin_address = address(0xA1BA);
    address non_admin_address = address(0xB0B);

    function setUp() public {
        // Deploy contracts
        issuanceToken = new ERC20Issuance_v1(
            NAME, SYMBOL, DECIMALS, MAX_SUPPLY, address(this)
        );

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
            address(new FM_BC_Restricted_Bancor_Redeeming_VirtualSupplyV1Mock());

        bondingCurveFundingManager =
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupplyV1Mock(
            Clones.clone(impl)
        );

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

    function testsellTo_FailsIfCallerNotAuthorized() public {
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
            bondingCurveFundingManager.sellTo(
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
}
