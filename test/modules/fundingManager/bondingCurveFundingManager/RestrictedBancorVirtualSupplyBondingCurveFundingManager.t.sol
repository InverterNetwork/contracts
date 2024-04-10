// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// SuT
import {RestrictedBancorVirtualSupplyBondingCurveFundingManager} from
    "src/modules/fundingManager/bondingCurveFundingManager/ParibuChanges/RestrictedBancorVirtualSupplyBondingCurveFundingManager.sol";

import {Clones} from "@oz/proxy/Clones.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";

import {
    IBancorVirtualSupplyBondingCurveFundingManager,
    BancorVirtualSupplyBondingCurveFundingManager,
    IFundingManager
} from
    "src/modules/fundingManager/bondingCurveFundingManager/BancorVirtualSupplyBondingCurveFundingManager.sol";
import {BancorFormula} from
    "src/modules/fundingManager/bondingCurveFundingManager/formula/BancorFormula.sol";

import {ERC20IssuanceMock} from "test/utils/mocks/ERC20IssuanceMock.sol";

import {BancorVirtualSupplyBondingCurveFundingManagerTest} from
    "test/modules/fundingManager/bondingCurveFundingManager/BancorVirtualSupplyBondingCurveFundingManager.t.sol";
import {BancorVirtualSupplyBondingCurveFundingManagerMock} from
    "test/modules/fundingManager/bondingCurveFundingManager/marketMaker/utils/mocks/BancorVirtualSupplyBondingCurveFundingManagerMock.sol";

import {RestrictedBancorVirtualSupplyBondingCurveFundingManagerMock} from
    "test/modules/fundingManager/bondingCurveFundingManager/marketMaker/utils/mocks/RestrictedBancorVirtualSupplyBondingCurveFundingManagerMock.sol";

contract RestrictedBancorVirtualSupplyBondingCurveFundingManagerUpstreamTests is
    BancorVirtualSupplyBondingCurveFundingManagerTest
{
    function setUp() public override {
        // Deploy contracts
        IBancorVirtualSupplyBondingCurveFundingManager.BondingCurveProperties
            memory bc_properties;

        BancorFormula bancorFormula = new BancorFormula();
        formula = address(bancorFormula);

        issuanceToken = new ERC20IssuanceMock();
        issuanceToken.init(NAME, SYMBOL, type(uint).max, DECIMALS);
        issuanceToken.setMinter(address(bondingCurveFundingManager));

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

        issuanceToken.setMinter(address(bondingCurveFundingManager));

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
