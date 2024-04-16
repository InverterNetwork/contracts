// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// SuT
import {RestrictedBancorVirtualSupplyBondingCurveFundingManager} from
    "src/modules/fundingManager/bondingCurveFundingManager/ParibuChanges/RestrictedBancorVirtualSupplyBondingCurveFundingManager.sol";

import {Clones} from "@oz/proxy/Clones.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";
import {ERC20Issuance} from
    "src/modules/fundingManager/bondingCurveFundingManager/ParibuChanges/ERC20Issuance.sol";

import {
    IBancorVirtualSupplyBondingCurveFundingManager,
    BancorVirtualSupplyBondingCurveFundingManager,
    IBondingCurveFundingManagerBase,
    IFundingManager
} from
    "src/modules/fundingManager/bondingCurveFundingManager/BancorVirtualSupplyBondingCurveFundingManager.sol";
import {BancorFormula} from
    "src/modules/fundingManager/bondingCurveFundingManager/formula/BancorFormula.sol";

import {ERC20IssuanceMock} from "test/utils/mocks/ERC20IssuanceMock.sol";

import {
    BancorVirtualSupplyBondingCurveFundingManagerTest,
    ModuleTest,
    IModule
} from
    "test/modules/fundingManager/bondingCurveFundingManager/BancorVirtualSupplyBondingCurveFundingManager.t.sol";
import {BancorVirtualSupplyBondingCurveFundingManagerMock} from
    "test/modules/fundingManager/bondingCurveFundingManager/marketMaker/utils/mocks/BancorVirtualSupplyBondingCurveFundingManagerMock.sol";
import {RestrictedBancorVirtualSupplyBondingCurveFundingManagerMock} from
    "test/modules/fundingManager/bondingCurveFundingManager/marketMaker/utils/mocks/RestrictedBancorVirtualSupplyBondingCurveFundingManagerMock.sol";
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract RestrictedBancorVirtualSupplyBondingCurveFundingManagerUpstreamTests is
    BancorVirtualSupplyBondingCurveFundingManagerTest
{
    function setUp() public override {
        // Deploy contracts
        IBondingCurveFundingManagerBase.IssuanceToken memory
            issuanceToken_properties;
        IBancorVirtualSupplyBondingCurveFundingManager.BondingCurveProperties
            memory bc_properties;

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
        bc_properties.initialTokenSupply = INITIAL_TOKEN_SUPPLY;
        bc_properties.initialCollateralSupply = INITIAL_COLLATERAL_SUPPLY;

        address impl = address(
            new RestrictedBancorVirtualSupplyBondingCurveFundingManagerMock()
        );

        bondingCurveFundingManager =
        BancorVirtualSupplyBondingCurveFundingManagerMock(Clones.clone(impl));

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
            ERC20Issuance(bondingCurveFundingManager.getIssuanceToken());

        vm.prank(owner_address);
        issuanceToken.setMinter(address(bondingCurveFundingManager));

        // Grant necessary roles for the Upstream tests to pass

        bytes32 CURVE_INTERACTION_ROLE = "CURVE_USER";
        address buyer = makeAddr("buyer");
        address seller = makeAddr("seller");

        bondingCurveFundingManager.grantModuleRole(
            CURVE_INTERACTION_ROLE, buyer
        );
        bondingCurveFundingManager.grantModuleRole(
            CURVE_INTERACTION_ROLE, seller
        );
        bondingCurveFundingManager.grantModuleRole(
            CURVE_INTERACTION_ROLE, owner_address
        );
    }
}

contract RestrictedBancorVirtualSupplyBondingCurveFundingManagerTests is
    ModuleTest
{
    string internal constant NAME = "Bonding Curve Token";
    string internal constant SYMBOL = "BCT";
    uint8 internal constant DECIMALS = 18;
    uint internal constant MAX_SUPPLY = type(uint).max;

    uint internal constant INITIAL_TOKEN_SUPPLY = 1;
    uint internal constant INITIAL_COLLATERAL_SUPPLY = 1;
    uint32 internal constant RESERVE_RATIO_FOR_BUYING = 200_000;
    uint32 internal constant RESERVE_RATIO_FOR_SELLING = 200_000;
    uint internal constant BUY_FEE = 0;
    uint internal constant SELL_FEE = 0;
    bool internal constant BUY_IS_OPEN = true;
    bool internal constant SELL_IS_OPEN = true;

    RestrictedBancorVirtualSupplyBondingCurveFundingManagerMock
        bondingCurveFundingManager;
    address formula;

    ERC20Issuance issuanceToken;

    address owner_address = address(0xA1BA);
    address non_owner_address = address(0xB0B);

    function setUp() public {
        // Deploy contracts
        IBondingCurveFundingManagerBase.IssuanceToken memory
            issuanceToken_properties;
        IBancorVirtualSupplyBondingCurveFundingManager.BondingCurveProperties
            memory bc_properties;

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
        bc_properties.initialTokenSupply = INITIAL_TOKEN_SUPPLY;
        bc_properties.initialCollateralSupply = INITIAL_COLLATERAL_SUPPLY;

        address impl = address(
            new RestrictedBancorVirtualSupplyBondingCurveFundingManagerMock()
        );

        bondingCurveFundingManager =
        RestrictedBancorVirtualSupplyBondingCurveFundingManagerMock(
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
            ERC20Issuance(bondingCurveFundingManager.getIssuanceToken());
        vm.prank(owner_address);
        issuanceToken.setMinter(address(bondingCurveFundingManager));

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
            bondingCurveFundingManager.getVirtualTokenSupply(),
            INITIAL_TOKEN_SUPPLY,
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
                    IModule.Module__CallerNotAuthorized.selector,
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
                    IModule.Module__CallerNotAuthorized.selector,
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
                    IModule.Module__CallerNotAuthorized.selector,
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
                    IModule.Module__CallerNotAuthorized.selector,
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

        bytes32 _roleId = _authorizer.generateRoleId(
            address(bondingCurveFundingManager), "CURVE_USER"
        );

        vm.startPrank(_minter);
        {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IModule.Module__CallerNotAuthorized.selector,
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
