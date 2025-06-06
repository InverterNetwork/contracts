// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Internal
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "@unitTest/modules/ModuleTest.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";

// External
import {Clones} from "@oz/proxy/Clones.sol";
import {OZErrors} from "@testUtilities/OZErrors.sol";

// Tests and Mocks
import {ERC20Mock} from "@mocks/external/token/ERC20Mock.sol";
import {
    IERC20PaymentClientBase_v2,
    ERC20PaymentClientBaseV2Mock
} from "@mocks/modules/paymentClient/ERC20PaymentClientBaseV2Mock.sol";

// System under Test (SuT)
import {IFM_BC_Discrete_Redeeming_VirtualSupply_v1} from
    "src/modules/fundingManager/bondingCurve/interfaces/IFM_BC_Discrete_Redeeming_VirtualSupply_v1.sol";
import {FM_BC_Discrete_Redeeming_VirtualSupply_v1_Exposed} from
    "./FM_BC_Discrete_Redeeming_VirtualSupply_v1_Exposed.sol";

contract FM_BC_Discrete_Redeeming_VirtualSupply_v1_Test is ModuleTest {
    FM_BC_Discrete_Redeeming_VirtualSupply_v1_Exposed public fmBcDiscrete;
    ERC20Mock public orchestratorToken;
    ERC20PaymentClientBaseV2Mock public paymentClient;

    // =========================================================================
    // Setup
    function setUp() public {
        address impl = address(new FM_BC_Discrete_Redeeming_VirtualSupply_v1_Exposed());
        fmBcDiscrete =
            FM_BC_Discrete_Redeeming_VirtualSupply_v1_Exposed(Clones.clone(impl));

        orchestratorToken = new ERC20Mock("Orchestrator Token", "OTK", 18);

        _setUpOrchestrator(fmBcDiscrete);
        _authorizer.setIsAuthorized(address(this), true);

        fmBcDiscrete.init(
            _orchestrator, _METADATA, abi.encode(address(orchestratorToken))
        );

        paymentClient = new ERC20PaymentClientBaseV2Mock();
        _addLogicModuleToOrchestrator(address(paymentClient));
    }

    // =========================================================================
    // Test: Initialization
    function testInit() public override(ModuleTest) {
        assertEq(address(fmBcDiscrete.orchestrator()), address(_orchestrator));
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        fmBcDiscrete.init(
            _orchestrator, _METADATA, abi.encode(address(orchestratorToken))
        );
    }

    function testSupportsInterface() public {
        assertTrue(
            fmBcDiscrete.supportsInterface(type(IFundingManager_v1).interfaceId)
        );
        assertTrue(
            fmBcDiscrete.supportsInterface(
                type(IFM_BC_Discrete_Redeeming_VirtualSupply_v1).interfaceId
            )
        );
    }
}
