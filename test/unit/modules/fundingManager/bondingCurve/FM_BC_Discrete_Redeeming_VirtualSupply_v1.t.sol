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
import {PackedSegment} from
    "src/modules/fundingManager/bondingCurve/types/PackedSegment_v1.sol";
import {IDiscreteCurveMathLib_v1} from
    "src/modules/fundingManager/bondingCurve/interfaces/IDiscreteCurveMathLib_v1.sol";
import {PackedSegmentLib} from
    "src/modules/fundingManager/bondingCurve/libraries/PackedSegmentLib.sol";

contract FM_BC_Discrete_Redeeming_VirtualSupply_v1_Test is ModuleTest {
    using PackedSegmentLib for PackedSegment;

    FM_BC_Discrete_Redeeming_VirtualSupply_v1_Exposed public fmBcDiscrete;
    ERC20Mock public orchestratorToken;
    ERC20PaymentClientBaseV2Mock public paymentClient;
    PackedSegment[] public initialTestSegments;

    // =========================================================================
    // Setup

    function setUp() public {
        address impl =
            address(new FM_BC_Discrete_Redeeming_VirtualSupply_v1_Exposed());
        fmBcDiscrete = FM_BC_Discrete_Redeeming_VirtualSupply_v1_Exposed(
            Clones.clone(impl)
        );

        orchestratorToken = new ERC20Mock("Orchestrator Token", "OTK", 18);

        _setUpOrchestrator(fmBcDiscrete);
        _authorizer.setIsAuthorized(address(this), true);

        initialTestSegments = new PackedSegment[](1);
        initialTestSegments[0] = PackedSegmentLib._create(1e18, 1e17, 100, 10); // Example segment

        fmBcDiscrete.init(
            _orchestrator,
            _METADATA,
            abi.encode(address(orchestratorToken), initialTestSegments)
        );

        paymentClient = new ERC20PaymentClientBaseV2Mock();
        _addLogicModuleToOrchestrator(address(paymentClient));
    }

    // =========================================================================
    // Test: Initialization

    function testInit() public override(ModuleTest) {
        assertEq(address(fmBcDiscrete.orchestrator()), address(_orchestrator));
        assertEq(address(fmBcDiscrete.token()), address(orchestratorToken));
        assertEq(fmBcDiscrete.getSegments().length, initialTestSegments.length);
        assertEq(
            PackedSegment.unwrap(fmBcDiscrete.getSegments()[0]),
            PackedSegment.unwrap(initialTestSegments[0])
        );
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        fmBcDiscrete.init(
            _orchestrator, _METADATA, abi.encode(address(orchestratorToken))
        );
    }

    function test_SupportsInterface() public {
        assertTrue(
            fmBcDiscrete.supportsInterface(type(IFundingManager_v1).interfaceId)
        );
        assertTrue(
            fmBcDiscrete.supportsInterface(
                type(IFM_BC_Discrete_Redeeming_VirtualSupply_v1).interfaceId
            )
        );
    }

    // =========================================================================
    // Test: Internal (tested through exposed_ functions)

    /* test internal _setSegments()
        ├── Given an empty segments array
        │   └── When _setSegments is called with an empty array
        │       └── Then it should revert with DiscreteCurveMathLib__NoSegmentsConfigured
        └── Given a valid segments array
            ├── When _setSegments is called with a valid array
            │   └── Then the segments should be set correctly
            └── When _setSegments is called with a valid array
                └── Then it should emit a SegmentsSet event
    */
    function testInternal_SetSegments_FailsEmptyArray() public {
        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__NoSegmentsConfigured
                .selector
        );
        fmBcDiscrete.exposed_setSegments(new PackedSegment[](0));
    }

    function testInternal_SetSegments_SetsCorrectly() public {
        PackedSegment[] memory testSegments = new PackedSegment[](1);
        testSegments[0] = PackedSegmentLib._create(1e18, 1e17, 100, 10);

        fmBcDiscrete.exposed_setSegments(testSegments);

        PackedSegment[] memory retrievedSegments = fmBcDiscrete.getSegments();
        assertEq(retrievedSegments.length, testSegments.length);
        assertEq(
            PackedSegment.unwrap(retrievedSegments[0]),
            PackedSegment.unwrap(testSegments[0])
        );
    }

    function testInternal_SetSegments_EmitsEvent() public {
        PackedSegment[] memory testSegments = new PackedSegment[](1);
        testSegments[0] = PackedSegmentLib._create(2e18, 2e17, 200, 20);

        vm.expectEmit(true, true, true, true, address(fmBcDiscrete));
        emit IFM_BC_Discrete_Redeeming_VirtualSupply_v1.SegmentsSet(
            testSegments
        );
        fmBcDiscrete.exposed_setSegments(testSegments);
    }
}
