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

    /* Test transferOrchestratorToken
        ├── Given the onlyPaymentClient modifier is set (individual modifier tests are done in Module_v1.t.sol)
        │   └── And the conditions of the modifier are not met
        │       └── When the function transferOrchestratorToken() gets called
        │           └── Then it should revert
        ├── Given the caller is a PaymentClient module
        │   └── And the PaymentClient module is registered in the Orchestrator
        │       ├── And the withdraw amount + project collateral fee > FM collateral token balance
        │       │   └── When the function transferOrchestratorToken() gets called
        │       │       └── Then it should revert
        │       └── And the FM has enough collateral token for amount to be transferred
        │           └── When the function transferOrchestratorToken() gets called
        │               └── Then it should send the funds to the specified address
        │                   └── And it should emit an event
    */
    function testTransferOrchestratorToken_OnlyPaymentClientModifierSet(
        address caller,
        address to,
        uint amount
    ) public {
        vm.prank(caller);
        vm.expectRevert(IModule_v1.Module__OnlyCallableByPaymentClient.selector);
        fmBcDiscrete.transferOrchestratorToken(to, amount);
    }

    // This test is commented out because it relies on setting `projectCollateralFeeCollected`
    // which is not directly settable in the SuT without a helper function, and we do not
    // want to add a helper function for this. This test can be re-enabled once there is
    // a way to get a non-zero fee in the SuT.
    /*
    function testTransferOrchestratorToken_FailsGivenNotEnoughCollateralInFM(
        address to,
        uint amount,
        uint projectCollateralFeeCollected
    ) public {
        vm.assume(to != address(0) && to != address(fmBcDiscrete));

        amount = bound(amount, 1, type(uint128).max);
        projectCollateralFeeCollected =
            bound(projectCollateralFeeCollected, 1, type(uint128).max);

        // Add collateral fee collected to create fail scenario
        fmBcDiscrete.setProjectCollateralFeeCollectedHelper(
            projectCollateralFeeCollected
        );
        assertEq(
            fmBcDiscrete.projectCollateralFeeCollected(),
            projectCollateralFeeCollected
        );
        amount = amount + projectCollateralFeeCollected; // Withdraw amount which includes the fee

        orchestratorToken.mint(address(fmBcDiscrete), amount);
        assertEq(orchestratorToken.balanceOf(address(fmBcDiscrete)), amount);

        vm.startPrank(address(paymentClient));
        {
            vm.expectRevert(
                IFundingManager_v1
                    .InvalidOrchestratorTokenWithdrawAmount
                    .selector
            );
            fmBcDiscrete.transferOrchestratorToken(to, amount);
        }
        vm.stopPrank();
    }
    */

    function testTransferOrchestratorToken_WorksGivenFunctionGetsCalled(
        address to,
        uint amount
    ) public {
        vm.assume(to != address(0) && to != address(fmBcDiscrete));

        orchestratorToken.mint(address(fmBcDiscrete), amount);

        assertEq(orchestratorToken.balanceOf(to), 0);
        assertEq(orchestratorToken.balanceOf(address(fmBcDiscrete)), amount);

        vm.startPrank(address(paymentClient));
        {
            vm.expectEmit(true, true, true, true);
            emit IFundingManager_v1.TransferOrchestratorToken(to, amount);

            fmBcDiscrete.transferOrchestratorToken(to, amount);
        }
        vm.stopPrank();

        assertEq(orchestratorToken.balanceOf(to), amount);
        assertEq(orchestratorToken.balanceOf(address(fmBcDiscrete)), 0);
    }
}
