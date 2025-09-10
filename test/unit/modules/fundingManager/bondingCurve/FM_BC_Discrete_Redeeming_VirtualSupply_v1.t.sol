// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Internal
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "@unitTest/modules/ModuleTest.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {IRedeemingBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IRedeemingBondingCurveBase_v1.sol";
import {IVirtualCollateralSupplyBase_v1} from
    "@fm/bondingCurve/interfaces/IVirtualCollateralSupplyBase_v1.sol";
import {IVirtualIssuanceSupplyBase_v1} from
    "@fm/bondingCurve/interfaces/IVirtualIssuanceSupplyBase_v1.sol";
import {PackedSegment} from
    "src/modules/fundingManager/bondingCurve/types/PackedSegment_v1.sol";
import {IDiscreteCurveMathLib_v1} from
    "src/modules/fundingManager/bondingCurve/interfaces/IDiscreteCurveMathLib_v1.sol";
import {DiscreteCurveMathLib_v1} from
    "src/modules/fundingManager/bondingCurve/formulas/DiscreteCurveMathLib_v1.sol";
import {PackedSegmentLib} from
    "src/modules/fundingManager/bondingCurve/libraries/PackedSegmentLib.sol";

// External
import {Clones} from "@oz/proxy/Clones.sol";
import {OZErrors} from "@testUtilities/OZErrors.sol";

// Tests and Mocks
import {ERC20Mock} from "@mocks/external/token/ERC20Mock.sol";
import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol"; // Added import
import {
    IERC20PaymentClientBase_v2,
    ERC20PaymentClientBaseV2Mock
} from "@mocks/modules/paymentClient/ERC20PaymentClientBaseV2Mock.sol";

// System under Test (SuT)
import {IFM_BC_Discrete_Redeeming_VirtualSupply_v1} from
    "src/modules/fundingManager/bondingCurve/interfaces/IFM_BC_Discrete_Redeeming_VirtualSupply_v1.sol";
import {FM_BC_Discrete_Redeeming_VirtualSupply_v1_Exposed} from
    "test/mocks/modules/fundingManager/bondingCurve/FM_BC_Discrete_Redeeming_VirtualSupply_v1_Exposed.sol";

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

    // Protocol Fee Test Parameters
    uint internal constant TEST_PROTOCOL_COLLATERAL_BUY_FEE_BPS = 50; // 0.5%
    uint internal constant TEST_PROTOCOL_ISSUANCE_BUY_FEE_BPS = 20; // 0.2%
    uint internal constant TEST_PROTOCOL_COLLATERAL_SELL_FEE_BPS = 40; // 0.4%
    uint internal constant TEST_PROTOCOL_ISSUANCE_SELL_FEE_BPS = 30; // 0.3%
    address internal constant TEST_PROTOCOL_TREASURY = address(0xFEE5); // Define a test treasury address

    // Project Fee Constants (mirroring those in the contract for assertion)
    uint internal constant TEST_PROJECT_BUY_FEE_BPS = 100;
    uint internal constant TEST_PROJECT_SELL_FEE_BPS = 100;

    address internal non_admin_address = address(0xB0B);

    // Default Curve Parameters
    uint public constant DEFAULT_SEG0_INITIAL_PRICE = 0.5 ether;
    uint public constant DEFAULT_SEG0_PRICE_INCREASE = 0;
    uint public constant DEFAULT_SEG0_SUPPLY_PER_STEP = 50 ether;
    uint public constant DEFAULT_SEG0_NUMBER_OF_STEPS = 1;

    uint public constant DEFAULT_SEG1_INITIAL_PRICE = 0.8 ether;
    uint public constant DEFAULT_SEG1_PRICE_INCREASE = 0.02 ether;
    uint public constant DEFAULT_SEG1_SUPPLY_PER_STEP = 25 ether;
    uint public constant DEFAULT_SEG1_NUMBER_OF_STEPS = 2;

    // Issuance Token Parameters
    string internal constant ISSUANCE_TOKEN_NAME = "House Token";
    string internal constant ISSUANCE_TOKEN_SYMBOL = "HOUSE";
    uint8 internal constant ISSUANCE_TOKEN_DECIMALS = 18;
    uint internal constant ISSUANCE_TOKEN_MAX_SUPPLY = type(uint).max;

    //
    uint collateralAmountIn = 10 ether;
    uint minIssuanceAmountOut = 1 ether;

    FM_BC_Discrete_Redeeming_VirtualSupply_v1_Exposed public fmBcDiscrete;
    ERC20Mock public orchestratorToken; // This is the collateral token
    ERC20Issuance_v1 public issuanceToken; // This is the token to be issued
    ERC20PaymentClientBaseV2Mock public paymentClient;
    PackedSegment[] public initialTestSegments;
    CurveTestData internal defaultCurve; // Declare defaultCurve variable

    // =========================================================================
    // Setup

    function setUp() public {
        address impl =
            address(new FM_BC_Discrete_Redeeming_VirtualSupply_v1_Exposed());
        fmBcDiscrete = FM_BC_Discrete_Redeeming_VirtualSupply_v1_Exposed(
            Clones.clone(impl)
        );

        orchestratorToken = new ERC20Mock("Orchestrator Token", "OTK", 18);
        issuanceToken = new ERC20Issuance_v1(
            ISSUANCE_TOKEN_NAME,
            ISSUANCE_TOKEN_SYMBOL,
            ISSUANCE_TOKEN_DECIMALS,
            ISSUANCE_TOKEN_MAX_SUPPLY
        );
        // Grant minting rights for issuance token to the test contract for setup if needed,
        // and later to the bonding curve itself.
        issuanceToken.setMinter(address(this), true);

        _setUpOrchestrator(fmBcDiscrete); // This also sets up feeManager via _createFeeManager in ModuleTest

        // Configure FeeManager *before* fmBcDiscrete.init() is called later in this setUp.
        // ModuleTest's _setUpOrchestrator should make `this` (the test contract) the owner of feeManager.
        feeManager.setWorkflowTreasury(
            address(_orchestrator), TEST_PROTOCOL_TREASURY
        );

        bytes4 buyOrderSelector =
            bytes4(keccak256(bytes("_buyOrder(address,uint,uint)")));
        feeManager.setCollateralWorkflowFee(
            address(_orchestrator),
            address(fmBcDiscrete),
            buyOrderSelector,
            true,
            TEST_PROTOCOL_COLLATERAL_BUY_FEE_BPS
        );
        feeManager.setIssuanceWorkflowFee(
            address(_orchestrator),
            address(fmBcDiscrete),
            buyOrderSelector,
            true,
            TEST_PROTOCOL_ISSUANCE_BUY_FEE_BPS
        );

        bytes4 sellOrderSelector =
            bytes4(keccak256(bytes("_sellOrder(address,uint,uint)")));
        feeManager.setCollateralWorkflowFee(
            address(_orchestrator),
            address(fmBcDiscrete),
            sellOrderSelector,
            true,
            TEST_PROTOCOL_COLLATERAL_SELL_FEE_BPS
        );
        feeManager.setIssuanceWorkflowFee(
            address(_orchestrator),
            address(fmBcDiscrete),
            sellOrderSelector,
            true,
            TEST_PROTOCOL_ISSUANCE_SELL_FEE_BPS
        );

        _authorizer.setIsAuthorized(address(this), true);
        _authorizer.grantRole(_authorizer.getAdminRole(), address(this));

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

        vm.expectEmit(true, true, true, true, address(fmBcDiscrete));
        emit IBondingCurveBase_v1.IssuanceTokenSet(
            address(issuanceToken), issuanceToken.decimals()
        );
        vm.expectEmit(true, true, true, true, address(fmBcDiscrete));
        emit IFM_BC_Discrete_Redeeming_VirtualSupply_v1.SegmentsSet(
            initialTestSegments
        );
        vm.expectEmit(true, true, true, true, address(fmBcDiscrete));
        emit IFundingManager_v1.OrchestratorTokenSet(
            address(orchestratorToken), orchestratorToken.decimals()
        );

        fmBcDiscrete.init(
            _orchestrator,
            _METADATA,
            abi.encode(
                address(issuanceToken),
                address(orchestratorToken),
                initialTestSegments
            )
        );

        // Update protocol fee cache for buy and sell operations
        fmBcDiscrete.updateProtocolFeeCache();

        // Grant minting rights for issuance token to the bonding curve
        issuanceToken.setMinter(address(fmBcDiscrete), true);

        paymentClient = new ERC20PaymentClientBaseV2Mock();
        _addLogicModuleToOrchestrator(address(paymentClient));
    }

    // =========================================================================
    // Test: Initialization

    /* Test init()
        └── Given valid initialization parameters (including pre-configured FeeManager)
            └── When init() is called
                └── Then the orchestrator should be set correctly
                    └── And the collateral token should be set correctly
                    └── And the issuance token should be set correctly
                    └── And the segments should be set correctly
                    └── And project fees (buyFee, sellFee) should be set correctly
                    └── And protocol fees should be cached correctly in _protocolFeeCache
    */
    function testInit() public override(ModuleTest) {
        assertEq(address(fmBcDiscrete.orchestrator()), address(_orchestrator));
        assertEq(
            address(fmBcDiscrete.token()),
            address(orchestratorToken),
            "Collateral token mismatch"
        );
        assertEq(
            fmBcDiscrete.getIssuanceToken(),
            address(issuanceToken),
            "Issuance token mismatch"
        );

        PackedSegment[] memory segmentsAfterInit = fmBcDiscrete.getSegments();
        assertEq(
            segmentsAfterInit.length,
            initialTestSegments.length,
            "Segments length mismatch"
        );
        for (uint i = 0; i < segmentsAfterInit.length; i++) {
            assertEq(
                PackedSegment.unwrap(segmentsAfterInit[i]),
                PackedSegment.unwrap(initialTestSegments[i]),
                string(
                    abi.encodePacked(
                        "Segment content mismatch at index ", vm.toString(i)
                    )
                )
            );
        }

        // --- Assertions for fee setup during init ---
        assertEq(
            fmBcDiscrete.buyFee(),
            TEST_PROJECT_BUY_FEE_BPS,
            "Project buy fee mismatch after init"
        );
        assertEq(
            fmBcDiscrete.sellFee(),
            TEST_PROJECT_SELL_FEE_BPS,
            "Project sell fee mismatch after init"
        );

        IFM_BC_Discrete_Redeeming_VirtualSupply_v1.ProtocolFeeCache memory cache =
            fmBcDiscrete.exposed_getProtocolFeeCache();

        assertEq(
            cache.collateralTreasury,
            TEST_PROTOCOL_TREASURY,
            "Cached collateral treasury mismatch"
        );
        assertEq(
            cache.issuanceTreasury,
            TEST_PROTOCOL_TREASURY,
            "Cached issuance treasury mismatch"
        ); // FeeManager uses one workflow treasury for both

        assertEq(
            cache.collateralFeeBuyBps,
            TEST_PROTOCOL_COLLATERAL_BUY_FEE_BPS,
            "Cached collateralFeeBuyBps mismatch"
        );
        assertEq(
            cache.issuanceFeeBuyBps,
            TEST_PROTOCOL_ISSUANCE_BUY_FEE_BPS,
            "Cached issuanceFeeBuyBps mismatch"
        );
        assertEq(
            cache.collateralFeeSellBps,
            TEST_PROTOCOL_COLLATERAL_SELL_FEE_BPS,
            "Cached collateralFeeSellBps mismatch"
        );
        assertEq(
            cache.issuanceFeeSellBps,
            TEST_PROTOCOL_ISSUANCE_SELL_FEE_BPS,
            "Cached issuanceFeeSellBps mismatch"
        );
    }

    /* Test reinitFails()
        └── Given the contract is already initialized
            └── When init() is called again
                └── Then it should revert with Initializable__InvalidInitialization
    */
    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        fmBcDiscrete.init(
            _orchestrator,
            _METADATA,
            abi.encode(
                address(issuanceToken),
                address(orchestratorToken),
                initialTestSegments
            )
        );
    }

    /* Test supportsInterface()
        └── Given the FM_BC_Discrete_Redeeming_VirtualSupply_v1 contract
            ├── When supportsInterface() is called with IFundingManager_v1 interface ID
            |   └── Then it should return true
            └── When supportsInterface() is called with IFM_BC_Discrete_Redeeming_VirtualSupply_v1 interface ID
                └── Then it should return true
    */
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

    /* Test internal _setIssuanceToken()
        └── Given a new issuance token
            └── When exposed_setIssuanceToken is called
                └── Then the issuance token should be set correctly
                └── And it should emit an IssuanceTokenSet event
    */
    function testInternal_SetIssuanceToken_SuccessAndEvent() public {
        ERC20Issuance_v1 newIssuanceToken =
            new ERC20Issuance_v1("New Token", "NEW", 18, type(uint).max);

        vm.expectEmit(true, true, true, true, address(fmBcDiscrete));
        emit IBondingCurveBase_v1.IssuanceTokenSet(
            address(newIssuanceToken), newIssuanceToken.decimals()
        );

        fmBcDiscrete.exposed_setIssuanceToken(address(newIssuanceToken));
        assertEq(fmBcDiscrete.getIssuanceToken(), address(newIssuanceToken));
    }

    /* Test transferOrchestratorToken
        ├── Given the onlyPaymentClient modifier is set (individual modifier tests are done in Module_v1.t.sol)
        │   └── And the conditions of the modifier are not met
        │       └── When the function transferOrchestratorToken() gets called
        │           └── Then it should revert
        └── Given the caller is a PaymentClient module
            └── And the PaymentClient module is registered in the Orchestrator
                ├── And the withdraw amount + project collateral fee > FM collateral token balance
                │   └── When the function transferOrchestratorToken() gets called
                │       └── Then it should revert
                └── And the FM has enough collateral token for amount to be transferred
                    └── When the function transferOrchestratorToken() gets called
                        └── Then it should send the funds to the specified address
                            └── And it should emit an event
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
        vm.prank(non_admin_address);
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
        _ensureTotalIssuanceSupply(initialIssuanceSupply);
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
        _ensureTotalIssuanceSupply(initialIssuanceSupply);
        fmBcDiscrete.exposed_setVirtualCollateralSupply(
            initialCollateralReserve
        );

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

    /* Test Price Getters: getStaticPriceForSelling() and getStaticPriceForBuying()
        ├── Test getStaticPriceForSelling()
        │   ├── Given a specific virtualIssuanceSupply at a segment transition point
        │   │   └── When getStaticPriceForSelling() is called
        │   │       └── Then it should return the correct price for that segment
        │   └── Given a specific virtualIssuanceSupply at an exact step transition point
        │       └── When getStaticPriceForSelling() is called
        │           └── Then it should return the correct price for that step
        └── Test getStaticPriceForBuying()
            ├── Given a specific virtualCollateralSupply at a segment transition point
            │   └── When getStaticPriceForBuying() is called
            │       └── Then it should return the correct price for the next segment/step
            └── Given a specific virtualCollateralSupply at an exact step transition point
                └── When getStaticPriceForBuying() is called
                    └── Then it should return the correct price for the next step
    */
    function testGetStaticPriceForSelling_AtSegmentTransitionPoint() public {
        uint virtualIssuanceSupply = DEFAULT_SEG0_SUPPLY_PER_STEP;
        _ensureTotalIssuanceSupply(virtualIssuanceSupply);
        assertEq(
            fmBcDiscrete.getStaticPriceForSelling(), DEFAULT_SEG0_INITIAL_PRICE
        );
    }

    function testGetStaticPriceForSelling_AtExactStepTransitionPoint() public {
        uint virtualIssuanceSupply =
            DEFAULT_SEG0_SUPPLY_PER_STEP + DEFAULT_SEG1_SUPPLY_PER_STEP;
        _ensureTotalIssuanceSupply(virtualIssuanceSupply);
        assertEq(
            fmBcDiscrete.getStaticPriceForSelling(), DEFAULT_SEG1_INITIAL_PRICE
        );
    }

    function testGetStaticPriceForBuying_AtSegmentTransitionPoint() public {
        uint virtualCollateralSupply = DEFAULT_SEG0_SUPPLY_PER_STEP;
        fmBcDiscrete.exposed_setVirtualCollateralSupply(virtualCollateralSupply);
        assertEq(
            fmBcDiscrete.getStaticPriceForBuying(), DEFAULT_SEG1_INITIAL_PRICE
        );
    }

    function testGetStaticPriceForBuying_AtExactStepTransitionPoint() public {
        uint virtualCollateralSupply =
            DEFAULT_SEG0_SUPPLY_PER_STEP + DEFAULT_SEG1_SUPPLY_PER_STEP;
        fmBcDiscrete.exposed_setVirtualCollateralSupply(virtualCollateralSupply);
        uint expectedPrice =
            DEFAULT_SEG1_INITIAL_PRICE + DEFAULT_SEG1_PRICE_INCREASE;
        assertEq(fmBcDiscrete.getStaticPriceForBuying(), expectedPrice);
    }

    /* Test _issueTokensFormulaWrapper()
        ├── Given a flat segment and zero initial supply
        │   └── When collateral is spent to buy tokens
        │       └── Then it should return the correct number of tokens minted
        ├── Given spanning segments and zero initial supply
        │   └── When collateral is spent to buy tokens across segments
        │       └── Then it should return the correct number of tokens minted
        └── Given a sloped segment and mid-curve initial supply
            └── When collateral is spent to buy tokens
                └── Then it should return the correct number of tokens minted
    */
    function testIssueTokensFormulaWrapper_FlatSegment_FromZeroSupply()
        public
    {
        uint collateralToSpend = 25 ether;
        uint expectedTokensToMint = 50 ether;
        assertEq(
            fmBcDiscrete.exposed_issueTokensFormulaWrapper(collateralToSpend),
            expectedTokensToMint,
            "Failed: Buying on flat segment from zero supply"
        );
    }

    function testIssueTokensFormulaWrapper_SpanningSegments_FromZeroSupply()
        public
    {
        uint collateralToSpend = 45 ether;
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
        uint startingIssuanceSupply = DEFAULT_SEG0_SUPPLY_PER_STEP;
        _ensureTotalIssuanceSupply(startingIssuanceSupply);
        uint collateralToSpend = 20 ether;
        uint expectedTokensToMint = 25 ether;
        assertEq(
            fmBcDiscrete.exposed_issueTokensFormulaWrapper(collateralToSpend),
            expectedTokensToMint,
            "Failed: Buying on sloped segment from mid supply"
        );
    }

    // =========================================================================
    // Test: _redeemTokensFormulaWrapper

    /* Test _redeemTokensFormulaWrapper()
        ├── Given a flat segment with existing supply
        │   └── When tokens are redeemed
        │       └── Then it should return the correct collateral amount
        ├── Given spanning segments with existing supply
        │   └── When tokens are redeemed across segments
        │       └── Then it should return the correct collateral amount
        ├── Given a sloped segment with existing supply
        │   └── When tokens are redeemed
        │       └── Then it should return the correct collateral amount
        ├── Given a partial step redemption
        │   └── When tokens are redeemed partially from a step
        │       └── Then it should return the correct collateral amount
        ├── Given zero tokens to redeem
        │   └── When redeeming zero tokens
        │       └── Then it should revert with DiscreteCurveMathLib__ZeroIssuanceInput
        └── Given tokens to redeem exceed current supply
            └── When redeeming more tokens than available
                └── Then it should revert with DiscreteCurveMathLib__InsufficientIssuanceToSell
    */
    function testRedeemTokensFormulaWrapper_FlatSegment() public {
        _ensureTotalIssuanceSupply(DEFAULT_SEG0_SUPPLY_PER_STEP);
        uint tokensToRedeem = 20 ether;
        uint expectedCollateral = 10 ether;
        assertEq(
            fmBcDiscrete.exposed_redeemTokensFormulaWrapper(tokensToRedeem),
            expectedCollateral,
            "Scenario 1 Failed: Redeeming from flat segment"
        );
    }

    function testRedeemTokensFormulaWrapper_SpanningSegments() public {
        _ensureTotalIssuanceSupply(
            DEFAULT_SEG0_SUPPLY_PER_STEP + DEFAULT_SEG1_SUPPLY_PER_STEP
        );
        uint tokensToRedeem = 35 ether;
        uint expectedCollateral = 20 ether + 5 ether;
        assertEq(
            fmBcDiscrete.exposed_redeemTokensFormulaWrapper(tokensToRedeem),
            expectedCollateral,
            "Scenario 2 Failed: Redeeming across segments"
        );
    }

    function testRedeemTokensFormulaWrapper_SlopedSegment() public {
        _ensureTotalIssuanceSupply(defaultCurve.totalCapacity);
        uint tokensToRedeem = 30 ether;
        uint expectedCollateral = (25 ether * 82) / 100 + (5 ether * 80) / 100;
        assertEq(
            fmBcDiscrete.exposed_redeemTokensFormulaWrapper(tokensToRedeem),
            expectedCollateral,
            "Scenario 3 Failed: Redeeming from sloped segment"
        );
    }

    function testRedeemTokensFormulaWrapper_PartialStep() public {
        _ensureTotalIssuanceSupply(
            DEFAULT_SEG0_SUPPLY_PER_STEP + DEFAULT_SEG1_SUPPLY_PER_STEP
        );
        uint tokensToRedeem = 10 ether;
        uint expectedCollateral = 8 ether;
        assertEq(
            fmBcDiscrete.exposed_redeemTokensFormulaWrapper(tokensToRedeem),
            expectedCollateral,
            "Scenario 4 Failed: Redeeming partially from a step"
        );
    }

    function testRedeemTokensFormulaWrapper_RevertsOnZeroTokens() public {
        _ensureTotalIssuanceSupply(50 ether);
        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__ZeroIssuanceInput
                .selector
        );
        fmBcDiscrete.exposed_redeemTokensFormulaWrapper(0);
    }

    function testRedeemTokensFormulaWrapper_RevertsOnInsufficientSupply()
        public
    {
        uint currentSupply = 50 ether;
        _ensureTotalIssuanceSupply(currentSupply);
        uint tokensToRedeem = 51 ether;
        vm.expectRevert(
            abi.encodeWithSelector(
                IDiscreteCurveMathLib_v1
                    .DiscreteCurveMathLib__InsufficientIssuanceToSell
                    .selector,
                tokensToRedeem,
                currentSupply
            )
        );
        fmBcDiscrete.exposed_redeemTokensFormulaWrapper(tokensToRedeem);
    }

    /* 
    Test _processCollateralTokensForBuyOperation (exposed)
    └──When: function is called
        └── Then: It should do nothing
    */

    // Trivial

    /* Test _handleIssuanceTokensAfterBuy (exposed)
        └── Given a receiver address and an amount of issuance tokens to mint
            └── When exposed_handleIssuanceTokensAfterBuy is called
                └── Then it should mint the specified amount of issuance tokens to the receiver
                    └── And the receiver's token balance should increase by the amount
                    └── And the total supply of issuance tokens should increase by the amount
    */
    function testHandleIssuanceTokensAfterBuy_MintsTokensToReceiver(
        address _receiver,
        uint _amount
    ) public {
        vm.assume(_receiver != address(0) && _amount > 0);

        uint initialReceiverBalance = issuanceToken.balanceOf(_receiver);
        uint initialTotalSupply = issuanceToken.totalSupply();

        // Call the exposed function
        fmBcDiscrete.exposed_handleIssuanceTokensAfterBuy(_receiver, _amount);

        // Assert final balances
        assertEq(
            issuanceToken.balanceOf(_receiver),
            initialReceiverBalance + _amount,
            "Receiver final balance mismatch"
        );
        assertEq(
            issuanceToken.totalSupply(),
            initialTotalSupply + _amount,
            "Total supply mismatch"
        );
    }

    /* Test _handleCollateralTokensAfterSell (exposed)
        └── Given a receiver address and an amount of collateral tokens to transfer
            └── When exposed_handleCollateralTokensAfterSell is called
                └── Then it should transfer the specified amount of collateral tokens to the receiver
                    └── And the receiver's token balance should increase by the amount
                    └── And the module's token balance should decrease by the amount
    */
    function testHandleCollateralTokensAfterSell_TransfersTokensToReceiver(
        address _receiver,
        uint _amount
    ) public {
        vm.assume(_receiver != address(0) && _amount > 0);

        // Mint initial tokens to the fmBcDiscrete contract
        orchestratorToken.mint(address(fmBcDiscrete), _amount);
        assertEq(
            orchestratorToken.balanceOf(address(fmBcDiscrete)),
            _amount,
            "Module initial balance mismatch"
        );
        assertEq(
            orchestratorToken.balanceOf(_receiver),
            0,
            "Receiver initial balance mismatch"
        );

        uint initialReceiverBalance = orchestratorToken.balanceOf(_receiver);
        uint initialModuleBalance =
            orchestratorToken.balanceOf(address(fmBcDiscrete));

        // Call the exposed function
        fmBcDiscrete.exposed_handleCollateralTokensAfterSell(_receiver, _amount);

        // Assert final balances
        assertEq(
            orchestratorToken.balanceOf(_receiver),
            initialReceiverBalance + _amount,
            "Receiver final balance mismatch"
        );
        assertEq(
            orchestratorToken.balanceOf(address(fmBcDiscrete)),
            initialModuleBalance - _amount,
            "Module final balance mismatch"
        );
    }

    /* Test calculatePurchaseReturn()
        └── Given project fee is active (from setUp: TEST_PROJECT_BUY_FEE_BPS)
            └── And protocol fees are all zeroed out in the cache
            └── And a specific deposit amount
                    └── When calculatePurchaseReturn() is called
                        └── Then it should return the correctly calculated issuance amount after only project fee
    */
    function testCalculatePurchaseReturn_GivenProjectFeeOnly_WhenProtocolFeesZeroedInCache_ShouldReturnCorrectAmount(
    ) public {
        uint depositAmount = 10 ether;

        // Create a fee cache with zero protocol fees
        IFM_BC_Discrete_Redeeming_VirtualSupply_v1.ProtocolFeeCache memory
            zeroProtocolFeeCache =
            IFM_BC_Discrete_Redeeming_VirtualSupply_v1.ProtocolFeeCache({
                collateralTreasury: TEST_PROTOCOL_TREASURY, // Can be any address as fees are 0
                issuanceTreasury: TEST_PROTOCOL_TREASURY, // Can be any address as fees are 0
                collateralFeeBuyBps: 0,
                issuanceFeeBuyBps: 0,
                collateralFeeSellBps: 0, // Not relevant for purchase, but set to 0 for completeness
                issuanceFeeSellBps: 0 // Not relevant for purchase, but set to 0 for completeness
            });
        fmBcDiscrete.exposed_setProtocolFeeCache(zeroProtocolFeeCache);

        // Get project fee (should be TEST_PROJECT_BUY_FEE_BPS from setUp)
        uint projectBuyFeeBps = fmBcDiscrete.buyFee();

        // Stage 1: Fees on Deposited Collateral (only project fee)
        uint collateralProtocolFeeAmount = 0; // Protocol fees are zeroed
        uint projectFeeAmount = (depositAmount * projectBuyFeeBps) / 10_000;
        uint netDeposit =
            depositAmount - collateralProtocolFeeAmount - projectFeeAmount;

        // Stage 2: Fees on Gross Issuance Tokens (protocol issuance fee is zero)
        uint grossIssuanceTokenAmount =
            fmBcDiscrete.exposed_issueTokensFormulaWrapper(netDeposit);
        uint issuanceProtocolFeeAmount = 0; // Protocol fees are zeroed
        uint expectedIssuanceTokens =
            grossIssuanceTokenAmount - issuanceProtocolFeeAmount;

        uint actualIssuanceTokens =
            fmBcDiscrete.calculatePurchaseReturn(depositAmount);

        assertEq(
            actualIssuanceTokens,
            expectedIssuanceTokens,
            "Project fee only: Calculated purchase return mismatch"
        );
    }

    /* Test _getFunctionFeesAndTreasuryAddresses() (exposed)
        └── Given the FeeManager is configured with specific fees during setup
            └── And fm.init() has populated the _protocolFeeCache
                ├── When called with buy-related selector
                │   └── Then it should return the cached collateral treasury for buy operations
                │       └── And it should return the cached issuance treasury for buy operations
                │       └── And it should return the cached collateralFeeBuyBps
                │       └── And it should return the cached issuanceFeeBuyBps
                │
                ├── When called with sell-related selector 
                │   └── Then it should return the cached collateral treasury for sell operations
                │       └── And it should return the cached issuance treasury for sell operations
                │       └── And it should return the cached collateralFeeSellBps
                │       └── And it should return the cached issuanceFeeSellBps
                │
                └── When called with an unhandled selector
                    └── Then it should return the collateral treasury configured directly in FeeManager (via super call)
                        └── And it should return the issuance treasury configured directly in FeeManager (via super call)
                        └── And it should return the collateralFeeBps configured directly in FeeManager (via super call)
                        └── And it should return the issuanceFeeBps configured directly in FeeManager (via super call)
    */
    function testGetFunctionFeesAndTreasuryAddresses_BuySelectors_ReturnsCachedValues(
    ) public {
        // Arrange
        bytes4 calculatePurchaseReturnSelector =
            fmBcDiscrete.calculatePurchaseReturn.selector;
        bytes4 buyOrderSelector =
            bytes4(keccak256(bytes("_buyOrder(address,uint,uint)")));

        // Act & Assert for calculatePurchaseReturn.selector
        (
            address cTreasuryCalc,
            address iTreasuryCalc,
            uint cBpsCalc,
            uint iBpsCalc
        ) = fmBcDiscrete.exposed_getFunctionFeesAndTreasuryAddresses(
            calculatePurchaseReturnSelector
        );

        assertEq(
            cTreasuryCalc,
            TEST_PROTOCOL_TREASURY,
            "Buy (calc): Collateral treasury mismatch"
        );
        assertEq(
            iTreasuryCalc,
            TEST_PROTOCOL_TREASURY,
            "Buy (calc): Issuance treasury mismatch"
        );
        assertEq(
            cBpsCalc,
            TEST_PROTOCOL_COLLATERAL_BUY_FEE_BPS,
            "Buy (calc): Collateral BPS mismatch"
        );
        assertEq(
            iBpsCalc,
            TEST_PROTOCOL_ISSUANCE_BUY_FEE_BPS,
            "Buy (calc): Issuance BPS mismatch"
        );

        // Act & Assert for _buyOrder.selector
        (
            address cTreasuryOrder,
            address iTreasuryOrder,
            uint cBpsOrder,
            uint iBpsOrder
        ) = fmBcDiscrete.exposed_getFunctionFeesAndTreasuryAddresses(
            buyOrderSelector
        );

        assertEq(
            cTreasuryOrder,
            TEST_PROTOCOL_TREASURY,
            "Buy (order): Collateral treasury mismatch"
        );
        assertEq(
            iTreasuryOrder,
            TEST_PROTOCOL_TREASURY,
            "Buy (order): Issuance treasury mismatch"
        );
        assertEq(
            cBpsOrder,
            TEST_PROTOCOL_COLLATERAL_BUY_FEE_BPS,
            "Buy (order): Collateral BPS mismatch"
        );
        assertEq(
            iBpsOrder,
            TEST_PROTOCOL_ISSUANCE_BUY_FEE_BPS,
            "Buy (order): Issuance BPS mismatch"
        );
    }

    function testGetFunctionFeesAndTreasuryAddresses_SellSelectors_ReturnsCachedValues(
    ) public {
        // Arrange
        bytes4 calculateSaleReturnSelector =
            fmBcDiscrete.calculateSaleReturn.selector;
        bytes4 sellOrderSelector =
            bytes4(keccak256(bytes("_sellOrder(address,uint,uint)")));

        // Act & Assert for calculateSaleReturn.selector
        (
            address cTreasuryCalc,
            address iTreasuryCalc,
            uint cBpsCalc,
            uint iBpsCalc
        ) = fmBcDiscrete.exposed_getFunctionFeesAndTreasuryAddresses(
            calculateSaleReturnSelector
        );

        assertEq(
            cTreasuryCalc,
            TEST_PROTOCOL_TREASURY,
            "Sell (calc): Collateral treasury mismatch"
        );
        assertEq(
            iTreasuryCalc,
            TEST_PROTOCOL_TREASURY,
            "Sell (calc): Issuance treasury mismatch"
        );
        assertEq(
            cBpsCalc,
            TEST_PROTOCOL_COLLATERAL_SELL_FEE_BPS,
            "Sell (calc): Collateral BPS mismatch"
        );
        assertEq(
            iBpsCalc,
            TEST_PROTOCOL_ISSUANCE_SELL_FEE_BPS,
            "Sell (calc): Issuance BPS mismatch"
        );

        // Act & Assert for _sellOrder.selector
        (
            address cTreasuryOrder,
            address iTreasuryOrder,
            uint cBpsOrder,
            uint iBpsOrder
        ) = fmBcDiscrete.exposed_getFunctionFeesAndTreasuryAddresses(
            sellOrderSelector
        );

        assertEq(
            cTreasuryOrder,
            TEST_PROTOCOL_TREASURY,
            "Sell (order): Collateral treasury mismatch"
        );
        assertEq(
            iTreasuryOrder,
            TEST_PROTOCOL_TREASURY,
            "Sell (order): Issuance treasury mismatch"
        );
        assertEq(
            cBpsOrder,
            TEST_PROTOCOL_COLLATERAL_SELL_FEE_BPS,
            "Sell (order): Collateral BPS mismatch"
        );
        assertEq(
            iBpsOrder,
            TEST_PROTOCOL_ISSUANCE_SELL_FEE_BPS,
            "Sell (order): Issuance BPS mismatch"
        );
    }

    function testGetFunctionFeesAndTreasuryAddresses_OtherSelector_FallsBackToSuper(
    ) public {
        // For testing fallback to super._getFunctionFeesAndTreasuryAddresses
        uint TEST_OTHER_COLLATERAL_FEE_BPS = 77;
        uint TEST_OTHER_ISSUANCE_FEE_BPS = 88;
        bytes4 OTHER_SELECTOR =
            bytes4(keccak256(bytes("someOtherFunctionSelectorNotCached()")));

        // Configure FeeManager for a selector NOT explicitly handled by the cache, to test fallback
        feeManager.setCollateralWorkflowFee(
            address(_orchestrator),
            address(fmBcDiscrete),
            OTHER_SELECTOR,
            true,
            TEST_OTHER_COLLATERAL_FEE_BPS
        );
        feeManager.setIssuanceWorkflowFee(
            address(_orchestrator),
            address(fmBcDiscrete),
            OTHER_SELECTOR,
            true,
            TEST_OTHER_ISSUANCE_FEE_BPS
        );

        // Act
        (address cTreasury, address iTreasury, uint cBps, uint iBps) =
        fmBcDiscrete.exposed_getFunctionFeesAndTreasuryAddresses(OTHER_SELECTOR);

        // Assert - Values should come directly from FeeManager via super call
        assertEq(
            cTreasury,
            TEST_PROTOCOL_TREASURY,
            "Other: Collateral treasury mismatch (fallback)"
        );
        // Note: FeeManager_v1 uses one treasury per workflow, so issuanceTreasury will also be TEST_PROTOCOL_TREASURY.
        assertEq(
            iTreasury,
            TEST_PROTOCOL_TREASURY,
            "Other: Issuance treasury mismatch (fallback)"
        );
        assertEq(
            cBps,
            TEST_OTHER_COLLATERAL_FEE_BPS,
            "Other: Collateral BPS mismatch (fallback)"
        );
        assertEq(
            iBps,
            TEST_OTHER_ISSUANCE_FEE_BPS,
            "Other: Issuance BPS mismatch (fallback)"
        );
    }

    /* Test _getBuyFee() (exposed)
        └── Given the contract is initialized
            └── When exposed_getBuyFee() is called
                └── Then it should return the PROJECT_BUY_FEE_BPS constant
    */
    function testGetBuyFee_ReturnsProjectConstant() public {
        assertEq(
            fmBcDiscrete.exposed_getBuyFee(),
            TEST_PROJECT_BUY_FEE_BPS,
            "Incorrect buy fee returned"
        );
    }

    /* Test _getSellFee() (exposed)
        └── Given the contract is initialized
            └── When exposed_getSellFee() is called
                └── Then it should return the PROJECT_SELL_FEE_BPS constant
    */
    function testGetSellFee_ReturnsProjectConstant() public {
        assertEq(
            fmBcDiscrete.exposed_getSellFee(),
            TEST_PROJECT_SELL_FEE_BPS,
            "Incorrect sell fee returned"
        );
    }

    /* Test buyFor()
    └── Given the buy operation is open
        └── And the buyer has sufficient collateral and has approved the FM
            └── When buyFor() is called
                ├── Then (Collateral Token Movements):
                │   └── And the buyer's collateral balance should decrease by the deposit amount
                │   └── And the FM's collateral balance should increase by the net deposit (deposit - protocol collateral fee)
                │   └── And the protocol treasury's collateral balance should increase by the protocol collateral fee
                ├── Then (Issuance Token Minting and Supply):
                │   └── And the receiver should be minted the net issuance tokens
                │   └── And the protocol treasury should be minted the issuance protocol fee tokens
                │   └── And the total supply of issuance tokens should increase by the sum of net issuance to receiver and issuance protocol fee
                ├── Then (Fee and Virtual Supply Accounting):
                │   └── And the FM's projectCollateralFeeCollected should increase by the project collateral fee amount
                │   └── And the FM's virtualCollateralSupply should increase by the net deposit amount (deposit - protocol collateral fee - project collateral fee)
                └── Then (Event Emissions):
                    └── And it should emit a TokensBought event with correct parameters
                    └── And it should emit a VirtualCollateralAmountAdded event with correct parameters
    */
    function testBuyFor_CollateralTokenMovements() public {
        (uint expectedCollateralProtocolFee,,,,) = helper_prepareBuyForTest();

        uint initialBuyerCollateral = orchestratorToken.balanceOf(address(this));
        uint initialFmCollateral =
            orchestratorToken.balanceOf(address(fmBcDiscrete));
        uint initialTreasuryCollateral =
            orchestratorToken.balanceOf(TEST_PROTOCOL_TREASURY);

        fmBcDiscrete.buyFor(
            address(this), collateralAmountIn, minIssuanceAmountOut
        );

        assertEq(
            orchestratorToken.balanceOf(address(this)),
            initialBuyerCollateral - collateralAmountIn,
            "Buyer collateral after"
        );
        assertEq(
            orchestratorToken.balanceOf(address(fmBcDiscrete)),
            initialFmCollateral + collateralAmountIn
                - expectedCollateralProtocolFee,
            "FM collateral after"
        );
        assertEq(
            orchestratorToken.balanceOf(TEST_PROTOCOL_TREASURY),
            initialTreasuryCollateral + expectedCollateralProtocolFee,
            "Treasury collateral after"
        );
    }

    function testBuyFor_IssuanceTokenMintingAndSupply() public {
        (
            ,
            ,
            ,
            uint expectedNetIssuanceToReceiver,
            uint expectedIssuanceProtocolFee
        ) = helper_prepareBuyForTest();

        uint initialReceiverIssuance = issuanceToken.balanceOf(address(this));
        uint initialTreasuryIssuance =
            issuanceToken.balanceOf(TEST_PROTOCOL_TREASURY);
        uint initialTotalIssuanceSupply = issuanceToken.totalSupply();

        fmBcDiscrete.buyFor(
            address(this), collateralAmountIn, minIssuanceAmountOut
        );

        assertEq(
            issuanceToken.balanceOf(address(this)),
            initialReceiverIssuance + expectedNetIssuanceToReceiver,
            "Receiver issuance after"
        );
        assertEq(
            issuanceToken.balanceOf(TEST_PROTOCOL_TREASURY),
            initialTreasuryIssuance + expectedIssuanceProtocolFee,
            "Treasury issuance after"
        );
        assertEq(
            issuanceToken.totalSupply(),
            initialTotalIssuanceSupply + expectedNetIssuanceToReceiver
                + expectedIssuanceProtocolFee,
            "Total issuance supply after"
        );
    }

    function testBuyFor_FeeAndVirtualSupplyAccounting() public {
        (, uint expectedProjectCollateralFee, uint netDepositForPurchase,,) =
            helper_prepareBuyForTest();

        uint initialFmProjectFeeCollected =
            fmBcDiscrete.projectCollateralFeeCollected();
        uint initialVirtualCollateralSupply =
            fmBcDiscrete.getVirtualCollateralSupply();

        fmBcDiscrete.buyFor(
            address(this), collateralAmountIn, minIssuanceAmountOut
        );

        assertEq(
            fmBcDiscrete.projectCollateralFeeCollected(),
            initialFmProjectFeeCollected + expectedProjectCollateralFee,
            "Project fee collected after"
        );
        assertEq(
            fmBcDiscrete.getVirtualCollateralSupply(),
            initialVirtualCollateralSupply + netDepositForPurchase,
            "Virtual collateral supply after"
        );
    }

    function testBuyFor_EventEmissions() public {
        (,, uint netDepositForPurchase, uint expectedNetIssuanceToReceiver,) =
            helper_prepareBuyForTest();
        uint initialVirtualCollateralSupply =
            fmBcDiscrete.getVirtualCollateralSupply();

        vm.expectEmit(true, true, true, true, address(fmBcDiscrete));
        emit IBondingCurveBase_v1.TokensBought(
            address(this),
            collateralAmountIn,
            expectedNetIssuanceToReceiver,
            address(this)
        );

        vm.expectEmit(true, true, false, false, address(fmBcDiscrete));
        emit IVirtualCollateralSupplyBase_v1.VirtualCollateralAmountAdded(
            netDepositForPurchase,
            initialVirtualCollateralSupply + netDepositForPurchase
        );

        fmBcDiscrete.buyFor(
            address(this), collateralAmountIn, minIssuanceAmountOut
        );
    }

    // =========================================================================
    // Test: sellTo()

    /* Test sellTo()
    └── Given the sell operation is open
        └── And the seller has sufficient issuance tokens and has approved the FM
            └── When sellTo() is called
                ├── Then (Issuance Token Movements):
                │   └── And the seller's issuance balance should decrease by the deposit amount
                │   └── And the FM should burn the net deposit of issuance tokens (deposit - protocol issuance fee)
                │   └── And the protocol treasury should be minted the issuance protocol fee tokens (if applicable on sell)
                │   └── And the total supply of issuance tokens should decrease by the net deposit amount
                ├── Then (Collateral Token Movements):
                │   └── And the receiver's collateral balance should increase by the net collateral out
                │   └── And the FM's collateral balance should decrease by the total collateral moved out (net to receiver + protocol collateral fee)
                │   └── And the protocol treasury's collateral balance should increase by the protocol collateral fee
                ├── Then (Fee and Virtual Supply Accounting):
                │   └── And the FM's projectCollateralFeeCollected should increase by the project collateral fee amount
                │   └── And the FM's virtualCollateralSupply should decrease by the total collateral moved out
                └── Then (Event Emissions):
                    └── And it should emit a TokensSold event with correct parameters
                    └── And it should emit a VirtualCollateralAmountSubtracted event with correct parameters
    */

    function testSellTo_IssuanceTokenMovements() public {
        (
            uint depositAmount, // Issuance tokens to sell
            , // minCollateralAmountOut
            uint expectedIssuanceProtocolFee, // Fee on issuance tokens
            , // expectedCollateralProtocolFee, // Fee on collateral tokens
            , // expectedProjectCollateralFee, // Project fee on collateral
            , // netCollateralToReceiver
            uint netIssuanceToBurn // depositAmount - expectedIssuanceProtocolFee
        ) = helper_prepareSellToTest();

        uint initialSellerIssuance = issuanceToken.balanceOf(address(this));
        uint initialTreasuryIssuance =
            issuanceToken.balanceOf(TEST_PROTOCOL_TREASURY);
        uint initialTotalIssuanceSupply = issuanceToken.totalSupply();

        fmBcDiscrete.sellTo(address(this), depositAmount, 1); // minAmountOut = 1 wei

        assertEq(
            issuanceToken.balanceOf(address(this)),
            initialSellerIssuance - depositAmount,
            "Seller issuance after"
        );
        assertEq(
            issuanceToken.balanceOf(TEST_PROTOCOL_TREASURY),
            initialTreasuryIssuance + expectedIssuanceProtocolFee,
            "Treasury issuance after (protocol fee)"
        );
        assertEq(
            issuanceToken.totalSupply(),
            initialTotalIssuanceSupply - netIssuanceToBurn,
            "Total issuance supply after (net burn)"
        );
    }

    function testSellTo_CollateralTokenMovements() public {
        (
            uint depositAmount, // Issuance tokens to sell
            uint minCollateralAmountOut,
            , // expectedIssuanceProtocolFee, // Fee on issuance tokens
            uint expectedCollateralProtocolFee, // Fee on collateral tokens
            , // expectedProjectCollateralFee, // Project fee on collateral
            uint netCollateralToReceiver, // netIssuanceToBurn // depositAmount - expectedIssuanceProtocolFee
        ) = helper_prepareSellToTest();

        uint initialReceiverCollateral =
            orchestratorToken.balanceOf(address(this));
        uint initialFmCollateral =
            orchestratorToken.balanceOf(address(fmBcDiscrete));
        uint initialTreasuryCollateral =
            orchestratorToken.balanceOf(TEST_PROTOCOL_TREASURY);

        fmBcDiscrete.sellTo(
            address(this), depositAmount, minCollateralAmountOut
        );

        assertEq(
            orchestratorToken.balanceOf(address(this)), // Receiver is self
            initialReceiverCollateral + netCollateralToReceiver,
            "Receiver collateral after"
        );
        assertEq(
            orchestratorToken.balanceOf(address(fmBcDiscrete)),
            initialFmCollateral
                - (netCollateralToReceiver + expectedCollateralProtocolFee),
            "FM collateral after"
        );
        assertEq(
            orchestratorToken.balanceOf(TEST_PROTOCOL_TREASURY),
            initialTreasuryCollateral + expectedCollateralProtocolFee,
            "Treasury collateral after (protocol fee)"
        );
    }

    function testSellTo_FeeAndVirtualSupplyAccounting() public {
        (
            uint depositAmount, // Issuance tokens to sell
            uint minCollateralAmountOut,
            , // expectedIssuanceProtocolFee, // Fee on issuance tokens
            uint expectedCollateralProtocolFee, // Fee on collateral tokens
            uint expectedProjectCollateralFee, // Project fee on collateral
            uint netCollateralToReceiver, // netIssuanceToBurn // depositAmount - expectedIssuanceProtocolFee
        ) = helper_prepareSellToTest();

        uint initialFmProjectFeeCollected =
            fmBcDiscrete.projectCollateralFeeCollected();
        uint initialVirtualCollateralSupply =
            fmBcDiscrete.getVirtualCollateralSupply();
        uint totalCollateralMovedOut = netCollateralToReceiver
            + expectedCollateralProtocolFee + expectedProjectCollateralFee;

        fmBcDiscrete.sellTo(
            address(this), depositAmount, minCollateralAmountOut
        );

        assertEq(
            fmBcDiscrete.projectCollateralFeeCollected(),
            initialFmProjectFeeCollected + expectedProjectCollateralFee,
            "Project fee collected after sell"
        );
        assertEq(
            fmBcDiscrete.getVirtualCollateralSupply(),
            initialVirtualCollateralSupply - totalCollateralMovedOut,
            "Virtual collateral supply after sell"
        );
    }

    function testSellTo_EventEmissions() public {
        (
            uint depositAmount, // Issuance tokens to sell
            uint minCollateralAmountOut,
            , // expectedIssuanceProtocolFee, // Fee on issuance tokens
            uint expectedCollateralProtocolFee, // Fee on collateral tokens
            uint expectedProjectCollateralFee, // Project fee on collateral
            uint netCollateralToReceiver, // netIssuanceToBurn // depositAmount - expectedIssuanceProtocolFee
        ) = helper_prepareSellToTest();

        uint initialVirtualCollateralSupply =
            fmBcDiscrete.getVirtualCollateralSupply();
        uint totalCollateralMovedOut = netCollateralToReceiver
            + expectedCollateralProtocolFee + expectedProjectCollateralFee;

        vm.expectEmit(true, true, true, true, address(fmBcDiscrete));
        emit IRedeemingBondingCurveBase_v1.TokensSold(
            address(this), // receiver
            depositAmount,
            netCollateralToReceiver,
            address(this)
        );

        vm.expectEmit(true, true, false, false, address(fmBcDiscrete));
        emit IVirtualCollateralSupplyBase_v1.VirtualCollateralAmountSubtracted(
            totalCollateralMovedOut,
            initialVirtualCollateralSupply - totalCollateralMovedOut
        );

        fmBcDiscrete.sellTo(
            address(this), depositAmount, minCollateralAmountOut
        );
    }

    // =========================================================================
    // Helpers

    function _ensureTotalIssuanceSupply(uint _targetSupply) internal {
        uint currentTotalSupply = issuanceToken.totalSupply();
        if (_targetSupply > currentTotalSupply) {
            issuanceToken.mint(
                address(this), _targetSupply - currentTotalSupply
            );
        } else if (_targetSupply < currentTotalSupply) {
            uint amountToBurn = currentTotalSupply - _targetSupply;
            // Ensure address(this) has enough tokens to burn.
            // Mint to self if necessary, as address(this) is a minter.
            if (issuanceToken.balanceOf(address(this)) < amountToBurn) {
                issuanceToken.mint(
                    address(this),
                    amountToBurn - issuanceToken.balanceOf(address(this))
                );
            }
            issuanceToken.burn(address(this), amountToBurn);
        }
        assertEq(
            issuanceToken.totalSupply(),
            _targetSupply,
            "Failed to ensure total issuance supply"
        );
    }

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

    function helper_prepareSellToTest()
        internal
        returns (
            uint depositAmount, // Issuance tokens to sell
            uint minCollateralAmountOut,
            uint expectedIssuanceProtocolFee, // Fee on issuance tokens
            uint expectedCollateralProtocolFee, // Fee on collateral tokens
            uint expectedProjectCollateralFee, // Project fee on collateral
            uint netCollateralToReceiver,
            uint netIssuanceToBurn // depositAmount - expectedIssuanceProtocolFee
        )
    {
        fmBcDiscrete.openSell();
        assertTrue(fmBcDiscrete.sellIsOpen(), "Selling should be open");

        depositAmount = 20 ether; // Example amount of issuance tokens to sell
        minCollateralAmountOut = 1 wei; // Minimal expectation for collateral

        // Ensure FM has some collateral to pay out and seller has issuance tokens
        orchestratorToken.mint(address(fmBcDiscrete), 100 ether); // FM has collateral
        fmBcDiscrete.exposed_setVirtualCollateralSupply(100 ether); // Sync virtual supply

        _ensureTotalIssuanceSupply(depositAmount * 2); // Make sure total supply is ample
        issuanceToken.mint(address(this), depositAmount); // Seller gets tokens
        issuanceToken.approve(address(fmBcDiscrete), depositAmount); // Seller approves FM

        // Calculate expected fees and net amounts based on current FM state and constants
        // Stage 1: Fees on Deposited Issuance Tokens (Protocol Fee)
        expectedIssuanceProtocolFee =
            (depositAmount * TEST_PROTOCOL_ISSUANCE_SELL_FEE_BPS) / 10_000;
        netIssuanceToBurn = depositAmount - expectedIssuanceProtocolFee; // This is what's used in formula

        // Stage 2: Calculate Gross Collateral from Formula
        uint grossCollateralOut =
            fmBcDiscrete.exposed_redeemTokensFormulaWrapper(netIssuanceToBurn);

        // Stage 3: Fees on Gross Collateral Out (Protocol and Project Fees)
        expectedCollateralProtocolFee = (
            grossCollateralOut * TEST_PROTOCOL_COLLATERAL_SELL_FEE_BPS
        ) / 10_000;
        expectedProjectCollateralFee =
            (grossCollateralOut * TEST_PROJECT_SELL_FEE_BPS) / 10_000; // Using TEST_PROJECT_SELL_FEE_BPS

        netCollateralToReceiver = grossCollateralOut
            - expectedCollateralProtocolFee - expectedProjectCollateralFee;

        assertTrue(
            netCollateralToReceiver >= minCollateralAmountOut,
            "Calculated net collateral is less than minAmountOut for test setup"
        );
    }

    function helper_prepareBuyForTest()
        internal
        returns (
            uint expectedCollateralProtocolFee,
            uint expectedProjectCollateralFee,
            uint netDepositForPurchase,
            uint expectedNetIssuanceToReceiver,
            uint expectedIssuanceProtocolFee
        )
    {
        fmBcDiscrete.openBuy();
        assertTrue(fmBcDiscrete.buyIsOpen(), "Buying should be open");

        orchestratorToken.mint(address(this), collateralAmountIn);
        orchestratorToken.approve(address(fmBcDiscrete), collateralAmountIn);

        expectedCollateralProtocolFee =
            (collateralAmountIn * TEST_PROTOCOL_COLLATERAL_BUY_FEE_BPS) / 10_000;
        expectedProjectCollateralFee =
            (collateralAmountIn * TEST_PROJECT_BUY_FEE_BPS) / 10_000;
        netDepositForPurchase = collateralAmountIn
            - expectedCollateralProtocolFee - expectedProjectCollateralFee;
        uint grossIssuance = fmBcDiscrete.exposed_issueTokensFormulaWrapper(
            netDepositForPurchase
        );
        expectedIssuanceProtocolFee =
            (grossIssuance * TEST_PROTOCOL_ISSUANCE_BUY_FEE_BPS) / 10_000;
        expectedNetIssuanceToReceiver =
            grossIssuance - expectedIssuanceProtocolFee;

        assertTrue(
            expectedNetIssuanceToReceiver >= minIssuanceAmountOut,
            "Calculated net issuance is less than minAmountOut"
        );
    }
}
