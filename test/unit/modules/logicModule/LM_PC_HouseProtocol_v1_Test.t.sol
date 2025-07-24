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

    // =========================================================================
    // State

    // SuT
    LM_PC_HouseProtocol_v1_Exposed lendingFacility;

    // Mocks
    // ERC20Mock collateralToken;
    // ERC20Mock issuanceToken;
    // address dbcFmAddress;

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
    // Test: Issuance Token Management

    /* Test external lockIssuanceTokens function
        ├── Given valid amount
        │   └── When user locks issuance tokens
        │       ├── Then their locked amount should increase
        │       └── Then tokens should be transferred to contract
        └── Given invalid amount
            └── When user tries to lock zero tokens
                └── Then it should revert with InvalidBorrowAmount
    */
    function testLockIssuanceTokens() public {
        address user = makeAddr("user");
        uint lockAmount = 100 ether;

        issuanceToken.mint(user, lockAmount);
        orchestratorToken.mint(user, lockAmount); // Mint collateral tokens for the user
        
        vm.prank(user);
        issuanceToken.approve(address(lendingFacility), lockAmount);
        vm.prank(user);
        orchestratorToken.approve(address(lendingFacility), lockAmount); // Approve collateral tokens

        vm.prank(user);
        lendingFacility.lockIssuanceTokens(lockAmount);

        assertEq(lendingFacility.getLockedIssuanceTokens(user), lockAmount);
    }

    function testLockIssuanceTokens_zeroAmount() public {
        address user = makeAddr("user");

        vm.prank(user);
        vm.expectRevert(ILM_PC_HouseProtocol_v1.Module__LM_PC_HouseProtocol_InvalidBorrowAmount.selector);
        lendingFacility.lockIssuanceTokens(0);
    }

    /* Test external unlockIssuanceTokens function
        ├── Given user has locked tokens and no outstanding loan
        │   └── When user unlocks tokens
        │       ├── Then their locked amount should decrease
        │       └── Then tokens should be transferred back to user
        └── Given user has outstanding loan
            └── When user tries to unlock tokens
                └── Then it should revert with CannotUnlockWithOutstandingLoan
    */
    function testUnlockIssuanceTokens() public {
        address user = makeAddr("user");
        uint lockAmount = 100 ether;
        uint unlockAmount = 50 ether;

        // Setup: lock tokens
        issuanceToken.mint(user, lockAmount);
        orchestratorToken.mint(user, lockAmount); // Mint collateral tokens for the user
        
        vm.prank(user);
        issuanceToken.approve(address(lendingFacility), lockAmount);
        vm.prank(user);
        orchestratorToken.approve(address(lendingFacility), lockAmount); // Approve collateral tokens
        
        vm.prank(user);
        lendingFacility.lockIssuanceTokens(lockAmount);

        // Test: unlock tokens
        vm.prank(user);
        lendingFacility.unlockIssuanceTokens(unlockAmount);

        assertEq(
            lendingFacility.getLockedIssuanceTokens(user),
            lockAmount - unlockAmount
        );
    }

    function testUnlockIssuanceTokens_withOutstandingLoan() public {
        address user = makeAddr("user");
        uint lockAmount = 100 ether;

        // Setup: lock tokens and borrow
        issuanceToken.mint(user, lockAmount);
        orchestratorToken.mint(user, lockAmount); // Mint collateral tokens for the user
        
        vm.prank(user);
        issuanceToken.approve(address(lendingFacility), lockAmount);
        vm.prank(user);
        orchestratorToken.approve(address(lendingFacility), lockAmount); // Approve collateral tokens
        
        vm.prank(user);
        lendingFacility.lockIssuanceTokens(lockAmount);

        // Borrow some tokens (this creates an outstanding loan)
        uint borrowAmount = 50 ether;
        vm.prank(user);
        lendingFacility.borrow(borrowAmount);

        // Try to unlock tokens
        vm.prank(user);
        vm.expectRevert(ILM_PC_HouseProtocol_v1.Module__LM_PC_HouseProtocol_CannotUnlockWithOutstandingLoan.selector);
        lendingFacility.unlockIssuanceTokens(50 ether);
    }

    // =========================================================================
    // Test: Borrowing

    /* Test external borrow function
        ├── Given valid borrow request
        │   └── When user borrows collateral tokens
        │       ├── Then their outstanding loan should increase
        │       ├── Then dynamic fee should be calculated and deducted
        │       └── Then net amount should be transferred to user
        └── Given invalid borrow request
            └── When user tries to borrow more than limit
                └── Then it should revert with appropriate error
    */
    function testBorrow() public {
        address user = makeAddr("user");
        uint lockAmount = 1000 ether;
        uint borrowAmount = 500 ether;

        // Setup: lock issuance tokens
        issuanceToken.mint(user, lockAmount);
        orchestratorToken.mint(user, lockAmount); // Mint collateral tokens for the user
        
        vm.prank(user);
        issuanceToken.approve(address(lendingFacility), lockAmount);
        vm.prank(user);
        orchestratorToken.approve(address(lendingFacility), lockAmount); // Approve collateral tokens
        
        vm.prank(user);
        lendingFacility.lockIssuanceTokens(lockAmount);

        // Test: borrow collateral tokens
        vm.prank(user);
        lendingFacility.borrow(borrowAmount);

        assertEq(lendingFacility.getOutstandingLoan(user), borrowAmount);
        assertEq(lendingFacility.currentlyBorrowedAmount(), borrowAmount);
    }

    function testBorrow_exceedsIndividualLimit() public {
        address user = makeAddr("user");
        uint lockAmount = 3000 ether; // Lock more tokens to have sufficient borrowing power
        uint borrowAmount = 600 ether; // More than individual limit (500 ether) but within borrowable quota (800 ether)

        // Setup: lock issuance tokens
        issuanceToken.mint(user, lockAmount);
        orchestratorToken.mint(user, lockAmount); // Mint collateral tokens for the user
        
        vm.prank(user);
        issuanceToken.approve(address(lendingFacility), lockAmount);
        vm.prank(user);
        orchestratorToken.approve(address(lendingFacility), lockAmount); // Approve collateral tokens
        
        vm.prank(user);
        lendingFacility.lockIssuanceTokens(lockAmount);

        // Test: try to borrow more than individual limit
        vm.prank(user);
        vm.expectRevert(ILM_PC_HouseProtocol_v1.Module__LM_PC_HouseProtocol_IndividualBorrowLimitExceeded.selector);
        lendingFacility.borrow(borrowAmount);
    }

    function testBorrow_zeroAmount() public {
        address user = makeAddr("user");

        vm.prank(user);
        vm.expectRevert(ILM_PC_HouseProtocol_v1.Module__LM_PC_HouseProtocol_InvalidBorrowAmount.selector);
        lendingFacility.borrow(0);
    }

    // =========================================================================
    // Test: Repaying

    /* Test external repay function
        ├── Given user has outstanding loan
        │   └── When user repays loan
        │       ├── Then their outstanding loan should decrease
        │       ├── Then collateral should be transferred back to facility
        │       └── Then issuance tokens should be unlocked proportionally
        └── Given user has no outstanding loan
            └── When user tries to repay
                └── Then it should revert with appropriate error
    */
    function testRepay() public {
        address user = makeAddr("user");
        uint lockAmount = 1000 ether;
        uint borrowAmount = 500 ether;
        uint repayAmount = 200 ether;

        // Setup: lock tokens and borrow
        issuanceToken.mint(user, lockAmount);
        orchestratorToken.mint(user, lockAmount); // Mint collateral tokens for the user
        
        vm.prank(user);
        issuanceToken.approve(address(lendingFacility), lockAmount);
        vm.prank(user);
        orchestratorToken.approve(address(lendingFacility), lockAmount); // Approve collateral tokens
        
        vm.prank(user);
        lendingFacility.lockIssuanceTokens(lockAmount);

        vm.prank(user);
        lendingFacility.borrow(borrowAmount);

        // Test: repay loan
        orchestratorToken.mint(user, repayAmount);
        vm.prank(user);
        orchestratorToken.approve(address(lendingFacility), repayAmount);

        vm.prank(user);
        lendingFacility.repay(repayAmount);

        assertEq(
            lendingFacility.getOutstandingLoan(user), borrowAmount - repayAmount
        );
        assertEq(
            lendingFacility.currentlyBorrowedAmount(),
            borrowAmount - repayAmount
        );
    }

    function testRepay_exceedsOutstandingLoan() public {
        address user = makeAddr("user");
        uint lockAmount = 1000 ether;
        uint borrowAmount = 500 ether;
        uint repayAmount = 600 ether;

        // Setup: lock tokens and borrow
        issuanceToken.mint(user, lockAmount);
        orchestratorToken.mint(user, lockAmount); // Mint collateral tokens for the user
        
        vm.prank(user);
        issuanceToken.approve(address(lendingFacility), lockAmount);
        vm.prank(user);
        orchestratorToken.approve(address(lendingFacility), lockAmount); // Approve collateral tokens
        
        vm.prank(user);
        lendingFacility.lockIssuanceTokens(lockAmount);

        vm.prank(user);
        lendingFacility.borrow(borrowAmount);

        // Test: try to repay more than outstanding loan
        orchestratorToken.mint(user, repayAmount);
        vm.prank(user);
        orchestratorToken.approve(address(lendingFacility), repayAmount);

        vm.prank(user);
        vm.expectRevert(ILM_PC_HouseProtocol_v1.Module__LM_PC_HouseProtocol_RepaymentAmountExceedsLoan.selector);
        lendingFacility.repay(repayAmount);
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
        vm.expectRevert(ILM_PC_HouseProtocol_v1.Module__LM_PC_HouseProtocol_BorrowableQuotaTooHigh.selector);
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

        vm.expectRevert(ILM_PC_HouseProtocol_v1.Module__LM_PC_HouseProtocol_InvalidFeeCalculatorAddress.selector);
        lendingFacility.setDynamicFeeCalculator(address(0));
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

        // Lock some tokens and check power
        uint lockAmount = 1000 ether;
        issuanceToken.mint(user, lockAmount);
        orchestratorToken.mint(user, lockAmount); // Mint collateral tokens for the user
        
        vm.prank(user);
        issuanceToken.approve(address(lendingFacility), lockAmount);
        vm.prank(user);
        orchestratorToken.approve(address(lendingFacility), lockAmount); // Approve collateral tokens
        
        vm.prank(user);
        lendingFacility.lockIssuanceTokens(lockAmount);

        power = lendingFacility.getUserBorrowingPower(user);
        assertGt(power, 0);
    }

    // =========================================================================
    // Test: Internal (tested through exposed_ functions)

    function testEnsureValidBorrowAmount() public {
        // Should not revert for valid amount
        lendingFacility.exposed_ensureValidBorrowAmount(100 ether);

        // Should revert for zero amount
        vm.expectRevert(ILM_PC_HouseProtocol_v1.Module__LM_PC_HouseProtocol_InvalidBorrowAmount.selector);
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

        // Lock tokens and check power
        uint lockAmount = 1000 ether;
        issuanceToken.mint(user, lockAmount);
        orchestratorToken.mint(user, lockAmount); // Mint collateral tokens for the user
        
        vm.prank(user);
        issuanceToken.approve(address(lendingFacility), lockAmount);
        vm.prank(user);
        orchestratorToken.approve(address(lendingFacility), lockAmount); // Approve collateral tokens
        
        vm.prank(user);
        lendingFacility.lockIssuanceTokens(lockAmount);

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
}
