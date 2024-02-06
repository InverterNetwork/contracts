// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// SuT
import {
    IToposBondingCurveFundingManager,
    ToposBondingCurveFundingManager,
    IFundingManager
} from
    "src/modules/fundingManager/bondingCurveFundingManager/ToposBondingCurveFundingManager.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";

// import {IERC20} from "@oz/token/ERC20/IERC20.sol";
// import {IERC20Metadata} from
//     "@oz/token/ERC20/extensions/IERC20Metadata.sol";

// Internal Dependencies
import {ModuleTest, IModule, IOrchestrator} from "test/modules/ModuleTest.sol";
import {BancorFormula} from
    "src/modules/fundingManager/bondingCurveFundingManager/formula/BancorFormula.sol";
import {IBondingCurveFundingManagerBase} from
    "src/modules/fundingManager/bondingCurveFundingManager/IBondingCurveFundingManagerBase.sol";
import {
    IRedeemingBondingCurveFundingManagerBase,
    IRedeemingBondingCurveFundingManagerBase
} from
    "src/modules/fundingManager/bondingCurveFundingManager/RedeemingBondingCurveFundingManagerBase.sol";
import {ILiquidityPool} from
    "src/modules/logicModule/liquidityPool/ILiquidityPool.sol";
// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// Mocks
import {ToposBondingCurveFundingManagerMock} from
    "test/modules/fundingManager/bondingCurveFundingManager/marketMaker/utils/mocks/ToposBondingCurveFundingManagerMock.sol";

import {RedeemingBondingCurveFundingManagerBaseTest} from
    "test/modules/fundingManager/bondingCurveFundingManager/RedeemingB_CurveFundingManagerBase.t.sol";

/*     
    @NOTE: The functions:

    - deposit(uint amount) external {}
    - depositFor(address to, uint amount) external {}
    - withdraw(uint amount) external {}
    - withdrawTo(address to, uint amount) external {} 

    are not tested since they are empty and will be removed in the future.

    Also, since the following functions just wrap the Bancor formula contract, their content is assumed to be tested in the original formula tests, not here:

    - _issueTokensFormulaWrapper(uint _depositAmount)
    - _redeemTokensFormulaWrapper(uint _depositAmount)

    */
contract ToposBondingCurveFundingManagerTest is ModuleTest {
    string private constant NAME = "Topos Token";
    string private constant SYMBOL = "TPG";

    ToposBondingCurveFundingManagerMock bondingCurveFundingManager;

    address owner_address = address(0xA1BA);
    ILiquidityPool liquidityPool = ILiquidityPool(makeAddr("liquidityPool")); // TODO: Replace with Mock

    function setUp() public {
        // Deploy contracts
        IToposBondingCurveFundingManager.IssuanceToken memory issuanceToken;
        IToposBondingCurveFundingManager.BondingCurveProperties memory
            bc_properties;

        issuanceToken.name = bytes32(abi.encodePacked(NAME));
        issuanceToken.symbol = bytes32(abi.encodePacked(SYMBOL));
        issuanceToken.decimals = uint8(18);

        address impl = address(new ToposBondingCurveFundingManagerMock());

        bondingCurveFundingManager =
            ToposBondingCurveFundingManagerMock(Clones.clone(impl));

        _setUpOrchestrator(bondingCurveFundingManager);

        _authorizer.grantRole(_authorizer.getOwnerRole(), owner_address);

        // Init Module
        bondingCurveFundingManager.init(
            _orchestrator,
            _METADATA,
            abi.encode(
                issuanceToken,
                bc_properties,
                _token, // fetching from ModuleTest.sol (specifically after the _setUpOrchestrator function call)
                liquidityPool
            )
        );
    }
    //--------------------------------------------------------------------------
    // Test: Initialization

    //This function also tests all the getters
    //--------------------------------------------------------------------------
    // Tests: Initialization
    function testInit() public override {
        assertEq(
            bondingCurveFundingManager.name(),
            string(abi.encodePacked(bytes32(abi.encodePacked(NAME)))),
            "Name has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManager.symbol(),
            string(abi.encodePacked(bytes32(abi.encodePacked(SYMBOL)))),
            "Symbol has not been set correctly"
        );
    }

    function testReinitFails() public override {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        bondingCurveFundingManager.init(_orchestrator, _METADATA, abi.encode());
    }
}
