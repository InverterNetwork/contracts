// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Internal
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
import {DynamicFeeCalculatorLib_v1} from
    "src/modules/logicModule/libraries/DynamicFeeCalculator_v1.sol";

// External
import {Clones} from "@oz/proxy/Clones.sol";

// Tests and Mocks
import {LM_PC_HouseProtocol_v1_Exposed} from
    "@mocks/modules/logicModule/LM_PC_HouseProtocol_v1_Exposed.sol";
import {
    IERC20PaymentClientBase_v2,
    ERC20PaymentClientBaseV2Mock,
    ERC20Mock
} from "@mocks/modules/paymentClient/ERC20PaymentClientBaseV2Mock.sol";
import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol"; // Added import

// System under Test (SuT)
import {ILM_PC_HouseProtocol_v1} from
    "@lm/interfaces/ILM_PC_HouseProtocol_v1.sol";
import {IFM_BC_Discrete_Redeeming_VirtualSupply_v1} from
    "src/modules/fundingManager/bondingCurve/interfaces/IFM_BC_Discrete_Redeeming_VirtualSupply_v1.sol";
import {FM_BC_Discrete_Redeeming_VirtualSupply_v1_Exposed} from
    "test/mocks/modules/fundingManager/bondingCurve/FM_BC_Discrete_Redeeming_VirtualSupply_v1_Exposed.sol";

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
contract LM_PC_HouseProtocol_v1_Test is ModuleTest {
    using PackedSegmentLib for PackedSegment;
    using DiscreteCurveMathLib_v1 for PackedSegment[];
    using DynamicFeeCalculatorLib_v1 for uint;
    // =========================================================================
    // State

    // SuT
    LM_PC_HouseProtocol_v1_Exposed lendingFacility;

    // Test constants
    uint constant BORROWABLE_QUOTA = 8000; // 80% in basis points
    uint constant INDIVIDUAL_BORROW_LIMIT = 500 ether;
    uint constant LOCKED_ISSUANCE_TOKENS = 1000 ether;

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
            address(new LM_PC_HouseProtocol_v1_Exposed());
        lendingFacility =
            LM_PC_HouseProtocol_v1_Exposed(Clones.clone(impl_lendingFacility));

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

        // Initiate the Logic Module with the metadata and config data
        lendingFacility.init(
            _orchestrator,
            _METADATA,
            abi.encode(
                address(orchestratorToken),
                address(issuanceToken),
                address(fmBcDiscrete),
                BORROWABLE_QUOTA,
                INDIVIDUAL_BORROW_LIMIT
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
                type(ILM_PC_HouseProtocol_v1).interfaceId
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
    function testRepay() public {
        // Given: a user has an outstanding loan
        address user = makeAddr("user");
        uint borrowAmount = 500 ether;
        uint repayAmount = 200 ether;

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
        assertLt(
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
    function testRepay_exceedsOutstandingLoan() public {
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
            outstandingLoanAfter,
            0,
            "Outstanding loan should be fully repaid"
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
    function testBorrow() public {
        // Given: a user has issuance tokens
        address user = makeAddr("user");
        uint borrowAmount = 500 ether;

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

        // Given: the borrow amount is within individual and system limits
        assertLe(
            borrowAmount,
            lendingFacility.individualBorrowLimit(),
            "Borrow amount should be within individual limit"
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

    /* Test: Function borrow()
        ├── Given a user has insufficient issuance tokens
        └── When the user tries to borrow collateral tokens
            └── Then the transaction should revert with InsufficientBorrowingPower error
    */
    function testBorrow_insufficientIssuanceTokens() public {
        // Given: a user has insufficient issuance tokens
        address user = makeAddr("user");
        uint borrowAmount = 500 ether;
        uint insufficientTokens = 100 ether; // Less than required

        issuanceToken.mint(user, insufficientTokens);
        vm.prank(user);
        issuanceToken.approve(address(lendingFacility), insufficientTokens);

        // When: the user tries to borrow collateral tokens
        vm.prank(user);
        vm.expectRevert(
            ILM_PC_HouseProtocol_v1
                .Module__LM_PC_HouseProtocol_InsufficientBorrowingPower
                .selector
        );
        lendingFacility.borrow(borrowAmount);

        // Then: the transaction should revert with InsufficientBorrowingPower error
    }

    /* Test: Function borrow()
        ├── Given a user has issuance tokens
        ├── And the user has sufficient borrowing power
        └── And the borrow amount exceeds individual limit
            └── When the user tries to borrow collateral tokens
                └── Then the transaction should revert with IndividualBorrowLimitExceeded error
    */
    function testBorrow_exceedsIndividualLimit() public {
        // Given: a user has issuance tokens
        address user = makeAddr("user");
        uint borrowAmount = 600 ether; // More than individual limit (500 ether)

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

        // Given: the borrow amount exceeds individual limit
        assertGt(
            borrowAmount,
            lendingFacility.individualBorrowLimit(),
            "Borrow amount should exceed individual limit"
        );

        // When: the user tries to borrow collateral tokens
        vm.prank(user);
        vm.expectRevert(
            ILM_PC_HouseProtocol_v1
                .Module__LM_PC_HouseProtocol_IndividualBorrowLimitExceeded
                .selector
        );
        lendingFacility.borrow(borrowAmount);

        // Then: the transaction should revert with IndividualBorrowLimitExceeded error
    }

    /* Test: Function borrow() - Individual limit with existing outstanding loans
        ├── Given a user has an existing outstanding loan
        └── And the user tries to borrow additional tokens that would exceed the individual limit when combined
            └── When the user tries to borrow additional collateral tokens
                └── Then the transaction should revert with IndividualBorrowLimitExceeded error
    */
    function testBorrow_exceedsIndividualLimitWithExistingLoan() public {
        // Given: a user has an existing outstanding loan
        address user = makeAddr("user");
        uint firstBorrowAmount = 300 ether; // First borrow
        uint secondBorrowAmount = 250 ether; // Second borrow that would exceed limit when combined

        // Setup: user borrows first amount
        uint requiredIssuanceTokens = lendingFacility
            .exposed_calculateRequiredIssuanceTokens(firstBorrowAmount);
        uint issuanceTokensWithBuffer = requiredIssuanceTokens + 10 ether;
        issuanceToken.mint(user, issuanceTokensWithBuffer);
        vm.prank(user);
        issuanceToken.approve(
            address(lendingFacility), issuanceTokensWithBuffer
        );
        vm.prank(user);
        lendingFacility.borrow(firstBorrowAmount);

        // Verify user has outstanding loan
        assertEq(
            lendingFacility.getOutstandingLoan(user),
            firstBorrowAmount,
            "User should have outstanding loan"
        );

        // Given: the user tries to borrow additional tokens that would exceed the individual limit when combined
        uint totalBorrowed = firstBorrowAmount + secondBorrowAmount;
        assertGt(
            totalBorrowed,
            lendingFacility.individualBorrowLimit(),
            "Total borrowed amount should exceed individual limit"
        );

        // Setup for second borrow attempt
        uint requiredIssuanceTokens2 = lendingFacility
            .exposed_calculateRequiredIssuanceTokens(secondBorrowAmount);
        uint issuanceTokensWithBuffer2 = requiredIssuanceTokens2 + 10 ether;
        issuanceToken.mint(user, issuanceTokensWithBuffer2);
        vm.prank(user);
        issuanceToken.approve(
            address(lendingFacility), issuanceTokensWithBuffer2
        );

        // When: the user tries to borrow additional collateral tokens
        vm.prank(user);
        vm.expectRevert(
            ILM_PC_HouseProtocol_v1
                .Module__LM_PC_HouseProtocol_IndividualBorrowLimitExceeded
                .selector
        );
        lendingFacility.borrow(secondBorrowAmount);

        // Then: the transaction should revert with IndividualBorrowLimitExceeded error
    }

    /* Test: Function borrow() - Individual limit allows borrowing within limit with existing loans
        ├── Given a user has an existing outstanding loan
        └── And the user tries to borrow additional tokens that would stay within the individual limit when combined
            └── When the user tries to borrow additional collateral tokens
                └── Then the transaction should succeed
    */
    function testBorrow_withinIndividualLimitWithExistingLoan() public {
        // Given: a user has an existing outstanding loan
        address user = makeAddr("user");
        uint firstBorrowAmount = 300 ether; // First borrow
        uint secondBorrowAmount = 150 ether; // Second borrow that stays within limit when combined

        // Setup: user borrows first amount
        uint requiredIssuanceTokens = lendingFacility
            .exposed_calculateRequiredIssuanceTokens(firstBorrowAmount);
        uint issuanceTokensWithBuffer = requiredIssuanceTokens + 10 ether;
        issuanceToken.mint(user, issuanceTokensWithBuffer);
        vm.prank(user);
        issuanceToken.approve(
            address(lendingFacility), issuanceTokensWithBuffer
        );
        vm.prank(user);
        lendingFacility.borrow(firstBorrowAmount);

        // Verify user has outstanding loan
        assertEq(
            lendingFacility.getOutstandingLoan(user),
            firstBorrowAmount,
            "User should have outstanding loan"
        );

        // Given: the user tries to borrow additional tokens that would stay within the individual limit when combined
        uint totalBorrowed = firstBorrowAmount + secondBorrowAmount;
        assertLe(
            totalBorrowed,
            lendingFacility.individualBorrowLimit(),
            "Total borrowed amount should be within individual limit"
        );

        // Setup for second borrow attempt
        uint requiredIssuanceTokens2 = lendingFacility
            .exposed_calculateRequiredIssuanceTokens(secondBorrowAmount);
        uint issuanceTokensWithBuffer2 = requiredIssuanceTokens2 + 10 ether;
        issuanceToken.mint(user, issuanceTokensWithBuffer2);
        vm.prank(user);
        issuanceToken.approve(
            address(lendingFacility), issuanceTokensWithBuffer2
        );

        // When: the user tries to borrow additional collateral tokens
        uint outstandingLoanBefore = lendingFacility.getOutstandingLoan(user);
        vm.prank(user);
        lendingFacility.borrow(secondBorrowAmount);

        // Then: the transaction should succeed and outstanding loan should increase
        assertEq(
            lendingFacility.getOutstandingLoan(user),
            outstandingLoanBefore + secondBorrowAmount,
            "Outstanding loan should increase by second borrow amount"
        );
    }

    /* Test: Function borrow() - Outstanding loan should match net amount received
        ├── Given a user borrows tokens with a dynamic fee
        └── When the borrow transaction completes
            └── Then the outstanding loan should equal the net amount received by the user
    */
    function testBorrow_outstandingLoanMatchesNetAmount() public {
        // Given: a user has issuance tokens
        address user = makeAddr("user");
        uint borrowAmount = 500 ether;

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

        // Given: the borrow amount is within limits
        assertLe(
            borrowAmount,
            lendingFacility.individualBorrowLimit(),
            "Borrow amount should be within individual limit"
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
        helper_setDynamicFeeCalculatorParams();

        // When: the user borrows collateral tokens
        uint userBalanceBefore = orchestratorToken.balanceOf(user);
        vm.prank(user);
        lendingFacility.borrow(borrowAmount);

        // Then: the outstanding loan should equal the net amount received by the user
        uint userBalanceAfter = orchestratorToken.balanceOf(user);
        uint netAmountReceived = userBalanceAfter - userBalanceBefore;
        uint outstandingLoan = lendingFacility.getOutstandingLoan(user);

        assertEq(
            outstandingLoan,
            netAmountReceived,
            "Outstanding loan should equal net amount received by user"
        );

        // And: the outstanding loan should be less than the requested amount (due to fees)
        assertLt(
            outstandingLoan,
            borrowAmount,
            "Outstanding loan should be less than requested amount due to fees"
        );
    }

    /* Test: Dynamic Fee Parameters - Set and Read
        ├── Given dynamic fee parameters are set
        └── When reading the dynamic fee parameters
            └── Then the returned parameters should match the set parameters
    */
    function testDynamicFeeParameters_SetAndRead() public {
        // Given: dynamic fee parameters are set
        ILM_PC_HouseProtocol_v1.DynamicFeeParameters memory expectedParams = 
            ILM_PC_HouseProtocol_v1.DynamicFeeParameters({
                Z_issueRedeem: 2e16, // 2%
                A_issueRedeem: 8e16, // 8%
                m_issueRedeem: 3e15, // 0.3%
                Z_origination: 1.5e16, // 1.5%
                A_origination: 2.5e16, // 2.5%
                m_origination: 2.5e15 // 0.25%
            });

        // Set the parameters
        lendingFacility.setDynamicFeeCalculatorParams(expectedParams);

        // When: reading the dynamic fee parameters
        ILM_PC_HouseProtocol_v1.DynamicFeeParameters memory actualParams = 
            lendingFacility.getDynamicFeeParameters();

        // Then: the returned parameters should match the set parameters
        assertEq(
            actualParams.Z_issueRedeem,
            expectedParams.Z_issueRedeem,
            "Z_issueRedeem should match"
        );
        assertEq(
            actualParams.A_issueRedeem,
            expectedParams.A_issueRedeem,
            "A_issueRedeem should match"
        );
        assertEq(
            actualParams.m_issueRedeem,
            expectedParams.m_issueRedeem,
            "m_issueRedeem should match"
        );
        assertEq(
            actualParams.Z_origination,
            expectedParams.Z_origination,
            "Z_origination should match"
        );
        assertEq(
            actualParams.A_origination,
            expectedParams.A_origination,
            "A_origination should match"
        );
        assertEq(
            actualParams.m_origination,
            expectedParams.m_origination,
            "m_origination should match"
        );
    }

    /* Test: Dynamic Fee Parameters - Default Values
        ├── Given the lending facility is initialized
        └── When reading the dynamic fee parameters before setting them
            └── Then the parameters should have default values (all zeros)
    */
    function testDynamicFeeParameters_DefaultValues() public {
        // Given: the lending facility is initialized (already done in setUp)

        // When: reading the dynamic fee parameters before setting them
        ILM_PC_HouseProtocol_v1.DynamicFeeParameters memory params = 
            lendingFacility.getDynamicFeeParameters();

        // Then: the parameters should have default values (all zeros)
        assertEq(params.Z_issueRedeem, 0, "Z_issueRedeem should be 0 by default");
        assertEq(params.A_issueRedeem, 0, "A_issueRedeem should be 0 by default");
        assertEq(params.m_issueRedeem, 0, "m_issueRedeem should be 0 by default");
        assertEq(params.Z_origination, 0, "Z_origination should be 0 by default");
        assertEq(params.A_origination, 0, "A_origination should be 0 by default");
        assertEq(params.m_origination, 0, "m_origination should be 0 by default");
    }

    /* Test: Dynamic Fee Parameters - Update Values
        ├── Given dynamic fee parameters are initially set
        └── And the parameters are updated with new values
            └── When reading the dynamic fee parameters
                └── Then the returned parameters should match the updated values
    */
    function testDynamicFeeParameters_UpdateValues() public {
        // Given: dynamic fee parameters are initially set
        ILM_PC_HouseProtocol_v1.DynamicFeeParameters memory initialParams = 
            ILM_PC_HouseProtocol_v1.DynamicFeeParameters({
                Z_issueRedeem: 1e16, // 1%
                A_issueRedeem: 7.5e16, // 7.5%
                m_issueRedeem: 2e15, // 0.2%
                Z_origination: 1e16, // 1%
                A_origination: 2e16, // 2%
                m_origination: 2e15 // 0.2%
            });

        lendingFacility.setDynamicFeeCalculatorParams(initialParams);

        // And: the parameters are updated with new values
        ILM_PC_HouseProtocol_v1.DynamicFeeParameters memory updatedParams = 
            ILM_PC_HouseProtocol_v1.DynamicFeeParameters({
                Z_issueRedeem: 3e16, // 3%
                A_issueRedeem: 9e16, // 9%
                m_issueRedeem: 4e15, // 0.4%
                Z_origination: 2.5e16, // 2.5%
                A_origination: 3e16, // 3%
                m_origination: 3e15 // 0.3%
            });

        lendingFacility.setDynamicFeeCalculatorParams(updatedParams);

        // When: reading the dynamic fee parameters
        ILM_PC_HouseProtocol_v1.DynamicFeeParameters memory actualParams = 
            lendingFacility.getDynamicFeeParameters();

        // Then: the returned parameters should match the updated values
        assertEq(
            actualParams.Z_issueRedeem,
            updatedParams.Z_issueRedeem,
            "Z_issueRedeem should match updated value"
        );
        assertEq(
            actualParams.A_issueRedeem,
            updatedParams.A_issueRedeem,
            "A_issueRedeem should match updated value"
        );
        assertEq(
            actualParams.m_issueRedeem,
            updatedParams.m_issueRedeem,
            "m_issueRedeem should match updated value"
        );
        assertEq(
            actualParams.Z_origination,
            updatedParams.Z_origination,
            "Z_origination should match updated value"
        );
        assertEq(
            actualParams.A_origination,
            updatedParams.A_origination,
            "A_origination should match updated value"
        );
        assertEq(
            actualParams.m_origination,
            updatedParams.m_origination,
            "m_origination should match updated value"
        );

        // And: the parameters should NOT match the initial values
        assertTrue(
            actualParams.Z_issueRedeem != initialParams.Z_issueRedeem,
            "Z_issueRedeem should not match initial value"
        );
        assertTrue(
            actualParams.A_issueRedeem != initialParams.A_issueRedeem,
            "A_issueRedeem should not match initial value"
        );
    }

    /* Test: Function borrow()
        ├── Given a user wants to borrow tokens
        └── And the borrow amount is zero
            └── When the user tries to borrow collateral tokens
                └── Then the transaction should revert with InvalidBorrowAmount error
    */
    function testBorrow_zeroAmount() public {
        // Given: a user wants to borrow tokens
        address user = makeAddr("user");

        // Given: the borrow amount is zero
        uint borrowAmount = 0;

        // When: the user tries to borrow collateral tokens
        vm.prank(user);
        vm.expectRevert(
            ILM_PC_HouseProtocol_v1
                .Module__LM_PC_HouseProtocol_InvalidBorrowAmount
                .selector
        );
        lendingFacility.borrow(borrowAmount);

        // Then: the transaction should revert with InvalidBorrowAmount error
    }

    // =========================================================================
    // Test: Configuration Functions

    /* Test external setIndividualBorrowLimit function
        ├── Given caller has LENDING_FACILITY_MANAGER_ROLE
        │   └── When setting new individual borrow limit
        │       ├── Then the limit should be updated
        │       └── Then an event should be emitted
        └── Given caller doesn't have role
            └── When trying to set limit
                └── Then it should revert with CallerNotAuthorized
    */
    function testSetIndividualBorrowLimit() public {
        // Grant role to this test contract
        bytes32 roleId = _authorizer.generateRoleId(
            address(lendingFacility),
            lendingFacility.LENDING_FACILITY_MANAGER_ROLE()
        );
        _authorizer.grantRole(roleId, address(this));

        uint newLimit = 2000 ether;
        lendingFacility.setIndividualBorrowLimit(newLimit);

        assertEq(lendingFacility.individualBorrowLimit(), newLimit);
    }

    function testSetIndividualBorrowLimit_unauthorized() public {
        address unauthorizedUser = makeAddr("unauthorized");

        vm.startPrank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                lendingFacility.LENDING_FACILITY_MANAGER_ROLE(),
                unauthorizedUser
            )
        );
        lendingFacility.setIndividualBorrowLimit(2000 ether);
        vm.stopPrank();
    }

    /* Test external setBorrowableQuota function
        ├── Given caller has LENDING_FACILITY_MANAGER_ROLE
        │   └── When setting new borrowable quota
        │       ├── Then the quota should be updated
        │       └── Then an event should be emitted
        └── Given quota exceeds 100%
            └── When trying to set quota
                └── Then it should revert with appropriate error
    */
    function testSetBorrowableQuota() public {
        // Grant role to this test contract
        bytes32 roleId = _authorizer.generateRoleId(
            address(lendingFacility),
            lendingFacility.LENDING_FACILITY_MANAGER_ROLE()
        );
        _authorizer.grantRole(roleId, address(this));

        uint newQuota = 9000; // 90% in basis points
        lendingFacility.setBorrowableQuota(newQuota);

        assertEq(lendingFacility.borrowableQuota(), newQuota);
    }

    function testSetBorrowableQuota_exceedsMax() public {
        // Grant role to this test contract
        bytes32 roleId = _authorizer.generateRoleId(
            address(lendingFacility),
            lendingFacility.LENDING_FACILITY_MANAGER_ROLE()
        );
        _authorizer.grantRole(roleId, address(this));

        uint invalidQuota = 10_001; // Exceeds 100%
        vm.expectRevert(
            ILM_PC_HouseProtocol_v1
                .Module__LM_PC_HouseProtocol_BorrowableQuotaTooHigh
                .selector
        );
        lendingFacility.setBorrowableQuota(invalidQuota);
    }

    /* Test external setDynamicFeeCalculator function
        ├── Given caller has LENDING_FACILITY_MANAGER_ROLE
        │   └── When setting new fee calculator address
        │       ├── Then the address should be updated
        │       └── Then an event should be emitted
        └── Given invalid address (zero address)
            └── When trying to set address
                └── Then it should revert with appropriate error
    */
    function testSetDynamicFeeCalculator() public {
        // Grant role to this test contract
        bytes32 roleId = _authorizer.generateRoleId(
            address(lendingFacility),
            lendingFacility.LENDING_FACILITY_MANAGER_ROLE()
        );
        _authorizer.grantRole(roleId, address(this));

        address newCalculator = makeAddr("newCalculator");
        lendingFacility.setDynamicFeeCalculator(newCalculator);

        assertEq(lendingFacility.dynamicFeeCalculator(), newCalculator);
    }

    function testSetDynamicFeeCalculator_zeroAddress() public {
        // Grant role to this test contract
        bytes32 roleId = _authorizer.generateRoleId(
            address(lendingFacility),
            lendingFacility.LENDING_FACILITY_MANAGER_ROLE()
        );
        _authorizer.grantRole(roleId, address(this));

        vm.expectRevert(
            ILM_PC_HouseProtocol_v1
                .Module__LM_PC_HouseProtocol_InvalidFeeCalculatorAddress
                .selector
        );
        lendingFacility.setDynamicFeeCalculator(address(0));
    }

    // =========================================================================
    // Test: Dynamic Fee Calculator

    /* Test external setDynamicFeeCalculatorParams function
        ├── Given caller has FEE_CALCULATOR_ADMIN_ROLE
        │   └── When setting new fee calculator parameters
        │       ├── Then the parameters should be updated
        │       └── Then an event should be emitted
        └── Given invalid parameters (zero values)
            └── When trying to set parameters
                └── Then it should revert with InvalidDynamicFeeParameters error
        └── Given caller doesn't have role
            └── When trying to set parameters
    */

    function testFuzz_setDynamicFeeCalculatorParams_unauthorized(
        address unauthorizedUser
    ) public {
        vm.assume(
            unauthorizedUser != address(0) && unauthorizedUser != address(this)
        );

        vm.startPrank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                lendingFacility.FEE_CALCULATOR_ADMIN_ROLE(),
                unauthorizedUser
            )
        );
        ILM_PC_HouseProtocol_v1.DynamicFeeParameters memory feeParams =
            helper_getDynamicFeeCalculatorParams();
        lendingFacility.setDynamicFeeCalculatorParams(feeParams);
        vm.stopPrank();
    }

    function testFuzz_setDynamicFeeCalculatorParams_invalidParams(
        ILM_PC_HouseProtocol_v1.DynamicFeeParameters memory feeParams
    ) public {
        vm.assume(
            feeParams.Z_issueRedeem == 0 || feeParams.A_issueRedeem == 0
                || feeParams.m_issueRedeem == 0 || feeParams.Z_origination == 0
                || feeParams.A_origination == 0 || feeParams.m_origination == 0
        );
        vm.expectRevert(
            ILM_PC_HouseProtocol_v1
                .Module__LM_PC_HouseProtocol_InvalidDynamicFeeParameters
                .selector
        );
        lendingFacility.setDynamicFeeCalculatorParams(feeParams);
    }

    function testFuzz_setDynamicFeeCalculatorParams(
        ILM_PC_HouseProtocol_v1.DynamicFeeParameters memory feeParams
    ) public {
        vm.assume(
            feeParams.Z_issueRedeem != 0 && feeParams.A_issueRedeem != 0
                && feeParams.m_issueRedeem != 0 && feeParams.Z_origination != 0
                && feeParams.A_origination != 0 && feeParams.m_origination != 0
        );
        vm.assume(
            feeParams.Z_issueRedeem < type(uint64).max
                && feeParams.A_issueRedeem < type(uint64).max
                && feeParams.m_issueRedeem < type(uint64).max
                && feeParams.Z_origination < type(uint64).max
                && feeParams.A_origination < type(uint64).max
                && feeParams.m_origination < type(uint64).max
        );

        lendingFacility.setDynamicFeeCalculatorParams(feeParams);

        ILM_PC_HouseProtocol_v1.DynamicFeeParameters memory LF_feeParams =
            lendingFacility.getDynamicFeeParameters();

        assertEq(LF_feeParams.Z_issueRedeem, feeParams.Z_issueRedeem);
        assertEq(LF_feeParams.A_issueRedeem, feeParams.A_issueRedeem);
        assertEq(LF_feeParams.m_issueRedeem, feeParams.m_issueRedeem);
        assertEq(LF_feeParams.Z_origination, feeParams.Z_origination);
        assertEq(LF_feeParams.A_origination, feeParams.A_origination);
        assertEq(LF_feeParams.m_origination, feeParams.m_origination);
    }

    // Test: Dynamic Fee Calculator Library

    /* Test calculateOriginationFee function
        ├── Given floorLiquidityRate is below A_origination
        │   └── Then the fee should be Z_origination
        └── Given floorLiquidityRate is above A_origination
            └── Then the fee should be Z_origination + (floorLiquidityRate - A_origination) * m_origination / Sc
    */
    function test_calculateOriginationFee_BelowThreshold() public {
        ILM_PC_HouseProtocol_v1.DynamicFeeParameters memory feeParams =
            helper_setDynamicFeeCalculatorParams();

        uint floorLiquidityRate = 1e16; // 1%
        uint fee = DynamicFeeCalculatorLib_v1.calculateOriginationFee(
            floorLiquidityRate,
            feeParams.Z_origination,
            feeParams.A_origination,
            feeParams.m_origination
        );
        assertEq(fee, feeParams.Z_origination);
    }

    function test_calculateOriginationFee_AboveThreshold() public {
        ILM_PC_HouseProtocol_v1.DynamicFeeParameters memory feeParams =
            helper_setDynamicFeeCalculatorParams();

        uint floorLiquidityRate = 9e16; // 9%
        uint fee = DynamicFeeCalculatorLib_v1.calculateOriginationFee(
            floorLiquidityRate,
            feeParams.Z_origination,
            feeParams.A_origination,
            feeParams.m_origination
        );
        assertEq(
            fee,
            feeParams.Z_origination
                + (
                    (floorLiquidityRate - feeParams.A_origination)
                        * feeParams.m_origination
                ) / 1e18
        );
    }

    /* Test calculateIssuanceFee function
        ├── Given premiumRate is below A_issueRedeem
        │   └── Then the fee should be Z_issueRedeem
        └── Given premiumRate is above A_issueRedeem
            └── Then the fee should be Z_issueRedeem + (premiumRate - A_issueRedeem) * m_issueRedeem / SCALING_FACTOR
    */
    function test_calculateIssuanceFee_BelowThreshold() public {
        ILM_PC_HouseProtocol_v1.DynamicFeeParameters memory feeParams =
            helper_setDynamicFeeCalculatorParams();

        uint premiumRate = 1e16; // 1%
        uint fee = DynamicFeeCalculatorLib_v1.calculateIssuanceFee(
            premiumRate,
            feeParams.Z_issueRedeem,
            feeParams.A_issueRedeem,
            feeParams.m_issueRedeem
        );
        assertEq(fee, feeParams.Z_issueRedeem);
    }

    function test_calculateIssuanceFee_AboveThreshold() public {
        ILM_PC_HouseProtocol_v1.DynamicFeeParameters memory feeParams =
            helper_setDynamicFeeCalculatorParams();

        uint premiumRate = 9e16; // 9%
        uint fee = DynamicFeeCalculatorLib_v1.calculateIssuanceFee(
            premiumRate,
            feeParams.Z_issueRedeem,
            feeParams.A_issueRedeem,
            feeParams.m_issueRedeem
        );
        assertEq(
            fee,
            feeParams.Z_issueRedeem
                + (premiumRate - feeParams.A_issueRedeem) * feeParams.m_issueRedeem
                    / 1e18
        );
    }

    /* Test calculateRedemptionFee function
        ├── Given premiumRate is below A_issueRedeem
        │   └── Then the fee should be Z_issueRedeem
        └── Given premiumRate is above A_issueRedeem
            └── Then the fee should be feeParams.Z_issueRedeem
                + (feeParams.A_issueRedeem - premiumRate) * feeParams.m_issueRedeem
                    / SCALING_FACTOR
    */
    function test_calculateRedemptionFee_BelowThreshold() public {
        ILM_PC_HouseProtocol_v1.DynamicFeeParameters memory feeParams =
            helper_setDynamicFeeCalculatorParams();

        uint premiumRate = 1e16; // 1%
        uint fee = DynamicFeeCalculatorLib_v1.calculateRedemptionFee(
            premiumRate,
            feeParams.Z_issueRedeem,
            feeParams.A_issueRedeem,
            feeParams.m_issueRedeem
        );
        assertEq(
            fee,
            feeParams.Z_issueRedeem
                + (feeParams.A_issueRedeem - premiumRate) * feeParams.m_issueRedeem
                    / 1e18
        );
    }

    function test_calculateRedemptionFee_AboveThreshold() public {
        ILM_PC_HouseProtocol_v1.DynamicFeeParameters memory feeParams =
            helper_setDynamicFeeCalculatorParams();

        uint premiumRate = 9e16; // 9%
        uint fee = DynamicFeeCalculatorLib_v1.calculateRedemptionFee(
            premiumRate,
            feeParams.Z_issueRedeem,
            feeParams.A_issueRedeem,
            feeParams.m_issueRedeem
        );
        assertEq(fee, feeParams.Z_issueRedeem);
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
            ILM_PC_HouseProtocol_v1
                .Module__LM_PC_HouseProtocol_InvalidBorrowAmount
                .selector
        );
        lendingFacility.exposed_ensureValidBorrowAmount(0);
    }

    function testCalculateBorrowCapacity() public {
        uint capacity = lendingFacility.exposed_calculateBorrowCapacity();
        assertGt(capacity, 0);
    }

    function testCalculateUserBorrowingPower() public {
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

    // =========================================================================
    // Test: Unlocking Issuance Tokens

    /* Test: Function unlockIssuanceTokens()
        ├── Given a user has locked issuance tokens
        ├── And the user has no outstanding loan
        └── When the user unlocks issuance tokens
            ├── Then their locked issuance tokens should decrease
            ├── And issuance tokens should be transferred back to user
            └── And an event should be emitted
    */
    function testUnlockIssuanceTokens() public {
        // Given: a user has locked issuance tokens
        address user = makeAddr("user");
        uint borrowAmount = 500 ether;
        uint unlockAmount = 200 ether;

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

        // Given: the user has no outstanding loan (repay the full amount)
        orchestratorToken.mint(user, borrowAmount);
        vm.prank(user);
        orchestratorToken.approve(address(lendingFacility), borrowAmount);
        vm.prank(user);
        lendingFacility.repay(borrowAmount);

        // Verify user has no outstanding loan
        assertEq(
            lendingFacility.getOutstandingLoan(user),
            0,
            "User should have no outstanding loan"
        );

        // When: the user unlocks issuance tokens
        uint lockedTokensBefore = lendingFacility.getLockedIssuanceTokens(user);
        uint userBalanceBefore = issuanceToken.balanceOf(user);

        vm.prank(user);
        lendingFacility.unlockIssuanceTokens(unlockAmount);

        // Then: their locked issuance tokens should decrease
        assertEq(
            lendingFacility.getLockedIssuanceTokens(user),
            lockedTokensBefore - unlockAmount,
            "Locked issuance tokens should decrease"
        );

        // And: issuance tokens should be transferred back to user
        assertEq(
            issuanceToken.balanceOf(user),
            userBalanceBefore + unlockAmount,
            "User should receive unlocked issuance tokens"
        );
    }

    /* Test: Function unlockIssuanceTokens()
        ├── Given a user has locked issuance tokens
        ├── And the user has an outstanding loan
        └── When the user tries to unlock issuance tokens
            └── Then the transaction should revert with CannotUnlockWithOutstandingLoan error
    */
    function testUnlockIssuanceTokens_withOutstandingLoan() public {
        // Given: a user has locked issuance tokens
        address user = makeAddr("user");
        uint borrowAmount = 500 ether;
        uint unlockAmount = 200 ether;

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

        // Given: the user has an outstanding loan (don't repay)
        assertGt(
            lendingFacility.getOutstandingLoan(user),
            0,
            "User should have outstanding loan"
        );

        // When: the user tries to unlock issuance tokens
        vm.prank(user);
        vm.expectRevert(
            ILM_PC_HouseProtocol_v1
                .Module__LM_PC_HouseProtocol_CannotUnlockWithOutstandingLoan
                .selector
        );
        lendingFacility.unlockIssuanceTokens(unlockAmount);

        // Then: the transaction should revert with CannotUnlockWithOutstandingLoan error
    }

    /* Test: Function unlockIssuanceTokens()
        ├── Given a user has locked issuance tokens
        └── And the user tries to unlock more than locked amount
            └── When the user tries to unlock issuance tokens
                └── Then the transaction should revert with InsufficientLockedTokens error
    */
    function testUnlockIssuanceTokens_insufficientLockedTokens() public {
        // Given: a user has locked issuance tokens
        address user = makeAddr("user");
        uint borrowAmount = 500 ether;
        uint unlockAmount = 1000 ether; // More than locked amount

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

        // Given: the user has no outstanding loan (repay the full amount)
        orchestratorToken.mint(user, borrowAmount);
        vm.prank(user);
        orchestratorToken.approve(address(lendingFacility), borrowAmount);
        vm.prank(user);
        lendingFacility.repay(borrowAmount);

        // Given: the user tries to unlock more than locked amount
        uint lockedTokens = lendingFacility.getLockedIssuanceTokens(user);
        assertLt(
            lockedTokens,
            unlockAmount,
            "Unlock amount should exceed locked tokens"
        );

        // When: the user tries to unlock issuance tokens
        vm.prank(user);
        vm.expectRevert(
            ILM_PC_HouseProtocol_v1
                .Module__LM_PC_HouseProtocol_InsufficientLockedTokens
                .selector
        );
        lendingFacility.unlockIssuanceTokens(unlockAmount);

        // Then: the transaction should revert with InsufficientLockedTokens error
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
        pure
        returns (
            ILM_PC_HouseProtocol_v1.DynamicFeeParameters memory dynamicFeeParameters
        )
    {
        dynamicFeeParameters = ILM_PC_HouseProtocol_v1.DynamicFeeParameters({
            Z_issueRedeem: 1e16, // 1%
            A_issueRedeem: 7.5e16, // 7.5%
            m_issueRedeem: 2e15, // 0.2%
            Z_origination: 1e16, // 1%
            A_origination: 2e16, // 2%
            m_origination: 2e15 // 0.2%
        });
        return dynamicFeeParameters;
    }

    function helper_setDynamicFeeCalculatorParams()
        internal
        returns (
            ILM_PC_HouseProtocol_v1.DynamicFeeParameters memory dynamicFeeParameters
        )
    {
        dynamicFeeParameters = helper_getDynamicFeeCalculatorParams();

        lendingFacility.setDynamicFeeCalculatorParams(dynamicFeeParameters);

        return dynamicFeeParameters;
    }
}
