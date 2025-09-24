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
    uint constant BORROWABLE_QUOTA = 9900; // 99% in basis points
    uint constant MAX_FEE_PERCENTAGE = 1e18;
    uint constant MAX_LEVERAGE = 9;

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
                BORROWABLE_QUOTA,
                MAX_LEVERAGE
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
        └── And the load id is not valid
            └── When the user attempts to repay
                └── Then the transaction should revert with InvalidLoanId error
    */
    function testFuzzPublicRepay_revertsGivenInvalidLoanId(
        uint loanId_,
        uint amount_
    ) public {
        testFuzzPublicBorrow_succeedsGivenValidBorrowRequest(amount_);
        loanId_ =
            bound(loanId_, lendingFacility.nextLoanId() + 1, type(uint16).max);

        vm.expectRevert(
            ILM_PC_Lending_Facility_v1
                .Module__LM_PC_Lending_Facility_InvalidLoanId
                .selector
        );
        lendingFacility.repay(loanId_, amount_);
    }

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

        issuanceToken.mint(user, requiredIssuanceTokens);
        vm.startPrank(user);
        issuanceToken.approve(address(lendingFacility), requiredIssuanceTokens);
        lendingFacility.borrow(borrowAmount);
        vm.stopPrank();

        // Given: the user has sufficient collateral tokens to repay
        orchestratorToken.mint(user, repayAmount);
        vm.startPrank(user);
        orchestratorToken.approve(address(lendingFacility), repayAmount);

        // When: the user repays part of their loan
        uint outstandingLoanBefore = lendingFacility.getOutstandingLoan(user);
        uint currentlyBorrowedBefore = lendingFacility.currentlyBorrowedAmount();
        uint lockedTokensBefore = lendingFacility.getLockedIssuanceTokens(user);
        uint dbcFmCollateralBefore =
            orchestratorToken.balanceOf(address(fmBcDiscrete));

        for (uint i = 0; i < lendingFacility.getUserLoanIds(user).length; i++) {
            lendingFacility.repay(
                lendingFacility.getUserLoanIds(user)[i], repayAmount
            );
        }
        vm.stopPrank();

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
        ├── Given a user has two loans at different floor prices
        └── When the user repays the loans
            └── Then the outstanding loan should be zero
                └── And the locked issuance tokens should be zero
    */
    function testFuzzPublicRepay_succeedsGivenTwoLoansAtDifferentFloorPrices(
        uint borrowAmount
    ) public {
        // Given: a user has issuance tokens
        address user = makeAddr("user");

        testFuzzPublicBorrow_succeedsGivenUserBorrowsSameAmountAtDifferentFloorPrices(
            borrowAmount
        );

        uint[] memory userLoanIds = lendingFacility.getUserLoanIds(user);
        assertEq(userLoanIds.length, 2, "User should have exactly 2 loans");

        uint repaymentAmount1 =
            lendingFacility.calculateLoanRepaymentAmount(userLoanIds[0]);
        uint repaymentAmount2 =
            lendingFacility.calculateLoanRepaymentAmount(userLoanIds[1]);

        orchestratorToken.mint(user, repaymentAmount1 + repaymentAmount2);

        vm.startPrank(user);
        orchestratorToken.approve(
            address(lendingFacility), repaymentAmount1 + repaymentAmount2
        );
        lendingFacility.repay(userLoanIds[0], repaymentAmount1);
        lendingFacility.repay(userLoanIds[1], repaymentAmount2);
        vm.stopPrank();

        assertEq(lendingFacility.getOutstandingLoan(user), 0);
        assertEq(lendingFacility.getLockedIssuanceTokens(user), 0);
    }

    /* Test: Function repay()
        ├── Given a user has two loans at different floor prices
        └── When the user repays the loans with same repayment amount
            └── Then the issuance tokens should be unlocked proportionally
                └── And the tokens unlocked for loan1 should be greater than the tokens unlocked for loan2
    */
    function testFuzzPublicRepay_succeedsGivenTwoLoansAtDifferentFloorPricesPartialRepayment(
        uint borrowAmount_,
        uint repaymentAmount_
    ) public {
        // Given: a user has issuance tokens
        address user = makeAddr("user");

        testFuzzPublicBorrow_succeedsGivenUserBorrowsSameAmountAtDifferentFloorPrices(
            borrowAmount_
        );

        ILM_PC_Lending_Facility_v1.Loan[] memory userLoans =
            lendingFacility.getUserLoans(user);
        assertEq(userLoans.length, 2, "User should have exactly 2 loans");

        uint repaymentAmount1 =
            lendingFacility.calculateLoanRepaymentAmount(userLoans[0].id);
        uint repaymentAmount2 =
            lendingFacility.calculateLoanRepaymentAmount(userLoans[1].id);

        vm.assume(
            repaymentAmount_ > 0 && repaymentAmount_ < repaymentAmount1
                && repaymentAmount_ < repaymentAmount2
        );
        orchestratorToken.mint(user, repaymentAmount1 + repaymentAmount2);

        vm.startPrank(user);
        orchestratorToken.approve(
            address(lendingFacility), repaymentAmount1 + repaymentAmount2
        );
        lendingFacility.repay(userLoans[0].id, repaymentAmount1);
        uint issuanceTokensUnlockedFirstRepay = issuanceToken.balanceOf(user);
        lendingFacility.repay(userLoans[1].id, repaymentAmount2);
        uint issuanceTokensUnlockedSecondRepay = issuanceToken.balanceOf(user);
        vm.stopPrank();

        assertGt(
            issuanceTokensUnlockedFirstRepay,
            issuanceTokensUnlockedSecondRepay - issuanceTokensUnlockedFirstRepay,
            "More issuance tokens should be unlocked from loan 1 than loan 2 due to increased floor price for same repayment amount"
        );
    }

    /* Test: Function repay()
        ├── Given a user has an outstanding loan
        └── And the user tries to repay more than the outstanding amount
            └── When the user attempts to repay
                └── Then the repayment amount should be automatically adjusted to the outstanding loan amount
                └── And the outstanding loan should be fully repaid
    */

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
        issuanceToken.mint(user, requiredIssuanceTokens);

        vm.prank(user);
        issuanceToken.approve(address(lendingFacility), requiredIssuanceTokens);

        // When: the user borrows collateral tokens
        uint outstandingLoanBefore = lendingFacility.getOutstandingLoan(user);
        uint currentlyBorrowedBefore = lendingFacility.currentlyBorrowedAmount();
        uint lockedTokensBefore = lendingFacility.getLockedIssuanceTokens(user);

        vm.prank(user);
        uint loanId = lendingFacility.borrow(borrowAmount);

        // Then: verify the core state

        assertGt(loanId, 0, "Loan ID should be greater than 0");

        assertEq(
            lendingFacility.getOutstandingLoan(user),
            outstandingLoanBefore + borrowAmount,
            "Outstanding loan should increase by borrow amount"
        );

        assertEq(
            lendingFacility.getLockedIssuanceTokens(user),
            lockedTokensBefore + requiredIssuanceTokens,
            "Issuance tokens should be locked automatically"
        );

        assertEq(
            lendingFacility.currentlyBorrowedAmount(),
            currentlyBorrowedBefore + borrowAmount,
            "System borrowed amount should increase by borrow amount"
        );

        // And: verify the loan was created correctly
        ILM_PC_Lending_Facility_v1.Loan memory createdLoan =
            lendingFacility.getLoan(lendingFacility.nextLoanId() - 1);
        assertEq(createdLoan.borrower, user, "Loan borrower should be correct");
        assertEq(
            createdLoan.principalAmount,
            borrowAmount,
            "Loan principal should match borrow amount"
        );
        assertEq(
            createdLoan.lockedIssuanceTokens,
            requiredIssuanceTokens,
            "Locked issuance tokens should match"
        );
        assertTrue(createdLoan.isActive, "Loan should be active");
        assertEq(
            createdLoan.timestamp,
            block.timestamp,
            "Loan timestamp should be current block timestamp"
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
        issuanceToken.mint(user, requiredIssuanceTokens);

        vm.prank(user);
        issuanceToken.approve(address(lendingFacility), requiredIssuanceTokens);

        // Given: the user has sufficient borrowing power
        uint userBorrowingPower = requiredIssuanceTokens
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
        ├── Given a user borrows tokens at different floor prices
        └── When the borrow transaction completes
            └── Then the outstanding loan should equal the sum of borrow amounts
                └── And the floor price should be different
    */
    function testFuzzPublicBorrow_succeedsGivenUserBorrowsTwiceAtDifferentFloorPrices(
        uint borrowAmount1_,
        uint borrowAmount2_
    ) public {
        // // Given: a user has issuance tokens
        address user = makeAddr("user");

        uint maxBorrowableQuota = lendingFacility.getBorrowCapacity()
            * lendingFacility.borrowableQuota() / 10_000;

        borrowAmount1_ = bound(borrowAmount1_, 1, maxBorrowableQuota / 2);
        uint borrowAmount1 = borrowAmount1_;

        borrowAmount2_ =
            bound(borrowAmount2_, 1, maxBorrowableQuota - borrowAmount1);
        uint borrowAmount2 = borrowAmount2_;

        uint requiredIssuanceTokens1 = lendingFacility
            .exposed_calculateRequiredIssuanceTokens(borrowAmount1);
        issuanceToken.mint(user, requiredIssuanceTokens1);

        uint requiredIssuanceTokens2 = lendingFacility
            .exposed_calculateRequiredIssuanceTokens(borrowAmount2);
        issuanceToken.mint(user, requiredIssuanceTokens2);

        vm.startPrank(user);
        issuanceToken.approve(address(lendingFacility), requiredIssuanceTokens1);
        uint loanId1 = lendingFacility.borrow(borrowAmount1);
        vm.stopPrank();
        // Use helper function to mock floor price
        uint mockFloorPrice = 0.75 ether;
        _mockFloorPrice(mockFloorPrice);

        vm.startPrank(user);
        issuanceToken.approve(address(lendingFacility), requiredIssuanceTokens2);
        uint loanId2 = lendingFacility.borrow(borrowAmount2);
        vm.stopPrank();

        assertEq(
            lendingFacility.getOutstandingLoan(user),
            borrowAmount1 + borrowAmount2,
            "Outstanding loan should equal the sum of borrow amounts"
        );

        // Assert: User should have exactly 2 active loans
        ILM_PC_Lending_Facility_v1.Loan[] memory userLoans =
            lendingFacility.getUserLoans(user);
        assertEq(userLoans.length, 2, "User should have exactly 2 loans");

        uint initialFloorPrice = DEFAULT_SEG0_INITIAL_PRICE; // 0.5 ether

        // Floor price should be different
        assertTrue(
            userLoans[0].floorPriceAtBorrow == initialFloorPrice
                && userLoans[1].floorPriceAtBorrow == mockFloorPrice,
            "Loans should have different floor prices"
        );

        assertNotEq(loanId1, loanId2, "Loan IDs should be different");
    }

    function testFuzzPublicBorrow_succeedsGivenUserBorrowsSameAmountAtDifferentFloorPrices(
        uint borrowAmount_
    ) public {
        // Given: a user has issuance tokens
        address user = makeAddr("user");

        uint maxBorrowableQuota = lendingFacility.getBorrowCapacity()
            * lendingFacility.borrowableQuota() / 10_000;

        borrowAmount_ = bound(borrowAmount_, 1, maxBorrowableQuota / 2);
        uint borrowAmount = borrowAmount_;

        uint requiredIssuanceTokens = lendingFacility
            .exposed_calculateRequiredIssuanceTokens(borrowAmount);
        issuanceToken.mint(user, requiredIssuanceTokens);

        vm.startPrank(user);
        issuanceToken.approve(address(lendingFacility), requiredIssuanceTokens);
        uint loanId1 = lendingFacility.borrow(borrowAmount);
        vm.stopPrank();

        // Use helper function to mock floor price
        uint mockFloorPrice = 0.75 ether;
        _mockFloorPrice(mockFloorPrice);

        requiredIssuanceTokens = lendingFacility
            .exposed_calculateRequiredIssuanceTokens(borrowAmount);
        issuanceToken.mint(user, requiredIssuanceTokens);

        vm.startPrank(user);
        issuanceToken.approve(address(lendingFacility), requiredIssuanceTokens);
        uint loanId2 = lendingFacility.borrow(borrowAmount);
        vm.stopPrank();

        // Assert: User should have exactly 2 active loans
        uint[] memory userLoanIds = lendingFacility.getUserLoanIds(user);
        assertEq(userLoanIds.length, 2, "User should have exactly 2 loans");

        // Get loan details for both loans
        ILM_PC_Lending_Facility_v1.Loan memory loan1 =
            lendingFacility.getLoan(userLoanIds[0]);
        ILM_PC_Lending_Facility_v1.Loan memory loan2 =
            lendingFacility.getLoan(userLoanIds[1]);

        // Testing borrow of same amount of tokens at different floor prices should create 2 loans
        // with different floor prices, principal amount, and locked issuance tokens
        // The locked issuance tokens for second loan should be less than first since the floor price has increased

        assertNotEq(loanId1, loanId2, "Loan IDs should be different");
        assertGt(
            lendingFacility.calculateLoanRepaymentAmount(userLoanIds[0]),
            0,
            "Loan should have a repayment amount"
        );
        assertGt(
            lendingFacility.calculateLoanRepaymentAmount(userLoanIds[1]),
            0,
            "Loan should have a repayment amount"
        );

        assertNotEq(
            loan1.floorPriceAtBorrow,
            loan2.floorPriceAtBorrow,
            "Loans should have different floor prices"
        );
        assertEq(
            loan1.principalAmount,
            loan2.principalAmount,
            "Loans should have the same principal amount"
        );
        assertGt(
            loan1.lockedIssuanceTokens,
            loan2.lockedIssuanceTokens,
            "Loans should have different locked issuance tokens"
        );
    }
    /* Test: Function borrow()
        ├── Given a user wants to borrow tokens
        └── And the borrow amount exceeds the borrowable quota
            └── When the user tries to borrow collateral tokens
                └── Then the transaction should revert with BorrowableQuotaExceeded error
    */

    function testFuzzPublicBorrow_revertsGivenBorrowableQuotaExcedded(
        uint borrowAmount_
    ) public {
        // Given: a user has issuance tokens
        address user = makeAddr("user");

        uint maxBorrowableQuota = lendingFacility.getBorrowCapacity()
            * lendingFacility.borrowableQuota() / 10_000;

        borrowAmount_ =
            bound(borrowAmount_, maxBorrowableQuota + 1, type(uint128).max);
        uint borrowAmount = borrowAmount_;

        uint requiredIssuanceTokens = lendingFacility
            .exposed_calculateRequiredIssuanceTokens(borrowAmount);
        issuanceToken.mint(user, requiredIssuanceTokens);

        lendingFacility.setBorrowableQuota(1000); //mock set it to 10%

        vm.startPrank(user);
        issuanceToken.approve(address(lendingFacility), requiredIssuanceTokens);
        vm.expectRevert(
            ILM_PC_Lending_Facility_v1
                .Module__LM_PC_Lending_Facility_BorrowableQuotaExceeded
                .selector
        );

        lendingFacility.borrow(borrowAmount);
        vm.stopPrank();
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

    // ================================================================
    // Test: borrowFor

    /* Test: Function borrowFor()
        ├── Given a user wants to borrow tokens for another user
        └── And the receiver address is invalid
            └── When the user tries to borrow collateral tokens
                └── Then the transaction should revert with InvalidReceiver error
    */

    function testPublicBorrowFor_revertsGivenInvalidReceiver() public {
        address receiver = address(0);
        uint borrowAmount = 25 ether;
        vm.expectRevert(
            ILM_PC_Lending_Facility_v1
                .Module__LM_PC_Lending_Facility_InvalidReceiver
                .selector
        );
        lendingFacility.borrowFor(receiver, borrowAmount);
    }

    /* Test: Function borrowFor()
        ├── Given a user wants to borrow tokens for another user
        └── And the receiver address is valid
            └── When the user tries to borrow collateral tokens
                └── Then the transaction should succeed
                └── And the loan shoudl be created on behalf of the receiver
    */
    function testFuzzPublicBorrowFor_succeedsGivenValidReceiver(
        uint borrowAmount_,
        address receiver_
    ) public {
        // Given: a user wants to borrow tokens for another user
        address user = makeAddr("user");
        vm.assume(
            receiver_ != address(0) && receiver_ != address(this)
                && receiver_ != address(user)
        );

        uint maxBorrowableQuota = lendingFacility.getBorrowCapacity()
            * lendingFacility.borrowableQuota() / 10_000;

        borrowAmount_ = bound(borrowAmount_, 1, maxBorrowableQuota);
        uint borrowAmount = borrowAmount_;

        // Calculate how much issuance tokens will be needed
        uint requiredIssuanceTokens = lendingFacility
            .exposed_calculateRequiredIssuanceTokens(borrowAmount);
        issuanceToken.mint(user, requiredIssuanceTokens);

        vm.startPrank(user);
        issuanceToken.approve(address(lendingFacility), requiredIssuanceTokens);

        // When: the user borrows collateral tokens
        uint outstandingLoanBefore = lendingFacility.getOutstandingLoan(user);
        uint currentlyBorrowedBefore = lendingFacility.currentlyBorrowedAmount();
        uint lockedTokensBefore = lendingFacility.getLockedIssuanceTokens(user);

        uint loanId = lendingFacility.borrowFor(receiver_, borrowAmount);
        vm.stopPrank();
        // Then: verify the core state

        assertGt(loanId, 0, "Loan ID should be greater than 0");

        assertEq(
            lendingFacility.getOutstandingLoan(receiver_),
            outstandingLoanBefore + borrowAmount,
            "Outstanding loan should increase by borrow amount"
        );

        assertEq(
            lendingFacility.getLockedIssuanceTokens(receiver_),
            lockedTokensBefore + requiredIssuanceTokens,
            "Issuance tokens should be locked automatically"
        );

        assertEq(
            lendingFacility.currentlyBorrowedAmount(),
            currentlyBorrowedBefore + borrowAmount,
            "System borrowed amount should increase by borrow amount"
        );

        // And: verify the loan was created correctly
        ILM_PC_Lending_Facility_v1.Loan memory createdLoan =
            lendingFacility.getLoan(lendingFacility.nextLoanId() - 1);
        assertEq(
            createdLoan.borrower, receiver_, "Loan borrower should be correct"
        );
        assertEq(
            createdLoan.principalAmount,
            borrowAmount,
            "Loan principal should match borrow amount"
        );
        assertEq(
            createdLoan.lockedIssuanceTokens,
            requiredIssuanceTokens,
            "Locked issuance tokens should match"
        );
        assertTrue(createdLoan.isActive, "Loan should be active");
        assertEq(
            createdLoan.timestamp,
            block.timestamp,
            "Loan timestamp should be current block timestamp"
        );
    }

    // =========================================================================
    // Test: Buy and Borrow

    /* Test: Function buyAndBorrow()
        ├── Given a user wants to use buyAndBorrow
        └── And the user provides leverage exceeding maximum allowed limit
            └── When the user executes buyAndBorrow
                └── Then the transaction should revert with InvalidLeverage error
    */
    function testFuzzPublicBuyAndBorrow_revertsGivenInvalidLeverage(
        uint leverage_
    ) public {
        // Given: a user wants to use buyAndBorrow
        address user = makeAddr("user");
        orchestratorToken.mint(user, 100 ether);
        fmBcDiscrete.openBuy();

        leverage_ =
            bound(leverage_, lendingFacility.maxLeverage() + 1, type(uint8).max);
        uint leverage = leverage_;

        vm.startPrank(user);
        vm.expectRevert(
            ILM_PC_Lending_Facility_v1
                .Module__LM_PC_Lending_Facility_InvalidLeverage
                .selector
        );
        lendingFacility.buyAndBorrow(100 ether, leverage);
        vm.stopPrank();
    }

    /* Test: Function buyAndBorrow()
        ├── Given a user wants to use buyAndBorrow
        │   └── And the user has no collateral tokens
        │       └── When the user executes buyAndBorrow
        │           └── Then the transaction should revert with NoCollateralAvailable error
    */

    function testFuzzPublicBuyAndBorrow_revertsGivenNoCollateralAvailable(
        uint leverage_
    ) public {
        // Given: a user wants to use buyAndBorrow
        address user = makeAddr("user");

        leverage_ = bound(leverage_, 1, lendingFacility.maxLeverage());
        uint leverage = leverage_;

        vm.prank(user);
        vm.expectRevert(
            ILM_PC_Lending_Facility_v1
                .Module__LM_PC_Lending_Facility_NoCollateralAvailable
                .selector
        );
        lendingFacility.buyAndBorrow(0, leverage);
    }

    /* Test: Function buyAndBorrow()
    ├── Given a user wants to use buyAndBorrow
    └── And the bonding curve is not open for buying
        └── When the user executes buyAndBorrow
            └── Then the transaction should revert with appropriate error
    */
    function testFuzzPublicBuyAndBorrow_revertsGivenBondingCurveClosed(
        uint leverage_
    ) public {
        // Given: a user wants to use buyAndBorrow
        address user = makeAddr("user");
        leverage_ = bound(leverage_, 1, lendingFacility.maxLeverage());
        uint leverage = leverage_;

        orchestratorToken.mint(user, 100 ether);
        //bonding curve is closed by default (not calling fmBcDiscrete.openBuy())

        vm.startPrank(user);
        // The transaction should revert when trying to buy from a closed bonding curve
        vm.expectRevert(); // This will revert due to bonding curve being closed
        lendingFacility.buyAndBorrow(100 ether, leverage);
        vm.stopPrank();
    }

    /* Test: Function buyAndBorrow()
        ├── Given a user wants to use buyAndBorrow
        │   └── And the user has sufficient collateral tokens
        │   └── And the bonding curve is open for buying
        │   └── And the user provides valid leverage within limits
        │   └── And the user has approved sufficient token allowances
        │       └── When the user executes buyAndBorrow
        │           ├── Then the user should receive issuance tokens from the buy operation
        │           ├── And the user's collateral balance should decrease (due to fees and purchases)
        │           └── And the user should have an outstanding loan
    */
    function testFuzzPublicBuyAndBorrow_succeedsGivenValidLeverage(
        uint leverage_,
        uint collateralAmount_
    ) public {
        // Given: a user has issuance tokens
        address user = makeAddr("user");
        leverage_ = bound(leverage_, 1, lendingFacility.maxLeverage());
        uint leverage = leverage_;

        collateralAmount_ = bound(collateralAmount_, 1 ether, 100 ether);

        orchestratorToken.mint(user, collateralAmount_); // @note : Keeping this fixed for now, since fuzzing this results in various reverts.
        fmBcDiscrete.openBuy();

        uint outstandingLoanBefore = lendingFacility.getOutstandingLoan(user);
        uint collateralBalanceBefore = orchestratorToken.balanceOf(user);

        vm.startPrank(user);
        orchestratorToken.approve(address(lendingFacility), collateralAmount_);

        lendingFacility.buyAndBorrow(collateralAmount_, leverage);
        vm.stopPrank();

        // Then: verify state changes
        // User should have an outstanding loan
        uint outstandingLoanAfter = lendingFacility.getOutstandingLoan(user);
        uint collateralBalanceAfter = orchestratorToken.balanceOf(user);
        assertGt(
            outstandingLoanAfter,
            outstandingLoanBefore,
            "User should have an outstanding loan after borrowing"
        );

        // Get current loan IDs and verify loan amounts
        uint[] memory loanIds = lendingFacility.getUserLoanIds(user);

        uint totalLoanAmount = 0;
        for (uint i = 0; i < loanIds.length; i++) {
            ILM_PC_Lending_Facility_v1.Loan memory loan =
                lendingFacility.getLoan(loanIds[i]);
            totalLoanAmount += loan.remainingPrincipal;
        }

        // Assert that the sum of individual loan amounts equals the total outstanding loan
        assertEq(
            totalLoanAmount,
            outstandingLoanAfter,
            "Sum of individual loan amounts should equal total outstanding loan"
        );

        assertLt(
            collateralBalanceAfter,
            collateralBalanceBefore,
            "Collateral balance should decrease"
        );
    }

    /* Test: Function buyAndBorrow() and repay()
        ├── Given a user has issuance tokens through buyAndBorrow
           ├── And the user has an outstanding loan
           └── And the user has sufficient orchestrator tokens for partial repayment
               └── When the user repays a partial amount
                   └── Then the outstanding loan should be reduced by the repayment amount
    */
    function testFuzzPublicBuyAndBorrow_succeedsValidRepayment(
        uint leverage_,
        uint collateralAmount_,
        uint repaymentAmount_
    ) public {
        // Given: a user has issuance tokens
        address user = makeAddr("user");
        leverage_ = bound(leverage_, 1, lendingFacility.maxLeverage());

        collateralAmount_ = bound(collateralAmount_, 1 ether, 100 ether);
        testFuzzPublicBuyAndBorrow_succeedsGivenValidLeverage(
            leverage_, collateralAmount_
        );

        uint outstandingLoan = lendingFacility.getOutstandingLoan(user);

        repaymentAmount_ = bound(repaymentAmount_, 1, outstandingLoan);
        orchestratorToken.mint(user, repaymentAmount_); // Mint the repaymentAmount_ to user to pay the outstandingLoan

        vm.startPrank(user);
        orchestratorToken.approve(address(lendingFacility), type(uint).max);

        for (uint i = 0; i < lendingFacility.getUserLoanIds(user).length; i++) {
            lendingFacility.repay(
                lendingFacility.getUserLoanIds(user)[i], repaymentAmount_
            );
        }
        vm.stopPrank();

        assertEq(
            lendingFacility.getOutstandingLoan(user),
            outstandingLoan - repaymentAmount_
        );
    }

    /* Test: Function buyAndBorrow() and repay()
        ├── Given a user has issuance tokens through buyAndBorrow
           ├── And the user has an outstanding loan
           └── And the user has sufficient orchestrator tokens for full repayment
               └── When the user repays the full outstanding loan amount
                   └── Then the outstanding loan should be zero
    */
    function testFuzzPublicBuyAndBorrow_succeedsValidFullRepayment(
        uint leverage_,
        uint collateralAmount_
    ) public {
        // Given: a user has issuance tokens
        address user = makeAddr("user");
        leverage_ = bound(leverage_, 1, lendingFacility.maxLeverage());

        collateralAmount_ = bound(collateralAmount_, 1 ether, 100 ether);
        testFuzzPublicBuyAndBorrow_succeedsGivenValidLeverage(
            leverage_, collateralAmount_
        );

        uint outstandingLoan = lendingFacility.getOutstandingLoan(user);

        orchestratorToken.mint(user, outstandingLoan); // Mint the outstandingLoan to user to pay the Full Loan

        vm.startPrank(user);
        orchestratorToken.approve(address(lendingFacility), type(uint).max);

        for (uint i = 0; i < lendingFacility.getUserLoanIds(user).length; i++) {
            lendingFacility.repay(
                lendingFacility.getUserLoanIds(user)[i], outstandingLoan
            );
        }
        vm.stopPrank();

        assertEq(lendingFacility.getOutstandingLoan(user), 0);
    }

    // =========================================================================
    // Test: buyAndBorrowFor

    /* Test: Function buyAndBorrowFor()
        ├── Given a user wants to use buyAndBorrowFor
        └── And the user provides leverage exceeding maximum allowed limit
            └── When the user executes buyAndBorrowFor
                └── Then the transaction should revert with InvalidLeverage error
    */
    function testPublicBuyAndBorrowFor_revertsGivenInvalidReceiver() public {
        address user = makeAddr("user");
        address receiver = address(0);
        orchestratorToken.mint(user, 25 ether);
        fmBcDiscrete.openBuy();

        uint leverage = 2;

        vm.startPrank(user);
        vm.expectRevert(
            ILM_PC_Lending_Facility_v1
                .Module__LM_PC_Lending_Facility_InvalidReceiver
                .selector
        );
        lendingFacility.buyAndBorrowFor(receiver, 25 ether, leverage);
        vm.stopPrank();
    }

    /* Test: Function buyAndBorrowFor()
        ├── Given a user wants to use buyAndBorrowFor
        └── And the receiver address is valid
            └── When the user executes buyAndBorrowFor
                └── Then the transaction should succeed
    */
    function testFuzzPublicBuyAndBorrowFor_succeedsGivenValidReceiver(
        address receiver_,
        uint leverage_,
        uint collateralAmount_
    ) public {
        // Given: a user has issuance tokens
        address user = makeAddr("user");
        vm.assume(
            receiver_ != address(0) && receiver_ != address(this)
                && receiver_ != address(user)
        );
        leverage_ = bound(leverage_, 1, lendingFacility.maxLeverage());
        uint leverage = leverage_;

        collateralAmount_ = bound(collateralAmount_, 1 ether, 100 ether);

        orchestratorToken.mint(user, collateralAmount_);
        fmBcDiscrete.openBuy();

        uint outstandingLoanBefore =
            lendingFacility.getOutstandingLoan(receiver_);
        uint collateralBalanceBefore = orchestratorToken.balanceOf(user);

        vm.startPrank(user);
        orchestratorToken.approve(address(lendingFacility), collateralAmount_);

        vm.expectEmit(true, false, false, true);
        emit ILM_PC_Lending_Facility_v1.BuyAndBorrowCompleted(
            receiver_, leverage
        );
        lendingFacility.buyAndBorrowFor(receiver_, collateralAmount_, leverage);
        vm.stopPrank();

        // Then: verify state changes
        // User should have an outstanding loan
        uint outstandingLoanAfter =
            lendingFacility.getOutstandingLoan(receiver_);
        uint collateralBalanceAfter = orchestratorToken.balanceOf(user);
        assertGt(
            outstandingLoanAfter,
            outstandingLoanBefore,
            "User should have an outstanding loan after borrowing"
        );

        uint lockedIssuanceTokens =
            lendingFacility.getLockedIssuanceTokens(receiver_);
        assertGt(
            lockedIssuanceTokens,
            0,
            "Issuance tokens should be locked for the receiver"
        );

        assertLt(
            collateralBalanceAfter,
            collateralBalanceBefore,
            "Collateral balance should decrease"
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
        newQuota_ = bound(newQuota_, 1, 10_000);
        uint newQuota = newQuota_;
        lendingFacility.setBorrowableQuota(newQuota);

        assertEq(lendingFacility.borrowableQuota(), newQuota);
    }

    function testFuzzPublicSetBorrowableQuota_failsGivenExceedsMaxQuota(
        uint newQuota_
    ) public {
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
        address invalidFeeCalculator = address(0);
        vm.expectRevert(
            ILM_PC_Lending_Facility_v1
                .Module__LM_PC_Lending_Facility_InvalidFeeCalculatorAddress
                .selector
        );
        lendingFacility.setDynamicFeeCalculator(invalidFeeCalculator);
    }

    /* Test external setMaxLeverage function
        ├── Given caller has LENDING_FACILITY_MANAGER_ROLE
        │   └── When setting new maximum leverage
        │       ├── Then the maximum leverage should be updated
        └── Given invalid maximum leverage
            └── When trying to set maximum leverage
                └── Then it should revert with InvalidLeverage
    */

    function testFuzzPublicSetMaxLeverage_succeedsGivenValidLeverage(
        uint newMaxLeverage_
    ) public {
        newMaxLeverage_ = bound(newMaxLeverage_, 1, type(uint8).max);
        uint newMaxLeverage = newMaxLeverage_;
        lendingFacility.setMaxLeverage(newMaxLeverage);

        assertEq(lendingFacility.maxLeverage(), newMaxLeverage);
    }

    function testPublicSetMaxLeverage_failsGivenInvalidLeverage() public {
        uint invalidMaxLeverage = 0;
        vm.expectRevert(
            ILM_PC_Lending_Facility_v1
                .Module__LM_PC_Lending_Facility_InvalidLeverage
                .selector
        );
        lendingFacility.setMaxLeverage(invalidMaxLeverage);
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
        issuanceToken.mint(user, requiredIssuanceTokens);

        vm.prank(user);
        issuanceToken.approve(address(lendingFacility), requiredIssuanceTokens);

        vm.prank(user);
        lendingFacility.borrow(borrowAmount);

        power = lendingFacility.getUserBorrowingPower(user);
        assertGt(power, 0);
    }

    function testGetCalculateLoanRepaymentAmount() public {
        uint loanId = 0;
        uint repaymentAmount =
            lendingFacility.calculateLoanRepaymentAmount(loanId);
        assertEq(repaymentAmount, 0);
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
        issuanceToken.mint(user, requiredIssuanceTokens);

        vm.prank(user);
        issuanceToken.approve(address(lendingFacility), requiredIssuanceTokens);

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

    /**
     * @dev Internal helper function to mock the floor price for testing
     * @param customFloorPrice The desired floor price (in wei, scaled by 1e18)
     */
    function _mockFloorPrice(uint customFloorPrice) internal {
        // Create a mock PackedSegment with the custom floor price
        PackedSegment[] memory mockSegments = new PackedSegment[](1);
        mockSegments[0] = PackedSegmentLib._create(
            customFloorPrice, // initialPrice: custom floor price
            0, // priceIncrease: 0 for flat segment
            500 ether, // supplyPerStep: any valid amount
            1 // numberOfSteps: 1 for single step
        );

        // Mock the getSegments() call on the DBC FM contract
        vm.mockCall(
            address(fmBcDiscrete), // target contract
            abi.encodeWithSignature("getSegments()"), // function signature
            abi.encode(mockSegments) // return data
        );
    }
}
