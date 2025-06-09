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
import {DiscreteCurveMathLib_v1} from
    "src/modules/fundingManager/bondingCurve/formulas/DiscreteCurveMathLib_v1.sol";
import {PackedSegmentLib} from
    "src/modules/fundingManager/bondingCurve/libraries/PackedSegmentLib.sol";
import {IVirtualCollateralSupplyBase_v1} from
    "@fm/bondingCurve/interfaces/IVirtualCollateralSupplyBase_v1.sol";
import {IVirtualIssuanceSupplyBase_v1} from
    "@fm/bondingCurve/interfaces/IVirtualIssuanceSupplyBase_v1.sol";

contract FM_BC_Discrete_Redeeming_VirtualSupply_v1_Test is ModuleTest {
    using PackedSegmentLib for PackedSegment;
    using DiscreteCurveMathLib_v1 for PackedSegment[];

    // Structs for organizing test data
    struct CurveTestData {
        PackedSegment[] packedSegmentsArray; // Array of PackedSegments for the library
        uint totalCapacity; // Calculated: sum of segment capacities
        uint totalReserve; // Calculated: sum of segment reserves
        string description; // Optional: for logging or comments
    }

    FM_BC_Discrete_Redeeming_VirtualSupply_v1_Exposed public fmBcDiscrete;
    ERC20Mock public orchestratorToken;
    ERC20PaymentClientBaseV2Mock public paymentClient;
    PackedSegment[] public initialTestSegments;
    CurveTestData internal defaultCurve; // Declare defaultCurve variable

    address internal non_admin_address = address(0xB0B);

    // Default Curve Parameters (as defined in DiscreteCurveMathLib_v1.t.sol)
    // Based on flatSlopedTestCurve initialized in setUp() in DiscreteCurveMathLib_v1.t.sol:
    // Seg0 (Flat): P_init=0.5, S_step=50, N_steps=1  (Price: 0.50)
    // Seg1 (Sloped): P_init=0.8, P_inc=0.02, S_step=25, N_steps=2 (Prices: 0.80, 0.82)
    //
    //     Price (ether)
    //       ^
    //     0.82|                     +------+ (Supply: 100)
    //         |                     |      |
    //     0.80|             +-------+      | (Supply: 75)
    //         |             |              |
    //         |             |              |
    //         |             |              |
    //         |             |              |
    //     0.50|-------------+              | (Supply: 50)
    //         +-------------+--------------+--> Supply (ether)
    //         0             50     75     100
    //
    //          Step Prices:
    //          Supply  0-50:  Price 0.50 (Segment 0, Step 0)
    //          Supply 50-75:  Price 0.80 (Segment 1, Step 0)
    //          Supply 75-100: Price 0.82 (Segment 1, Step 1)
    uint public constant DEFAULT_SEG0_INITIAL_PRICE = 0.5 ether;
    uint public constant DEFAULT_SEG0_PRICE_INCREASE = 0;
    uint public constant DEFAULT_SEG0_SUPPLY_PER_STEP = 50 ether;
    uint public constant DEFAULT_SEG0_NUMBER_OF_STEPS = 1;

    uint public constant DEFAULT_SEG1_INITIAL_PRICE = 0.8 ether;
    uint public constant DEFAULT_SEG1_PRICE_INCREASE = 0.02 ether;
    uint public constant DEFAULT_SEG1_SUPPLY_PER_STEP = 25 ether;
    uint public constant DEFAULT_SEG1_NUMBER_OF_STEPS = 2;

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
        _authorizer.grantRole(_authorizer.getAdminRole(), address(this)); // Grant admin role to the test contract

        // --- Initialize defaultCurve ---
        defaultCurve.description = "Flat segment followed by a sloped segment";

        uint[] memory initialPrices = new uint[](2);
        initialPrices[0] = DEFAULT_SEG0_INITIAL_PRICE;
        initialPrices[1] = DEFAULT_SEG1_INITIAL_PRICE;

        uint[] memory priceIncreases = new uint[](2);
        priceIncreases[0] = DEFAULT_SEG0_PRICE_INCREASE;
        priceIncreases[1] = DEFAULT_SEG1_PRICE_INCREASE;

        uint[] memory suppliesPerStep = new uint[](2);
        suppliesPerStep[0] = DEFAULT_SEG0_SUPPLY_PER_STEP;
        suppliesPerStep[1] = DEFAULT_SEG1_SUPPLY_PER_STEP;

        uint[] memory numbersOfSteps = new uint[](2);
        numbersOfSteps[0] = DEFAULT_SEG0_NUMBER_OF_STEPS;
        numbersOfSteps[1] = DEFAULT_SEG1_NUMBER_OF_STEPS;

        defaultCurve.packedSegmentsArray = helper_createSegments(
            initialPrices, priceIncreases, suppliesPerStep, numbersOfSteps
        );
        defaultCurve.totalCapacity = (
            DEFAULT_SEG0_SUPPLY_PER_STEP * DEFAULT_SEG0_NUMBER_OF_STEPS
        ) + (DEFAULT_SEG1_SUPPLY_PER_STEP * DEFAULT_SEG1_NUMBER_OF_STEPS);

        initialTestSegments = defaultCurve.packedSegmentsArray;

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

    /* Test setVirtualCollateralSupply function
        ├── given caller is not the Orchestrator_v1 admin
        │   └── when the function setVirtualCollateralSupply() is called
        │       └── then it should revert (test modifier is in place. Modifier test itself is tested in base Module tests)
        └── given the caller is the Orchestrator_v1 admin
            ├── and the new token supply is zero
            │   └── when the setVirtualCollateralSupply() is called
            │       └── then it should revert
            └── and the new token supply is > zero
                └── when the function setVirtualCollateralSupply() is called
                    └── then it should set the new token supply
                        └── and it should emit an event
    */

    function testSetVirtualCollateralSupply_WorksGivenOnlyOrchestratorAdminModifierInPlace(
        uint _newSupply
    ) public {
        vm.assume(_newSupply != 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                _authorizer.getAdminRole(),
                non_admin_address
            )
        );
        vm.prank(non_admin_address); // Use non_admin_address as non-admin caller
        fmBcDiscrete.setVirtualCollateralSupply(_newSupply);
    }

    function testSetVirtualCollateralSupply_FailsIfZero() public {
        uint _newSupply = 0;
        vm.expectRevert(
            IVirtualCollateralSupplyBase_v1
                .Module__VirtualCollateralSupplyBase__VirtualSupplyCannotBeZero
                .selector
        );
        fmBcDiscrete.setVirtualCollateralSupply(_newSupply);
    }

    function testSetVirtualCollateralSupply(uint _newSupply) public {
        vm.assume(_newSupply != 0);
        uint oldSupply = fmBcDiscrete.getVirtualCollateralSupply();

        vm.expectEmit(true, true, false, false, address(fmBcDiscrete));
        emit IVirtualCollateralSupplyBase_v1.VirtualCollateralSupplySet(
            _newSupply, oldSupply
        );

        fmBcDiscrete.setVirtualCollateralSupply(_newSupply);
        assertEq(fmBcDiscrete.getVirtualCollateralSupply(), _newSupply);
    }

    /* Test _setVirtualIssuanceSupply function (exposed)
        ├── Given a new virtual issuance supply
        │   └── When exposed_setVirtualIssuanceSupply is called
        │       └── Then it should set the new supply
        │           └── And it should emit a VirtualIssuanceSupplySet event
    */
    function testInternal_SetVirtualIssuanceSupply_WorksAndEmitsEvent(
        uint _newSupply
    ) public {
        vm.assume(_newSupply != 0);
        uint oldSupply = fmBcDiscrete.getVirtualIssuanceSupply();

        vm.expectEmit(true, true, false, false, address(fmBcDiscrete));
        emit IVirtualIssuanceSupplyBase_v1.VirtualIssuanceSupplySet(
            _newSupply, oldSupply
        );

        fmBcDiscrete.exposed_setVirtualIssuanceSupply(_newSupply);
        assertEq(fmBcDiscrete.getVirtualIssuanceSupply(), _newSupply);
    }

    /* Test setVirtualIssuanceSupply function
        ├── Given caller is not the Orchestrator_v1 admin
        │   └── When the function setVirtualIssuanceSupply() is called
        │       └── Then it should revert
        └── Given the caller is the Orchestrator_v1 admin
            ├── And the new token supply is zero
            │   └── When the setVirtualIssuanceSupply() is called
            │       └── Then it should revert
            └── And the new token supply is > zero
                └── When the function setVirtualIssuanceSupply() is called
                    └── Then it should set the new token supply
                        └── And it should emit an event
    */
    function testSetVirtualIssuanceSupply_FailsGivenCallerNotOrchestratorAdmin(
        uint _newSupply
    ) public {
        vm.assume(_newSupply != 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                _authorizer.getAdminRole(),
                non_admin_address
            )
        );
        vm.prank(non_admin_address);
        fmBcDiscrete.setVirtualIssuanceSupply(_newSupply);
    }

    function testSetVirtualIssuanceSupply_FailsIfZero() public {
        uint _newSupply = 0;
        vm.expectRevert(
            IVirtualIssuanceSupplyBase_v1
                .Module__VirtualIssuanceSupplyBase__VirtualSupplyCannotBeZero
                .selector
        );
        fmBcDiscrete.setVirtualIssuanceSupply(_newSupply);
    }

    function testSetVirtualIssuanceSupply_Works(uint _newSupply) public {
        vm.assume(_newSupply != 0);
        uint oldSupply = fmBcDiscrete.getVirtualIssuanceSupply();

        vm.expectEmit(true, true, false, false, address(fmBcDiscrete));
        emit IVirtualIssuanceSupplyBase_v1.VirtualIssuanceSupplySet(
            _newSupply, oldSupply
        );

        fmBcDiscrete.setVirtualIssuanceSupply(_newSupply);
        assertEq(fmBcDiscrete.getVirtualIssuanceSupply(), _newSupply);
    }

    // =========================================================================
    // Test: reconfigureSegments

    /* Test reconfigureSegments function
        ├── given caller is not the Orchestrator_v1 admin
        │   └── when the function reconfigureSegments() is called
        │       └── then it should revert
        ├── given the caller is the Orchestrator_v1 admin
        │   ├── and the new segments break the invariance check
        │   │   └── when the function reconfigureSegments() is called
        │   │       └── then it should revert with InvarianceCheckFailed
        │   └── and the new segments maintain the invariance check
        │       └── when the function reconfigureSegments() is called
        │           └── then it should update the segments
        │               └── and it should emit a SegmentsSet event
        │               └── and the virtualCollateralSupply should remain unchanged
    */

    function testReconfigureSegments_FailsGivenCallerNotOrchestratorAdmin()
        public
    {
        PackedSegment[] memory newSegments = new PackedSegment[](1);
        newSegments[0] = PackedSegmentLib._create(1e18, 1e17, 100, 10);

        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                _authorizer.getAdminRole(),
                non_admin_address
            )
        );
        vm.prank(non_admin_address);
        fmBcDiscrete.reconfigureSegments(newSegments);
    }

    function testReconfigureSegments_FailsGivenInvarianceCheckFailure()
        public
    {
        uint initialIssuanceSupply = defaultCurve.totalCapacity;
        PackedSegment[] memory currentSegments =
            defaultCurve.packedSegmentsArray;
        uint initialCollateralReserve = DiscreteCurveMathLib_v1
            ._calculateReserveForSupply(currentSegments, initialIssuanceSupply);

        fmBcDiscrete.exposed_setSegments(currentSegments);
        fmBcDiscrete.exposed_setVirtualIssuanceSupply(initialIssuanceSupply);
        fmBcDiscrete.exposed_setVirtualCollateralSupply(
            initialCollateralReserve
        );

        PackedSegment[] memory breakingSegments = new PackedSegment[](1);
        breakingSegments[0] = PackedSegmentLib._create(1.1e18, 0, 100e18, 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IFM_BC_Discrete_Redeeming_VirtualSupply_v1
                    .InvarianceCheckFailed
                    .selector,
                DiscreteCurveMathLib_v1._calculateReserveForSupply(
                    breakingSegments, initialIssuanceSupply
                ),
                initialCollateralReserve
            )
        );
        fmBcDiscrete.reconfigureSegments(breakingSegments);
    }

    function testReconfigureSegments_WorksAndEmitsEvent() public {
        uint initialIssuanceSupply = defaultCurve.totalCapacity;
        PackedSegment[] memory currentSegments =
            defaultCurve.packedSegmentsArray;
        uint initialCollateralReserve = DiscreteCurveMathLib_v1
            ._calculateReserveForSupply(currentSegments, initialIssuanceSupply);

        fmBcDiscrete.exposed_setSegments(currentSegments);
        fmBcDiscrete.exposed_setVirtualIssuanceSupply(initialIssuanceSupply);
        fmBcDiscrete.exposed_setVirtualCollateralSupply(
            initialCollateralReserve
        );

        // New configuration: single flat segment
        // Price = 0.655 ether, SupplyPerStep = 100 ether, NumberOfSteps = 1
        // This should result in a reserve of 0.655 * 100 = 65.5 ether for the initialIssuanceSupply of 100 ether
        PackedSegment[] memory newSegments = new PackedSegment[](1);
        newSegments[0] = helper_createSegment(0.655 ether, 0, 100 ether, 1);

        uint expectedNewReserve = DiscreteCurveMathLib_v1
            ._calculateReserveForSupply(newSegments, initialIssuanceSupply);

        assertEq(
            expectedNewReserve,
            initialCollateralReserve,
            "Invariant check setup failed: new segments do not match old reserve"
        );

        vm.expectEmit(true, true, true, true, address(fmBcDiscrete));
        emit IFM_BC_Discrete_Redeeming_VirtualSupply_v1.SegmentsSet(newSegments);

        fmBcDiscrete.reconfigureSegments(newSegments);

        PackedSegment[] memory retrievedSegments = fmBcDiscrete.getSegments();
        assertEq(retrievedSegments.length, newSegments.length);
        assertEq(
            retrievedSegments.length,
            1,
            "Expected newSegments to have a length of 1"
        );
        assertEq(
            PackedSegment.unwrap(retrievedSegments[0]),
            PackedSegment.unwrap(newSegments[0])
        );
        assertEq(
            fmBcDiscrete.getVirtualCollateralSupply(), initialCollateralReserve
        );
    }

    // =========================================================================
    // Test: Getters - Price

    /* Test getStaticPriceForSelling
        ├── Given the default curve configuration
        │   ├── At Segment Transition:
        │   │   └── And virtualIssuanceSupply is at the last unit of the first segment (50 ether)
        │   │       └── When getStaticPriceForSelling is called
        │   │           └── Then it should return the price of the last unit of the first segment (0.5 ether)
        │   └── At Step Transition (within Segment 1, supply at 75 ether):
        │       └── And virtualIssuanceSupply is at the end of the first step of Segment 1 (75 ether)
        │           └── When getStaticPriceForSelling is called
        │               └── Then it should return the price of that step (0.8 ether)
    */
    function testGetStaticPriceForSelling_AtSegmentTransitionPoint() public {
        uint virtualIssuanceSupply = DEFAULT_SEG0_SUPPLY_PER_STEP; // 50 ether, last unit of first segment
        fmBcDiscrete.exposed_setVirtualIssuanceSupply(virtualIssuanceSupply);
        assertEq(
            fmBcDiscrete.getStaticPriceForSelling(),
            DEFAULT_SEG0_INITIAL_PRICE // 0.5 ether
        );
    }

    function testGetStaticPriceForSelling_AtExactStepTransitionPoint() public {
        // Supply is 75 ether, which is the last unit of the first step in Segment 1.
        // Price of this step (and thus this token) is 0.8 ether.
        uint virtualIssuanceSupply =
            DEFAULT_SEG0_SUPPLY_PER_STEP + DEFAULT_SEG1_SUPPLY_PER_STEP; // 50 + 25 = 75 ether
        fmBcDiscrete.exposed_setVirtualIssuanceSupply(virtualIssuanceSupply);
        assertEq(
            fmBcDiscrete.getStaticPriceForSelling(),
            DEFAULT_SEG1_INITIAL_PRICE // 0.8 ether
        );
    }

    /* Test getStaticPriceForBuying
        ├── Given the default curve configuration
        │   ├── At Segment Transition:
        │   │   └── And virtualCollateralSupply is at the last unit of the first segment (50 ether)
        │   │       └── When getStaticPriceForBuying is called (for supply 50+1=51)
        │   │           └── Then it should return the price of the first unit of the second segment (0.8 ether)
        │   └── At Step Transition (within Segment 1, supply at 75 ether):
        │       └── And virtualCollateralSupply is at the end of the first step of Segment 1 (75 ether)
        │           └── When getStaticPriceForBuying is called (for supply 75+1=76)
        │               └── Then it should return the price of the next step (0.82 ether)
    */
    function testGetStaticPriceForBuying_AtSegmentTransitionPoint() public {
        // virtualCollateralSupply is 50 ether. getStaticPriceForBuying looks at supply 50 + 1 = 51.
        // The 51st unit is the first unit of Segment 1, Step 0. Price is 0.8 ether.
        uint virtualCollateralSupply = DEFAULT_SEG0_SUPPLY_PER_STEP; // 50 ether
        fmBcDiscrete.exposed_setVirtualCollateralSupply(virtualCollateralSupply);
        assertEq(
            fmBcDiscrete.getStaticPriceForBuying(),
            DEFAULT_SEG1_INITIAL_PRICE // 0.8 ether
        );
    }

    function testGetStaticPriceForBuying_AtExactStepTransitionPoint() public {
        // virtualCollateralSupply is 75 ether. getStaticPriceForBuying looks at supply 75 + 1 = 76.
        // The 76th unit is the first unit of Segment 1, Step 1.
        // Price of this step is 0.8 + 0.02 = 0.82 ether.
        uint virtualCollateralSupply =
            DEFAULT_SEG0_SUPPLY_PER_STEP + DEFAULT_SEG1_SUPPLY_PER_STEP; // 50 + 25 = 75 ether
        fmBcDiscrete.exposed_setVirtualCollateralSupply(virtualCollateralSupply);
        uint expectedPrice =
            DEFAULT_SEG1_INITIAL_PRICE + DEFAULT_SEG1_PRICE_INCREASE; // 0.82 ether
        assertEq(fmBcDiscrete.getStaticPriceForBuying(), expectedPrice);
    }

    // =========================================================================
    // Test: _issueTokensFormulaWrapper

    /* Test _issueTokensFormulaWrapper
        ├── Given a flat segment and zero initial supply
        │   └── When collateral is provided to buy within the flat segment
        │       └── Then it should return the correct amount of tokens for the flat price
        ├── Given a curve spanning multiple segments and zero initial supply
        │   └── When collateral is provided to buy across segment boundaries
        │       └── Then it should return the correct total amount of tokens
        └── Given a sloped segment and an initial supply at the start of that segment
            └── When collateral is provided to buy within the sloped segment
                └── Then it should return the correct amount of tokens considering the price slope
    */

    function testIssueTokensFormulaWrapper_FlatSegment_FromZeroSupply()
        public
    {
        uint collateralToSpend = 25 ether;
        uint expectedTokensToMint = 50 ether; // 25 / 0.5 = 50

        assertEq(
            fmBcDiscrete.exposed_issueTokensFormulaWrapper(collateralToSpend),
            expectedTokensToMint,
            "Failed: Buying on flat segment from zero supply"
        );
    }

    function testIssueTokensFormulaWrapper_SpanningSegments_FromZeroSupply(
    ) public {
        // Test buying across Seg0 (flat) and into Seg1,Step0 (sloped)
        uint collateralToSpend = 45 ether;
        // Expected:
        // Seg0 (price 0.5): 50 tokens for 25 ether.
        // Seg1,Step0 (price 0.8): 25 tokens for 20 ether.
        // Total: 75 tokens for 45 ether.
        uint expectedTokensToMint = 75 ether;

        assertEq(
            fmBcDiscrete.exposed_issueTokensFormulaWrapper(collateralToSpend),
            expectedTokensToMint,
            "Failed: Buying across segments from zero supply (round numbers)"
        );
    }

    function testIssueTokensFormulaWrapper_SlopedSegment_FromMidSupply()
        public
    {
        // Set initial supply to be at the start of the sloped segment
        uint startingIssuanceSupply = DEFAULT_SEG0_SUPPLY_PER_STEP; // 50 ether
        fmBcDiscrete.exposed_setVirtualIssuanceSupply(startingIssuanceSupply);

        uint collateralToSpend = 20 ether;
        // Expected (starting at supply 50, spending 20 ether):
        // This buys all of Seg1,Step0 (price 0.8), which has a capacity of 25 tokens and costs 20 ether.
        // Total tokens: 25.
        uint expectedTokensToMint = 25 ether;

        assertEq(
            fmBcDiscrete.exposed_issueTokensFormulaWrapper(collateralToSpend),
            expectedTokensToMint,
            "Failed: Buying on sloped segment from mid supply"
        );
    }

    // =========================================================================
    // Helpers

    /// @notice Helper function to create a single PackedSegment.
    /// @param _initialPrice The initial price of the segment.
    /// @param _priceIncrease The price increase per step.
    /// @param _supplyPerStep The supply per step.
    /// @param _numberOfSteps The number of steps in the segment.
    /// @return A PackedSegment struct.
    function helper_createSegment(
        uint _initialPrice,
        uint _priceIncrease,
        uint _supplyPerStep,
        uint _numberOfSteps
    ) internal pure returns (PackedSegment) {
        return PackedSegmentLib._create(
            _initialPrice, _priceIncrease, _supplyPerStep, _numberOfSteps
        );
    }

    /// @notice Helper function to create a segments array from arrays of parameters.
    /// @param _initialPrices An array of initial prices for each segment.
    /// @param _priceIncreases An array of price increases for each segment.
    /// @param _suppliesPerStep An array of supplies per step for each segment.
    /// @param _numbersOfSteps An array of number of steps for each segment.
    /// @return An array of PackedSegment.
    function helper_createSegments(
        uint[] memory _initialPrices,
        uint[] memory _priceIncreases,
        uint[] memory _suppliesPerStep,
        uint[] memory _numbersOfSteps
    ) internal pure returns (PackedSegment[] memory) {
        require(
            _initialPrices.length == _priceIncreases.length
                && _initialPrices.length == _suppliesPerStep.length
                && _initialPrices.length == _numbersOfSteps.length,
            "Input arrays must have same length"
        );

        PackedSegment[] memory segments =
            new PackedSegment[](_initialPrices.length);
        for (uint i = 0; i < _initialPrices.length; i++) {
            segments[i] = helper_createSegment(
                _initialPrices[i],
                _priceIncreases[i],
                _suppliesPerStep[i],
                _numbersOfSteps[i]
            );
        }
        return segments;
    }
}
