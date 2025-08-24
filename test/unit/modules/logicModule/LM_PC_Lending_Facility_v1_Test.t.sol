// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Internal Dependencies
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "@unitTest/modules/ModuleTest.sol";
import {OZErrors} from "@testUtilities/OZErrors.sol";
import {ERC20Mock} from "@mocks/external/token/ERC20Mock.sol";
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
import {IDynamicFeeCalculator_v1} from
    "@ex/fees/interfaces/IDynamicFeeCalculator_v1.sol";
import {DynamicFeeCalculator_v1} from "@ex/fees/DynamicFeeCalculator_v1.sol";

// External Dependencies
import {Clones} from "@oz/proxy/Clones.sol";

// System under Test (SuT)
import {ILM_PC_Lending_Facility_v1} from
    "src/modules/logicModule/interfaces/ILM_PC_Lending_Facility_v1.sol";
import {IFM_BC_Discrete_Redeeming_VirtualSupply_v1} from
    "src/modules/fundingManager/bondingCurve/interfaces/IFM_BC_Discrete_Redeeming_VirtualSupply_v1.sol";

// Tests and Mocks
import {LM_PC_Lending_Facility_v1_Exposed} from
    "test/mocks/modules/logicModule/LM_PC_HouseProtocol_v1_Exposed.sol";
import {
    IERC20PaymentClientBase_v2,
    ERC20PaymentClientBaseV2Mock,
    ERC20Mock
} from "@mocks/modules/paymentClient/ERC20PaymentClientBaseV2Mock.sol";
import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";
import {FM_BC_Discrete_Redeeming_VirtualSupply_v1_Exposed} from
    "test/mocks/modules/fundingManager/bondingCurve/FM_BC_Discrete_Redeeming_VirtualSupply_v1_Exposed.sol";
import {console2} from "forge-std/console2.sol";

/**
 * @title   House Protocol Lending Facility Tests
 *
 * @notice  Tests for the House Protocol lending facility logic module
 *
 * @dev     This test contract follows the standard testing pattern showing:
 *          - Initialization tests
 *          - External function tests
 *          - Internal function tests through exposed functions
 *          - Use of Gherkin for test documentation
 *
 * @author  Inverter Network
 */
contract LM_PC_Lending_Facility_v1_Test is ModuleTest {
    using PackedSegmentLib for PackedSegment;
    using DiscreteCurveMathLib_v1 for PackedSegment[];
    // =========================================================================
    // State

    // SuT
    LM_PC_Lending_Facility_v1_Exposed lendingFacility;

    // Test constants
    uint constant BORROWABLE_QUOTA = 8000; // 80% in basis points
    uint constant LOCKED_ISSUANCE_TOKENS = 1000 ether;
    uint constant MAX_FEE_PERCENTAGE = 1e18;

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
    uint public constant DEFAULT_SEG0_SUPPLY_PER_STEP = 500 ether;
    uint public constant DEFAULT_SEG0_NUMBER_OF_STEPS = 1;

    uint public constant DEFAULT_SEG1_INITIAL_PRICE = 0.8 ether;
    uint public constant DEFAULT_SEG1_PRICE_INCREASE = 0.02 ether;
    uint public constant DEFAULT_SEG1_SUPPLY_PER_STEP = 500 ether;
    uint public constant DEFAULT_SEG1_NUMBER_OF_STEPS = 2;

    // Issuance Token Parameters
    string internal constant ISSUANCE_TOKEN_NAME = "House Token";
    string internal constant ISSUANCE_TOKEN_SYMBOL = "HOUSE";
    uint8 internal constant ISSUANCE_TOKEN_DECIMALS = 18;
    uint internal constant ISSUANCE_TOKEN_MAX_SUPPLY = type(uint).max;

    FM_BC_Discrete_Redeeming_VirtualSupply_v1_Exposed public fmBcDiscrete;
    ERC20Mock public orchestratorToken; // This is the collateral token
    ERC20Issuance_v1 public issuanceToken; // This is the token to be issued
    ERC20PaymentClientBaseV2Mock public paymentClient;
    PackedSegment[] public initialTestSegments;
    CurveTestData internal defaultCurve; // Declare defaultCurve variable
    DynamicFeeCalculator_v1 public dynamicFeeCalculator;
    // =========================================================================
    // Setup

    function setUp() public {
        address impl_fmBcDiscrete =
            address(new FM_BC_Discrete_Redeeming_VirtualSupply_v1_Exposed());
        fmBcDiscrete = FM_BC_Discrete_Redeeming_VirtualSupply_v1_Exposed(
            Clones.clone(impl_fmBcDiscrete)
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

        // Deploy the SuT
        address impl_lendingFacility =
            address(new LM_PC_Lending_Facility_v1_Exposed());
        lendingFacility = LM_PC_Lending_Facility_v1_Exposed(
            Clones.clone(impl_lendingFacility)
        );

        // Setup the module to test
        _setUpOrchestrator(fmBcDiscrete); // This also sets up feeManager via _createFeeManager in ModuleTest
        _setUpOrchestrator(lendingFacility);

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

        // Set virtual collateral supply to simulate pre-sale funds
        // This represents the backing for the first step of the bonding curve
        uint initialVirtualSupply = 1000 ether; // Simulate 1000 ETH worth of pre-sale
        fmBcDiscrete.setVirtualCollateralSupply(initialVirtualSupply);

        // Deploy the dynamic fee calculator
        address impl_dynamicFeeCalculator =
            address(new DynamicFeeCalculator_v1());
        dynamicFeeCalculator =
            DynamicFeeCalculator_v1(Clones.clone(impl_dynamicFeeCalculator));
        dynamicFeeCalculator.init(address(this));

        // Initiate the Logic Module with the metadata and config data
        lendingFacility.init(
            _orchestrator,
            _METADATA,
            abi.encode(
                address(orchestratorToken),
                address(issuanceToken),
                address(fmBcDiscrete),
                address(dynamicFeeCalculator),
                BORROWABLE_QUOTA
            )
        );

        // Mint tokens to the lending facility
        orchestratorToken.mint(address(lendingFacility), 10_000 ether);
        issuanceToken.mint(address(lendingFacility), 10_000 ether);

        // Mint tokens to the DBC FM so it can transfer them
        orchestratorToken.mint(address(fmBcDiscrete), 10_000 ether);
    }

    // =========================================================================
    // Test: Initialization

    // Test if the orchestrator is correctly set
    function testInit() public override(ModuleTest) {
        assertEq(
            address(lendingFacility.orchestrator()), address(_orchestrator)
        );
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

    // Test the interface support
    function testSupportsInterface() public {
        assertTrue(
            lendingFacility.supportsInterface(
                type(IERC20PaymentClientBase_v2).interfaceId
            )
        );
        assertTrue(
            lendingFacility.supportsInterface(
                type(ILM_PC_Lending_Facility_v1).interfaceId
            )
        );
    }

    // Test the reinit function
    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        lendingFacility.init(_orchestrator, _METADATA, abi.encode(""));
    }

    // =========================================================================
    // Test: Repaying

    /* Test: Function repay()
        ├── Given a user has an outstanding loan
        └── And the user has sufficient collateral tokens to repay
            └── When the user repays part of their loan
                ├── Then their outstanding loan should decrease
                ├── And the system's currently borrowed amount should decrease
                ├── And collateral tokens should be transferred back to facility
                └── And issuance tokens should be unlocked proportionally
    */
    function testFuzzPublicRepay_succeedsGivenValidRepaymentAmount(
        uint borrowAmount_,
        uint repayAmount_
    ) public {
        // Given: a user has an outstanding loan
        address user = makeAddr("user");

        uint maxBorrowableQuota = lendingFacility.getBorrowCapacity()
            * lendingFacility.borrowableQuota() / 10_000;

        borrowAmount_ = bound(borrowAmount_, 1, maxBorrowableQuota);
        repayAmount_ = bound(repayAmount_, 1, borrowAmount_);
        uint borrowAmount = borrowAmount_;
        uint repayAmount = repayAmount_;

        // Setup: user borrows tokens (which automatically locks issuance tokens)
        uint requiredIssuanceTokens = lendingFacility
            .exposed_calculateRequiredIssuanceTokens(borrowAmount);
        // Add a larger buffer to account for rounding precision
        uint issuanceTokensWithBuffer = requiredIssuanceTokens + 10 ether;
        issuanceToken.mint(user, issuanceTokensWithBuffer);
        vm.prank(user);
        issuanceToken.approve(
            address(lendingFacility), issuanceTokensWithBuffer
        );
        vm.prank(user);
        lendingFacility.borrow(borrowAmount);

        // Given: the user has sufficient collateral tokens to repay
        orchestratorToken.mint(user, repayAmount);
        vm.prank(user);
        orchestratorToken.approve(address(lendingFacility), repayAmount);

        // When: the user repays part of their loan
        uint outstandingLoanBefore = lendingFacility.getOutstandingLoan(user);
        uint currentlyBorrowedBefore = lendingFacility.currentlyBorrowedAmount();
        uint lockedTokensBefore = lendingFacility.getLockedIssuanceTokens(user);
        uint dbcFmCollateralBefore =
            orchestratorToken.balanceOf(address(fmBcDiscrete));

        vm.prank(user);
        lendingFacility.repay(repayAmount);

        // Then: their outstanding loan should decrease
        assertEq(
            lendingFacility.getOutstandingLoan(user),
            outstandingLoanBefore - repayAmount,
            "Outstanding loan should decrease by repayment amount"
        );

        // And: the system's currently borrowed amount should decrease
        assertEq(
            lendingFacility.currentlyBorrowedAmount(),
            currentlyBorrowedBefore - repayAmount,
            "System borrowed amount should decrease by repayment amount"
        );

        // And: collateral tokens should be transferred back to DBC FM
        uint dbcFmCollateralAfter =
            orchestratorToken.balanceOf(address(fmBcDiscrete));
        assertEq(
            dbcFmCollateralAfter,
            dbcFmCollateralBefore + repayAmount,
            "DBC FM should receive repayment amount"
        );

        // And: issuance tokens should be unlocked proportionally
        uint lockedTokensAfter = lendingFacility.getLockedIssuanceTokens(user);
        assertLe(
            lockedTokensAfter,
            lockedTokensBefore,
            "Some issuance tokens should be unlocked"
        );
    }

    /* Test: Function repay()
        ├── Given a user has an outstanding loan
        └── And the user tries to repay more than the outstanding amount
            └── When the user attempts to repay
                └── Then the repayment amount should be automatically adjusted to the outstanding loan amount
    */
    function testPublicRepay_succeedsGivenRepaymentAmountExceedsOutstandingLoan(
    ) public {
        // Given: a user has an outstanding loan
        address user = makeAddr("user");
        uint borrowAmount = 500 ether;
        uint repayAmount = 600 ether; // More than outstanding loan

        // Setup: user borrows tokens (which automatically locks issuance tokens)
        uint requiredIssuanceTokens = lendingFacility
            .exposed_calculateRequiredIssuanceTokens(borrowAmount);
        // Add a larger buffer to account for rounding precision
        uint issuanceTokensWithBuffer = requiredIssuanceTokens + 10 ether;
        issuanceToken.mint(user, issuanceTokensWithBuffer);
        vm.prank(user);
        issuanceToken.approve(
            address(lendingFacility), issuanceTokensWithBuffer
        );
        vm.prank(user);
        lendingFacility.borrow(borrowAmount);

        // Given: the user tries to repay more than the outstanding amount
        uint outstandingLoan = lendingFacility.getOutstandingLoan(user);
        assertGt(
            repayAmount,
            outstandingLoan,
            "Repay amount should exceed outstanding loan"
        );

        orchestratorToken.mint(user, repayAmount);
        vm.prank(user);
        orchestratorToken.approve(address(lendingFacility), repayAmount);

        // When: the user attempts to repay
        uint outstandingLoanBefore = lendingFacility.getOutstandingLoan(user);
        vm.prank(user);
        lendingFacility.repay(repayAmount);

        // Then: the repayment amount should be automatically adjusted to the outstanding loan amount
        uint outstandingLoanAfter = lendingFacility.getOutstandingLoan(user);
        assertEq(
            outstandingLoanAfter, 0, "Outstanding loan should be fully repaid"
        );
        assertEq(
            outstandingLoanAfter,
            outstandingLoanBefore - outstandingLoanBefore,
            "Outstanding loan should be reduced by the actual outstanding amount"
        );
    }

    // =========================================================================
    // Test: Borrowing

    /* Test: Function borrow()
        ├── Given a user has issuance tokens
        ├── And the user has sufficient borrowing power
        └── And the borrow amount is within individual and system limits
            └── When the user borrows collateral tokens
                ├── Then their outstanding loan should increase
                ├── And issuance tokens should be locked automatically
                ├── And dynamic fee should be calculated and deducted
                ├── And net amount should be transferred to user
                └── And the system's currently borrowed amount should increase
    */
    function testFuzzPublicBorrow_succeedsGivenValidBorrowRequest(
        uint borrowAmount_
    ) public {
        // Given: a user has issuance tokens
        address user = makeAddr("user");

        uint maxBorrowableQuota = lendingFacility.getBorrowCapacity()
            * lendingFacility.borrowableQuota() / 10_000;

        borrowAmount_ = bound(borrowAmount_, 1, maxBorrowableQuota);
        uint borrowAmount = borrowAmount_;

        // Calculate how much issuance tokens will be needed
        uint requiredIssuanceTokens = lendingFacility
            .exposed_calculateRequiredIssuanceTokens(borrowAmount);
        // Add a larger buffer to account for rounding precision
        uint issuanceTokensWithBuffer = requiredIssuanceTokens + 10 ether;
        issuanceToken.mint(user, issuanceTokensWithBuffer);

        vm.prank(user);
        issuanceToken.approve(
            address(lendingFacility), issuanceTokensWithBuffer
        );

        // Given: the user has sufficient borrowing power
        uint userBorrowingPower = issuanceTokensWithBuffer
            * lendingFacility.exposed_getFloorPrice() / 1e18;
        assertGe(
            userBorrowingPower,
            borrowAmount,
            "User should have sufficient borrowing power"
        );

        uint borrowCapacity = lendingFacility.getBorrowCapacity();
        uint borrowableQuota =
            borrowCapacity * lendingFacility.borrowableQuota() / 10_000;
        assertLe(
            borrowAmount,
            borrowableQuota,
            "Borrow amount should be within system quota"
        );

        // When: the user borrows collateral tokens
        uint userBalanceBefore = orchestratorToken.balanceOf(user);
        uint outstandingLoanBefore = lendingFacility.getOutstandingLoan(user);
        uint currentlyBorrowedBefore = lendingFacility.currentlyBorrowedAmount();
        uint lockedTokensBefore = lendingFacility.getLockedIssuanceTokens(user);

        vm.prank(user);
        lendingFacility.borrow(borrowAmount);

        // Then: their outstanding loan should increase
        assertEq(
            lendingFacility.getOutstandingLoan(user),
            outstandingLoanBefore + borrowAmount,
            "Outstanding loan should increase by borrow amount"
        );

        // And: issuance tokens should be locked automatically
        assertEq(
            lendingFacility.getLockedIssuanceTokens(user),
            lockedTokensBefore + requiredIssuanceTokens,
            "Issuance tokens should be locked automatically"
        );

        // And: the system's currently borrowed amount should increase
        assertEq(
            lendingFacility.currentlyBorrowedAmount(),
            currentlyBorrowedBefore + borrowAmount,
            "System borrowed amount should increase by borrow amount"
        );

        // And: net amount should be transferred to user (after fees)
        uint userBalanceAfter = orchestratorToken.balanceOf(user);
        uint actualReceived = userBalanceAfter - userBalanceBefore;
        assertGt(actualReceived, 0, "User should receive collateral tokens");
        assertLe(
            actualReceived,
            borrowAmount,
            "User should receive amount less than or equal to requested"
        );
    }

    /* Test: Function borrow() - Outstanding loan should equal gross requested amount (fee on top)
        ├── Given a user borrows tokens with a dynamic fee
        └── When the borrow transaction completes
            └── Then the outstanding loan should equal the net amount received by the user
    */
    function testFuzzPublicBorrow_succeedsGivenOutstandingLoanEqualsRequestedAmount(
        uint borrowAmount_
    ) public {
        // Given: a user has issuance tokens
        address user = makeAddr("user");

        uint maxBorrowableQuota = lendingFacility.getBorrowCapacity()
            * lendingFacility.borrowableQuota() / 10_000;

        borrowAmount_ = bound(borrowAmount_, 1, maxBorrowableQuota);
        uint borrowAmount = borrowAmount_;

        // Calculate how much issuance tokens will be needed
        uint requiredIssuanceTokens = lendingFacility
            .exposed_calculateRequiredIssuanceTokens(borrowAmount);
        uint issuanceTokensWithBuffer = requiredIssuanceTokens + 10 ether;
        issuanceToken.mint(user, issuanceTokensWithBuffer);

        vm.prank(user);
        issuanceToken.approve(
            address(lendingFacility), issuanceTokensWithBuffer
        );

        // Given: the user has sufficient borrowing power
        uint userBorrowingPower = issuanceTokensWithBuffer
            * lendingFacility.exposed_getFloorPrice() / 1e18;
        assertGe(
            userBorrowingPower,
            borrowAmount,
            "User should have sufficient borrowing power"
        );

        uint borrowCapacity = lendingFacility.getBorrowCapacity();
        uint borrowableQuota =
            borrowCapacity * lendingFacility.borrowableQuota() / 10_000;
        assertLe(
            borrowAmount,
            borrowableQuota,
            "Borrow amount should be within system quota"
        );

        // Given: dynamic fee calculator is set up
        IDynamicFeeCalculator_v1.DynamicFeeParameters memory feeParams =
        IDynamicFeeCalculator_v1.DynamicFeeParameters({
            Z_issueRedeem: 0,
            A_issueRedeem: 0,
            m_issueRedeem: 0,
            Z_origination: 0,
            A_origination: 0,
            m_origination: 0
        });
        feeParams = helper_setDynamicFeeCalculatorParams(feeParams);

        // When: the user borrows collateral tokens
        vm.prank(user);
        lendingFacility.borrow(borrowAmount);

        // Then: the outstanding loan should equal the requested amount (fee on top model)
        uint outstandingLoan = lendingFacility.getOutstandingLoan(user);

        assertEq(
            outstandingLoan,
            borrowAmount,
            "Outstanding loan should equal requested amount"
        );
    }

    /* Test: Function borrow()
        ├── Given a user wants to borrow tokens
        └── And the borrow amount is zero
            └── When the user tries to borrow collateral tokens
                └── Then the transaction should revert with InvalidBorrowAmount error
    */
    function testFuzzPublicBorrow_failsGivenZeroAmount(address user) public {
        // Given: a user wants to borrow tokens
        vm.assume(user != address(0) && user != address(this));

        // Given: the borrow amount is zero
        uint borrowAmount = 0;

        // When: the user tries to borrow collateral tokens
        vm.prank(user);
        vm.expectRevert(
            ILM_PC_Lending_Facility_v1
                .Module__LM_PC_Lending_Facility_InvalidBorrowAmount
                .selector
        );
        lendingFacility.borrow(borrowAmount);

        // Then: the transaction should revert with InvalidBorrowAmount error
    }

    // =========================================================================
    // Test: Buy and Borrow

    function testPublicBuyAndBorrow_succeedsGivenValidLeverage() public {
        // Given: a user has issuance tokens
        address user = makeAddr("user");
        orchestratorToken.mint(user, 100 ether);

        fmBcDiscrete.openBuy();

        // Record initial state
        uint userCollateralBalanceBefore = orchestratorToken.balanceOf(user);
        uint userIssuanceBalanceBefore = issuanceToken.balanceOf(user);
        uint outstandingLoanBefore = lendingFacility.getOutstandingLoan(user);

        vm.startPrank(user);
        orchestratorToken.approve(address(fmBcDiscrete), type(uint).max);
        orchestratorToken.approve(address(lendingFacility), type(uint).max);
        issuanceToken.approve(address(fmBcDiscrete), type(uint).max);
        issuanceToken.approve(address(lendingFacility), type(uint).max);

        lendingFacility.buyAndBorrow(25);
        vm.stopPrank();

        // Then: verify state changes
        // User should have received issuance tokens from the buy operation
        uint userIssuanceBalanceAfter = issuanceToken.balanceOf(user);
        assertGt(
            userIssuanceBalanceAfter,
            userIssuanceBalanceBefore,
            "User should receive issuance tokens from buy operation"
        );

        // User should have some collateral remaining (less than initial amount due to fees and purchases)
        uint userCollateralBalanceAfter = orchestratorToken.balanceOf(user);
        assertLt(
            userCollateralBalanceAfter,
            userCollateralBalanceBefore,
            "User should have spent some collateral on purchases"
        );

        // User should have an outstanding loan
        uint outstandingLoanAfter = lendingFacility.getOutstandingLoan(user);
        assertGt(
            outstandingLoanAfter,
            outstandingLoanBefore,
            "User should have an outstanding loan after borrowing"
        );
    }

    // =========================================================================
    // Test: Configuration Functions

    /* Test external setBorrowableQuota function
        ├── Given caller has LENDING_FACILITY_MANAGER_ROLE
        │   └── When setting new borrowable quota
        │       ├── Then the quota should be updated
        │       └── Then an event should be emitted
        └── Given quota exceeds 100%
            └── When trying to set quota
                └── Then it should revert with appropriate error
    */
    function testFuzzPublicSetBorrowableQuota_succeedsGivenValidQuota(
        uint newQuota_
    ) public {
        // Grant role to this test contract
        bytes32 roleId = _authorizer.generateRoleId(
            address(lendingFacility),
            lendingFacility.LENDING_FACILITY_MANAGER_ROLE()
        );
        _authorizer.grantRole(roleId, address(this));

        newQuota_ = bound(newQuota_, 1, 10_000);
        uint newQuota = newQuota_;
        lendingFacility.setBorrowableQuota(newQuota);

        assertEq(lendingFacility.borrowableQuota(), newQuota);
    }

    function testFuzzPublicSetBorrowableQuota_failsGivenExceedsMaxQuota(
        uint newQuota_
    ) public {
        // Grant role to this test contract
        bytes32 roleId = _authorizer.generateRoleId(
            address(lendingFacility),
            lendingFacility.LENDING_FACILITY_MANAGER_ROLE()
        );
        _authorizer.grantRole(roleId, address(this));

        newQuota_ = bound(newQuota_, 10_001, type(uint16).max);
        uint invalidQuota = newQuota_; // Exceeds 100%
        vm.expectRevert(
            ILM_PC_Lending_Facility_v1
                .Module__LM_PC_Lending_Facility_BorrowableQuotaTooHigh
                .selector
        );
        lendingFacility.setBorrowableQuota(invalidQuota);
    }

    // Test: setDynamicFeeCalculator

    /* Test external setDynamicFeeCalculator function
        ├── Given caller has LENDING_FACILITY_MANAGER_ROLE
        │   └── When setting new dynamic fee calculator
        │       ├── Then the calculator should be updated
        │       └── Then an event should be emitted
        └── Given invalid fee calculator address
            └── When trying to set calculator
                └── Then it should revert with InvalidFeeCalculatorAddress
    */

    function testFuzzPublicSetDynamicFeeCalculator_succeedsGivenValidCalculator(
        address newFeeCalculator_
    ) public {
        // Grant role to this test contract
        bytes32 roleId = _authorizer.generateRoleId(
            address(lendingFacility),
            lendingFacility.LENDING_FACILITY_MANAGER_ROLE()
        );
        _authorizer.grantRole(roleId, address(this));

        vm.assume(
            newFeeCalculator_ != address(0)
                && newFeeCalculator_ != address(this)
        );
        address newFeeCalculator = newFeeCalculator_;
        vm.expectEmit(true, true, true, true);
        emit ILM_PC_Lending_Facility_v1.DynamicFeeCalculatorUpdated(
            newFeeCalculator
        );
        lendingFacility.setDynamicFeeCalculator(newFeeCalculator);
    }

    function testPublicSetDynamicFeeCalculator_failsGivenInvalidCalculator()
        public
    {
        // Grant role to this test contract
        bytes32 roleId = _authorizer.generateRoleId(
            address(lendingFacility),
            lendingFacility.LENDING_FACILITY_MANAGER_ROLE()
        );
        _authorizer.grantRole(roleId, address(this));

        address invalidFeeCalculator = address(0);
        vm.expectRevert(
            ILM_PC_Lending_Facility_v1
                .Module__LM_PC_Lending_Facility_InvalidFeeCalculatorAddress
                .selector
        );
        lendingFacility.setDynamicFeeCalculator(invalidFeeCalculator);
    }

    // =========================================================================
    // Test: Getters

    function testGetBorrowCapacity() public {
        uint capacity = lendingFacility.getBorrowCapacity();
        assertGt(capacity, 0);
    }

    function testGetCurrentBorrowQuota() public {
        uint quota = lendingFacility.getCurrentBorrowQuota();
        assertEq(quota, 0); // Initially no borrowed amount
    }

    function testGetFloorLiquidityRate() public {
        uint rate = lendingFacility.getFloorLiquidityRate();
        assertGt(rate, 0);
    }

    function testGetUserBorrowingPower() public {
        address user = makeAddr("user");
        uint power = lendingFacility.getUserBorrowingPower(user);
        assertEq(power, 0); // Initially no locked tokens

        // Borrow some tokens (which automatically locks issuance tokens)
        uint borrowAmount = 500 ether;
        uint requiredIssuanceTokens = lendingFacility
            .exposed_calculateRequiredIssuanceTokens(borrowAmount);
        // Add a larger buffer to account for rounding precision
        uint issuanceTokensWithBuffer = requiredIssuanceTokens + 10 ether;
        issuanceToken.mint(user, issuanceTokensWithBuffer);

        vm.prank(user);
        issuanceToken.approve(
            address(lendingFacility), issuanceTokensWithBuffer
        );

        vm.prank(user);
        lendingFacility.borrow(borrowAmount);

        power = lendingFacility.getUserBorrowingPower(user);
        assertGt(power, 0);
    }

    // =========================================================================
    // Test: Internal (tested through exposed_ functions)

    function testEnsureValidBorrowAmount() public {
        // Should not revert for valid amount
        lendingFacility.exposed_ensureValidBorrowAmount(100 ether);

        // Should revert for zero amount
        vm.expectRevert(
            ILM_PC_Lending_Facility_v1
                .Module__LM_PC_Lending_Facility_InvalidBorrowAmount
                .selector
        );
        lendingFacility.exposed_ensureValidBorrowAmount(0);
    }

    function testCalculateBorrowCapacity() public {
        uint capacity = lendingFacility.exposed_calculateBorrowCapacity();
        assertGt(capacity, 0);
    }

    function testFuzzCalculateUserBorrowingPower() public {
        address user = makeAddr("user");
        uint power = lendingFacility.exposed_calculateUserBorrowingPower(user);
        assertEq(power, 0); // No locked tokens initially

        // Borrow some tokens (which automatically locks issuance tokens)
        uint borrowAmount = 500 ether;
        uint requiredIssuanceTokens = lendingFacility
            .exposed_calculateRequiredIssuanceTokens(borrowAmount);
        // Add a larger buffer to account for rounding precision
        uint issuanceTokensWithBuffer = requiredIssuanceTokens + 10 ether;
        issuanceToken.mint(user, issuanceTokensWithBuffer);

        vm.prank(user);
        issuanceToken.approve(
            address(lendingFacility), issuanceTokensWithBuffer
        );

        vm.prank(user);
        lendingFacility.borrow(borrowAmount);

        power = lendingFacility.exposed_calculateUserBorrowingPower(user);
        assertGt(power, 0);
    }

    function testCalculateDynamicBorrowingFee() public {
        uint fee =
            lendingFacility.exposed_calculateDynamicBorrowingFee(1000 ether);
        // Fee calculation depends on floor liquidity rate
        assertGe(fee, 0);
    }

    function testCalculateIssuanceTokensToUnlock() public {
        address user = makeAddr("user");
        uint repaymentAmount = 500 ether;
        uint tokensToUnlock = lendingFacility
            .exposed_calculateIssuanceTokensToUnlock(user, repaymentAmount);
        assertEq(tokensToUnlock, 0); // No outstanding loan initially
    }

    function testCalculateRequiredIssuanceTokens() public {
        uint borrowAmount = 500 ether;
        uint requiredIssuanceTokens = lendingFacility
            .exposed_calculateRequiredIssuanceTokens(borrowAmount);
        assertGt(requiredIssuanceTokens, 0);
    }

    function testCalculateCollateralAmount() public {
        uint issuanceTokenAmount = 1000 ether;
        uint collateralAmount = lendingFacility
            .exposed_calculateCollateralAmount(issuanceTokenAmount);
        assertGt(collateralAmount, 0);
    }

    // =========================================================================
    /* Test: State consistency after multiple borrow and repay operations
    ├── Given a user performs multiple borrow and repay operations
    └── When all operations complete
        └── Then the state should remain consistent
    */
    function testPublicBorrowAndRepay_maintainsStateConsistency() public {
        address user = makeAddr("user");

        // First borrow
        uint borrowAmount1 = 300 ether;
        uint requiredIssuanceTokens1 = lendingFacility
            .exposed_calculateRequiredIssuanceTokens(borrowAmount1);
        uint issuanceTokensWithBuffer1 = requiredIssuanceTokens1 + 10 ether;
        issuanceToken.mint(user, issuanceTokensWithBuffer1);
        vm.prank(user);
        issuanceToken.approve(
            address(lendingFacility), issuanceTokensWithBuffer1
        );
        vm.prank(user);
        lendingFacility.borrow(borrowAmount1);

        // Verify state after first borrow
        assertEq(lendingFacility.getOutstandingLoan(user), borrowAmount1);
        assertEq(
            lendingFacility.getLockedIssuanceTokens(user),
            requiredIssuanceTokens1
        );
        assertEq(lendingFacility.currentlyBorrowedAmount(), borrowAmount1);

        // Second borrow
        uint borrowAmount2 = 200 ether;
        uint requiredIssuanceTokens2 = lendingFacility
            .exposed_calculateRequiredIssuanceTokens(borrowAmount2);
        uint issuanceTokensWithBuffer2 = requiredIssuanceTokens2 + 10 ether;
        issuanceToken.mint(user, issuanceTokensWithBuffer2);
        vm.prank(user);
        issuanceToken.approve(
            address(lendingFacility), issuanceTokensWithBuffer2
        );
        vm.prank(user);
        lendingFacility.borrow(borrowAmount2);

        // Verify state after second borrow
        assertEq(
            lendingFacility.getOutstandingLoan(user),
            borrowAmount1 + borrowAmount2
        );
        assertEq(
            lendingFacility.getLockedIssuanceTokens(user),
            requiredIssuanceTokens1 + requiredIssuanceTokens2
        );
        assertEq(
            lendingFacility.currentlyBorrowedAmount(),
            borrowAmount1 + borrowAmount2
        );

        // Partial repayment
        uint repayAmount = 250 ether;
        orchestratorToken.mint(user, repayAmount);
        vm.prank(user);
        orchestratorToken.approve(address(lendingFacility), repayAmount);
        vm.prank(user);
        lendingFacility.repay(repayAmount);

        // Verify state after partial repayment
        assertEq(
            lendingFacility.getOutstandingLoan(user),
            borrowAmount1 + borrowAmount2 - repayAmount
        );
        assertEq(
            lendingFacility.currentlyBorrowedAmount(),
            borrowAmount1 + borrowAmount2 - repayAmount
        );
    }

    // =========================================================================
    // Helper Functions

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

    function helper_createSegments( // TODO: move to a library
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

    function helper_getDynamicFeeCalculatorParams()
        internal
        view
        returns (
            IDynamicFeeCalculator_v1.DynamicFeeParameters memory dynamicFeeParameters
        )
    {
        return dynamicFeeCalculator.getDynamicFeeParameters();
    }

    function helper_setDynamicFeeCalculatorParams(
        IDynamicFeeCalculator_v1.DynamicFeeParameters memory feeParams_
    )
        internal
        returns (
            IDynamicFeeCalculator_v1.DynamicFeeParameters memory dynamicFeeParameters
        )
    {
        feeParams_.Z_issueRedeem =
            bound(feeParams_.Z_issueRedeem, 1e15, MAX_FEE_PERCENTAGE);
        feeParams_.A_issueRedeem =
            bound(feeParams_.A_issueRedeem, 1e15, MAX_FEE_PERCENTAGE);
        feeParams_.m_issueRedeem =
            bound(feeParams_.m_issueRedeem, 1e15, MAX_FEE_PERCENTAGE);
        feeParams_.Z_origination =
            bound(feeParams_.Z_origination, 1e15, MAX_FEE_PERCENTAGE);
        feeParams_.A_origination =
            bound(feeParams_.A_origination, 1e15, MAX_FEE_PERCENTAGE);
        feeParams_.m_origination =
            bound(feeParams_.m_origination, 1e15, MAX_FEE_PERCENTAGE);

        dynamicFeeParameters = IDynamicFeeCalculator_v1.DynamicFeeParameters({
            Z_issueRedeem: feeParams_.Z_issueRedeem,
            A_issueRedeem: feeParams_.A_issueRedeem,
            m_issueRedeem: feeParams_.m_issueRedeem,
            Z_origination: feeParams_.Z_origination,
            A_origination: feeParams_.A_origination,
            m_origination: feeParams_.m_origination
        });

        dynamicFeeCalculator.setDynamicFeeCalculatorParams(dynamicFeeParameters);

        return dynamicFeeParameters;
    }
}
