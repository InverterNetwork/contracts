// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Internal imports
import {IOraclePrice_v1} from "@lm/interfaces/IOraclePrice_v1.sol";
import {IFM_PC_Oracle_Redeeming_v1} from
    "@fm/oracle/interfaces/IFM_PC_Oracle_Redeeming_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {OZErrors} from "test/utils/errors/OZErrors.sol";
import {
    BondingCurveBase_v1,
    IBondingCurveBase_v1
} from "@fm/bondingCurve/abstracts/BondingCurveBase_v1.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {
    RedeemingBondingCurveBase_v1,
    IRedeemingBondingCurveBase_v1
} from "@fm/bondingCurve/abstracts/RedeemingBondingCurveBase_v1.sol";
import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";
import {FM_BC_Tools} from "@fm/bondingCurve/FM_BC_Tools.sol";

// External imports
import {Clones} from "@oz/proxy/Clones.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Tests and Mocks
import {ModuleTest} from "test/modules/ModuleTest.sol";
import {ERC20PaymentClientBaseV2Mock} from
    "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV2Mock.sol";
import {ERC20Decimals_Mock} from "test/utils/mocks/ERC20Decimals_Mock.sol";
import {OraclePrice_Mock} from
    "test/utils/mocks/modules/logicModules/OraclePrice_Mock.sol";
import {InvalidOraclePrice_Mock} from
    "test/utils/mocks/modules/logicModules/InvalidOraclePrice_Mock.sol";
import {PP_Queue_ManualExecution_v1_Mock} from
    "test/utils/mocks/modules/paymentProcessor/PP_Queue_ManualExecution_v1_Mock.sol";

// System under testing (SUT)
import {FM_PC_Oracle_Redeeming_v1_Exposed} from
    "test/modules/fundingManager/oracle/FM_PC_Oracle_Redeeming_v1_Exposed.sol";

/**
 * @title FM_PC_ExternalPrice_Redeeming_v1_Test
 * @notice Test contract for FM_PC_Oracle_Redeeming_v1
 */
contract FM_PC_ExternalPrice_Redeeming_v1_Test is ModuleTest {
    // ============================================================================
    // Constants

    // Issuance token initial configuration
    string internal constant NAME = "Issuance Token";
    string internal constant SYMBOL = "IST";
    uint8 internal constant DECIMALS = 18;
    uint internal constant MAX_SUPPLY = type(uint).max;

    // Basis points (100%)
    uint internal constant BPS = 10_000;

    // FM initial configuration
    uint internal constant DEFAULT_BUY_FEE = 100; // 1%
    uint internal constant DEFAULT_SELL_FEE = 100; // 1%
    uint internal constant MAX_BUY_FEE = 500; // 5%
    uint internal constant MAX_SELL_FEE = 500; // 5%
    bool internal constant DIRECT_OPERATIONS_ONLY = true;

    // ============================================================================
    // State

    // Contracts
    FM_PC_Oracle_Redeeming_v1_Exposed fundingManager;
    ERC20Issuance_v1 issuanceToken;
    OraclePrice_Mock oracle;
    ERC20PaymentClientBaseV2Mock paymentClient;
    address impl;

    // Test addresses
    address projectTreasury;

    // ============================================================================
    // Setup

    function setUp() public {
        // Setup addresses
        projectTreasury = makeAddr("projectTreasury");

        // Create issuance token
        issuanceToken = new ERC20Issuance_v1(
            NAME, SYMBOL, DECIMALS, MAX_SUPPLY, address(this)
        );

        // Setup mock oracle
        impl = address(new OraclePrice_Mock());
        oracle = OraclePrice_Mock(Clones.clone(impl));

        _setUpOrchestrator(oracle);
        // Init mock oracle. No role authorization required as it is a mock
        oracle.init(_orchestrator, _METADATA, "");

        // Prepare config data
        bytes memory configData = abi.encode(
            projectTreasury, // oracle address
            address(issuanceToken), // issuance token
            address(_token), // accepted token
            DEFAULT_BUY_FEE, // buy fee
            DEFAULT_SELL_FEE, // sell fee
            MAX_SELL_FEE, // max sell fee
            MAX_BUY_FEE, // max buy fee
            DIRECT_OPERATIONS_ONLY // direct operations only flag
        );

        // Setup funding manager
        impl = address(new FM_PC_Oracle_Redeeming_v1_Exposed());
        fundingManager = FM_PC_Oracle_Redeeming_v1_Exposed(Clones.clone(impl));
        _setUpOrchestrator(fundingManager);

        // Initialize the funding manager
        fundingManager.init(_orchestrator, _METADATA, configData);

        // Grant minting rights to the FM in issuance token
        issuanceToken.setMinter(address(fundingManager), true);
        // set oracle address in FM
        fundingManager.setOracleAddress(address(oracle));

        // Grant whitelist role to test contract
        fundingManager.grantModuleRole(
            fundingManager.getWhitelistRole(), address(this)
        );
        // Grant queue executor role to test contract
        fundingManager.grantModuleRole(
            fundingManager.getQueueExecutorRole(), address(this)
        );

        // Open buy and sell
        fundingManager.openBuy();
        fundingManager.openSell();
    }

    // ============================================================================
    // Test Init

    // testInit(): This function tests all the getters
    function testInit() public override(ModuleTest) {
        assertEq(
            fundingManager.getProjectTreasury(),
            projectTreasury,
            "Project treasury not set correctly"
        );
        assertEq(
            fundingManager.getIssuanceToken(),
            address(issuanceToken),
            "Issuance token not set correctly"
        );
        assertEq(
            address(fundingManager.token()),
            address(_token),
            "Accepted token not set correctly"
        );
        assertEq(
            fundingManager.getBuyFee(),
            DEFAULT_BUY_FEE,
            "Buy fee not set correctly"
        );
        assertEq(
            fundingManager.getSellFee(),
            DEFAULT_SELL_FEE,
            "Sell fee not set correctly"
        );
        assertEq(
            fundingManager.getMaxProjectBuyFee(),
            MAX_BUY_FEE,
            "Max buy fee not set correctly"
        );
        assertEq(
            fundingManager.getMaxProjectSellFee(),
            MAX_SELL_FEE,
            "Max sell fee not set correctly"
        );
        assertEq(
            fundingManager.getIsDirectOperationsOnly(),
            DIRECT_OPERATIONS_ONLY,
            "Direct operations only flag not set correctly"
        );
    }

    /* testReinitFails()
        └── Given an initialized contract
            └── When trying to initialize again
                └── Then it should revert with InvalidInitialization
    */
    function testReinitFails() public override(ModuleTest) {
        bytes memory configData = abi.encode(
            address(projectTreasury), // treasury address
            address(issuanceToken), // issuance token
            address(_token), // accepted token
            DEFAULT_BUY_FEE, // buy fee
            DEFAULT_SELL_FEE, // sell fee
            MAX_SELL_FEE, // max sell fee
            MAX_BUY_FEE, // max buy fee
            DIRECT_OPERATIONS_ONLY // direct operations only flag
        );

        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        fundingManager.init(_orchestrator, _METADATA, configData);
    }

    // ============================================================================
    // Test External (public + external)

    /* Test: Function supportsInterface()
        └── Given different interface ids
            └── When the function supportsInterface() is called
                ├── Then it should return true for supported interfaces
                └── Then it should return false for unsupported interfaces
    */
    function testSupportsInterface_worksGivenDifferentInterfaces() public {
        // Test - Verify supported interfaces
        assertTrue(
            fundingManager.supportsInterface(
                type(IFM_PC_Oracle_Redeeming_v1).interfaceId
            ),
            "Should support IFM_PC_Oracle_Redeeming_v1"
        );

        assertTrue(
            fundingManager.supportsInterface(
                type(IFundingManager_v1).interfaceId
            ),
            "Should support IFundingManager_v1"
        );

        assertTrue(
            fundingManager.supportsInterface(type(IERC165).interfaceId),
            "Should support IERC165"
        );

        // Test - Verify unsupported interface
        bytes4 unsupportedInterfaceId = bytes4(keccak256("unsupported()"));
        assertFalse(
            fundingManager.supportsInterface(unsupportedInterfaceId),
            "Should not support random interface"
        );
    }

    /* Test: Function getWhitelistRole()
        └── Given we want to get the whitelist role
            └── When the function getWhitelistRole() is called
                └── Then it should return the correct whitelist role identifier
    */
    function testGetWhitelistRole_worksGivenWhitelistRoleRetrieved() public {
        // Test - Verify whitelist role
        bytes32 expectedRole = bytes32("WHITELIST_ROLE");
        assertEq(
            fundingManager.getWhitelistRole(),
            expectedRole,
            "Incorrect whitelist role identifier"
        );
    }

    /* Test: Function: getWhitelistRoleAdmin()
        └── Given we want to get the whitelist role admin
            └── When the function getWhitelistRoleAdmin() is called
                └── Then it should return the correct whitelist role admin identifier
    */
    function testGetWhitelistRoleAdmin_worksGivenWhitelistRoleAdminRetrieved()
        public
    {
        // Test - Verify whitelist role admin
        bytes32 expectedRole = bytes32("WHITELIST_ROLE_ADMIN");
        assertEq(
            fundingManager.getWhitelistRoleAdmin(),
            expectedRole,
            "Incorrect whitelist role admin identifier"
        );
    }

    /* Test: Function getQueueExecutorRole()
        └── Given we want to get the queue executor role
            └── When the function getQueueExecutorRole() is called
                └── Then it should return the correct queue executor role identifier
    */
    function testGetQueueExecutorRole_worksGivenQueueExecutorRoleRetrieved()
        public
    {
        // Test - Verify queue executor role
        bytes32 expectedRole = bytes32("QUEUE_EXECUTOR_ROLE");
        assertEq(
            fundingManager.getQueueExecutorRole(),
            expectedRole,
            "Incorrect queue executor role identifier"
        );
    }

    /* Test: Function getQueueExecutorRoleAdmin()
        └── Given we want to get the queue executor role admin
            └── When the function getQueueExecutorRoleAdmin() is called
                └── Then it should return the correct queue executor role admin identifier
    */
    function testGetQueueExecutorRoleAdmin_worksGivenQueueExecutorRoleAdminRetrieved(
    ) public {
        // Test - Verify queue executor role admin
        bytes32 expectedRole = bytes32("QUEUE_EXECUTOR_ROLE_ADMIN");
        assertEq(
            fundingManager.getQueueExecutorRoleAdmin(),
            expectedRole,
            "Incorrect queue executor role admin identifier"
        );
    }

    /* Test: Function getStaticPriceForBuying()
        ├── Given we want to get the static price for buying
            └── When the function getStaticPriceForBuying() is called
                └── Then it should return the correct static price for buying
    */
    function testGetStaticPriceForBuying_worksGivenStaticPriceForBuyingRetrieved(
    ) public {
        // Test - Verify static price for buying
        uint expectedPrice = 1e6;
        assertEq(
            fundingManager.getStaticPriceForBuying(),
            expectedPrice,
            "Incorrect static price for buying"
        );
    }

    /* Test: Function getStaticPriceForSelling()
        ├── Given we want to get the static price for selling
            └── When the function getStaticPriceForSelling() is called
                └── Then it should return the correct static price for selling
    */
    function testGetStaticPriceForSelling_worksGivenStaticPriceForSellingRetrieved(
    ) public {
        // Test - Verify static price for selling
        uint expectedPrice = 1e6;
        assertEq(
            fundingManager.getStaticPriceForSelling(),
            expectedPrice,
            "Incorrect static price for selling"
        );
    }

    /* Test: Function getOpenRedemptionAmount()
        └── Given multiple redemption orders are created
            └── When getOpenRedemptionAmount() is called
                └── Then it should return the total collateral amount pending redemption
    */
    function testGetOpenRedemptionAmount_worksGivenMultipleOrders() public {
        // Setup - Initial amount should be 0
        assertEq(
            fundingManager.getOpenRedemptionAmount(),
            0,
            "Initial open redemption amount should be 0"
        );

        // Setup - Create first order
        address receiver1_ = makeAddr("receiver1");
        uint depositAmount1_ = 1e18;
        uint collateralRedeemAmount1_ = 2e18;
        uint projectSellFeeAmount1_ = 1e17;

        fundingManager.exposed_createAndEmitOrder(
            receiver1_,
            depositAmount1_,
            collateralRedeemAmount1_,
            projectSellFeeAmount1_
        );

        // Test - Amount should be updated after first order
        assertEq(
            fundingManager.getOpenRedemptionAmount(),
            collateralRedeemAmount1_,
            "Open redemption amount should match first collateral amount"
        );

        // Setup - Create second order
        address receiver2_ = makeAddr("receiver2");
        uint depositAmount2_ = 2e18;
        uint collateralRedeemAmount2_ = 3e18;
        uint projectSellFeeAmount2_ = 2e17;

        fundingManager.exposed_createAndEmitOrder(
            receiver2_,
            depositAmount2_,
            collateralRedeemAmount2_,
            projectSellFeeAmount2_
        );

        // Test - Amount should be updated after second order
        assertEq(
            fundingManager.getOpenRedemptionAmount(),
            collateralRedeemAmount1_ + collateralRedeemAmount2_,
            "Open redemption amount should be sum of both collateral amounts"
        );
    }

    /* Test: Function getOrderId()
        └── Given a new order is created
            └── When getOrderId() is called
                └── Then it should return the correct order ID
    */
    function testGetOrderId_worksGivenNewOrderCreated() public {
        // Setup - Create first order
        address receiver1_ = makeAddr("receiver1");
        uint depositAmount1_ = 1e18;
        uint collateralRedeemAmount1_ = 2e18;
        uint projectSellFeeAmount1_ = 1e17;

        fundingManager.exposed_createAndEmitOrder(
            receiver1_,
            depositAmount1_,
            collateralRedeemAmount1_,
            projectSellFeeAmount1_
        );

        // Test - First order should have ID 1
        assertEq(fundingManager.getOrderId(), 1, "First order should have ID 1");

        // Setup - Create second order
        address receiver2_ = makeAddr("receiver2");
        uint depositAmount2_ = 2e18;
        uint collateralRedeemAmount2_ = 3e18;
        uint projectSellFeeAmount2_ = 2e17;

        fundingManager.exposed_createAndEmitOrder(
            receiver2_,
            depositAmount2_,
            collateralRedeemAmount2_,
            projectSellFeeAmount2_
        );

        // Test - Second order should have ID 2
        assertEq(
            fundingManager.getOrderId(), 2, "Second order should have ID 2"
        );
    }

    /* Test: Function depositReserve()
        └── Given a valid amount of tokens to deposit
            └── When depositReserve() is called
                └── Then it should transfer tokens to the funding manager
                └── And emit a ReserveDeposited event
    */
    function testDepositReserve_worksGivenValidAmount(uint amount_) public {
        // Setup - Bound amount to reasonable values and ensure non-zero
        amount_ = bound(amount_, 1, 1000e18);
        _prepareBuyOrSellConditions(
            address(_token), amount_, address(this), address(fundingManager)
        );

        // Test - Record balances before deposit
        uint balanceBefore = _token.balanceOf(address(this));
        uint fmBalanceBefore = _token.balanceOf(address(fundingManager));

        // Test - Expect ReserveDeposited event
        vm.expectEmit(true, true, true, true);
        emit IFM_PC_Oracle_Redeeming_v1.ReserveDeposited(address(this), amount_);

        // Test - Deposit reserve
        fundingManager.depositReserve(amount_);

        // Verify - Check balances after deposit
        assertEq(
            _token.balanceOf(address(this)),
            balanceBefore - amount_,
            "Sender balance not decreased correctly"
        );
        assertEq(
            _token.balanceOf(address(fundingManager)),
            fmBalanceBefore + amount_,
            "FM balance not increased correctly"
        );
    }

    /* Test: Function depositReserve()
        └── Given a zero amount
            └── When depositReserve() is called
                └── Then it should revert with InvalidAmount error
    */
    function testDepositReserve_revertGivenZeroAmount() public {
        // Test - Expect revert on zero amount
        vm.expectRevert(
            IFM_PC_Oracle_Redeeming_v1
                .Module__FM_PC_ExternalPrice_Redeeming_InvalidAmount
                .selector
        );
        fundingManager.depositReserve(0);
    }

    /* Test: Function buy()
        └── Given a user with WHITELIST_ROLE and buying is open
            └── When buy() is called with valid minAmountOut
                └── Then it should execute successfully
    */
    function testBuy_worksGivenWhitelistedUser() public {
        // Setup
        uint amount_ = 1e18;
        _prepareBuyOrSellConditions(
            address(_token), amount_, address(this), address(fundingManager)
        );

        // Setup - Calculate minimum amount out
        uint minAmountOut_ = fundingManager.calculatePurchaseReturn(amount_);

        // Test - Should not revert
        fundingManager.buy(amount_, minAmountOut_);
    }

    /* Test: Function buy()
        └── Given a user without WHITELIST_ROLE but buying is open
            └── When buy() is called with valid minAmountOut
                └── Then it should revert with Module__CallerNotAuthorized error
    */
    function testBuy_revertGivenNonWhitelistedUser() public {
        // Setup
        address nonWhitelisted_ = makeAddr("nonWhitelisted");
        uint amount_ = 1e18;
        // Get role for revert
        bytes32 roleId = _authorizer.generateRoleId(
            address(fundingManager), fundingManager.getWhitelistRole()
        );

        // Test - Switch to non-whitelisted user and expect revert
        vm.prank(nonWhitelisted_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                roleId,
                nonWhitelisted_
            )
        );
        fundingManager.buy(amount_, amount_);
    }

    /* Test: Function buyFor()
        └── Given a user with WHITELIST_ROLE and Third Party Operations (TPO) enabled
            └── When buyFor() is called
                └── Then it should execute successfully
    */
    function testBuyFor_worksGivenWhitelistedUserAndTPOEnabled() public {
        // Setup
        address receiver_ = makeAddr("receiver");
        uint amount_ = 1e18;
        _prepareBuyOrSellConditions(
            address(_token), amount_, address(this), address(fundingManager)
        );

        fundingManager.exposed_setIsDirectOperationsOnly(false);

        // Setup - Calculate minimum amount out
        uint minAmountOut_ = fundingManager.calculatePurchaseReturn(amount_);

        // Test - Should not revert
        fundingManager.buyFor(receiver_, amount_, minAmountOut_);
    }

    /* Test: Function buyFor()
        └── Given a user without WHITELIST_ROLE but Third Party Operations (TPO) enabled
            └── When buyFor() is called
                └── Then it should revert
    */
    function testBuyFor_revertGivenNonWhitelistedUserAndTPOEnabled() public {
        // Setup
        address nonWhitelisted_ = makeAddr("nonWhitelisted");
        address receiver_ = makeAddr("receiver");
        uint amount_ = 1e18;
        _prepareBuyOrSellConditions(
            address(_token), amount_, nonWhitelisted_, address(fundingManager)
        );

        fundingManager.exposed_setIsDirectOperationsOnly(false);

        // Setup - Calculate minimum amount out
        uint minAmountOut_ = fundingManager.calculatePurchaseReturn(amount_);

        // Test - Switch to non-whitelisted user and expect revert
        vm.startPrank(nonWhitelisted_);
        vm.expectRevert();
        fundingManager.buyFor(receiver_, amount_, minAmountOut_);
        vm.stopPrank();
    }

    /* Test: Function buyFor()
        └── Given a whitelisted user but Third Party Operations (TPO) disabled
            └── When buyFor() is called
                └── Then it should revert
    */
    function testBuyFor_revertGivenTPODisabled() public {
        // Setup
        address receiver_ = makeAddr("receiver");
        uint amount_ = 1e18;
        _prepareBuyOrSellConditions(
            address(_token), amount_, address(this), address(fundingManager)
        );

        // Setup - Calculate minimum amount out
        uint minAmountOut_ = fundingManager.calculatePurchaseReturn(amount_);

        // Test - Should revert as TPO is disabled
        vm.expectRevert();
        fundingManager.buyFor(receiver_, amount_, minAmountOut_);
    }

    /* Test: Function sell()
        └── Given a user with WHITELIST_ROLE and selling is open
            └── When sell() is called
                └── Then it should execute successfully
    */
    function testSell_worksGivenWhitelistedUser() public {
        // Setup
        uint amount_ = 1e18;
        _prepareBuyOrSellConditions(
            address(_token), amount_, address(this), address(fundingManager)
        );

        // Setup - Calculate minimum amount out
        uint minBuyAmountOut_ = fundingManager.calculatePurchaseReturn(amount_);

        // Test - Should not revert
        fundingManager.buy(amount_, minBuyAmountOut_);

        assertEq(
            issuanceToken.balanceOf(address(this)),
            minBuyAmountOut_,
            "Sender balance not decreased correctly"
        );

        uint minSellAmountOut_ =
            fundingManager.calculateSaleReturn(minBuyAmountOut_);

        // Test - Should not revert - sell the tokens we received from buying
        fundingManager.sell(minBuyAmountOut_, minSellAmountOut_);

        // Test - Verify balances
        assertEq(issuanceToken.balanceOf(address(fundingManager)), 0);
    }

    /* Test: Function sell()
        └── Given a user without WHITELIST_ROLE but selling is open
            └── When sell() is called
                └── Then it should revert (modifier in place test)
    */
    function testSell_revertGivenNonWhitelistedUser() public {
        // Setup
        address nonWhitelisted_ = makeAddr("nonWhitelisted");
        uint amount_ = 1e18;
        // Get role for revert
        bytes32 roleId = _authorizer.generateRoleId(
            address(fundingManager), fundingManager.getWhitelistRole()
        );

        // Setup - Calculate minimum amount out
        uint minAmountOut_ = fundingManager.calculateSaleReturn(amount_);

        // Test - Switch to non-whitelisted user and expect revert
        vm.prank(nonWhitelisted_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                roleId,
                nonWhitelisted_
            )
        );
        fundingManager.sell(amount_, minAmountOut_);
    }
    /* Test: Function sellTo()
        └── Given selling is open
            └── And Third Party Operations (TPO) enabled
                └── And the caller has WHITELIST_ROLE
                    └── When sellTo() is called
                        └── Then it should execute successfully
    */

    function testSellTo_worksGivenWhitelistedUser() public {
        // Setup
        address receiver_ = makeAddr("receiver");
        uint amount_ = 1e18;
        _prepareBuyOrSellConditions(
            address(issuanceToken),
            amount_,
            address(this),
            address(fundingManager)
        );
        fundingManager.exposed_setIsDirectOperationsOnly(false);

        uint minSellAmountOut_ = fundingManager.calculateSaleReturn(amount_);

        // Test - Should not revert - sell the tokens we received from buying
        fundingManager.sellTo(receiver_, amount_, minSellAmountOut_);

        // Test - Verify balances
        assertEq(issuanceToken.balanceOf(address(fundingManager)), 0);
    }

    /* Test: Function sellTo()
        └── Given selling is open
            └── And Third Party Operations (TPO) enabled
                └── And the caller has no WHITELIST_ROLE
                    └── When sellTo() is called
                        └── Then it should revert (modifier in place test)
    */
    function testSellTo_revertGivenNonWhitelistedUser() public {
        // Setup
        address nonWhitelisted_ = makeAddr("nonWhitelisted");
        address receiver_ = makeAddr("receiver");
        uint amount_ = 1e18;
        // Get role for revert
        bytes32 roleId = _authorizer.generateRoleId(
            address(fundingManager), fundingManager.getWhitelistRole()
        );
        // Enable TPO
        fundingManager.exposed_setIsDirectOperationsOnly(false);

        // Test - Switch to non-whitelisted user and expect revert
        vm.prank(nonWhitelisted_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                roleId,
                nonWhitelisted_
            )
        );
        fundingManager.sellTo(receiver_, amount_, amount_);
    }

    /* Test: Function transferOrchestratorToken()
        └── Given caller is not the payment client
            └── When transferOrchestratorToken() is called
                └── Then it should revert (modifier in place test)
    */
    function testTransferOrchestratorToken_revertGivenNonPaymentClient()
        public
    {
        // Setup
        address receiver_ = makeAddr("receiver");
        uint amount_ = 100;

        // Test - Should revert if not called by payment client
        vm.expectRevert(IModule_v1.Module__OnlyCallableByPaymentClient.selector);
        fundingManager.transferOrchestratorToken(receiver_, amount_);
    }

    /* Test: Function transferOrchestratorToken()
        └── Given caller is the payment client
            └── When transferOrchestratorToken() is called
                └── Then it should transfer the tokens
                   └── And it should emit the TransferOrchestratorToken event
        */
    function testTransferOrchestratorToken_worksGivenPaymentClient() public {
        // Setup
        address receiver_ = makeAddr("receiver");
        uint amount_ = 100;

        // Setup - Mint tokens to funding manager
        _prepareBuyOrSellConditions(
            address(_token), amount_, address(fundingManager), address(this)
        );

        // Setup - Create and register payment client
        paymentClient = new ERC20PaymentClientBaseV2Mock();
        _addLogicModuleToOrchestrator(address(paymentClient));

        // Setup - Mock payment client call
        vm.prank(address(paymentClient));

        // Test - Expect event
        vm.expectEmit(true, true, true, true, address(fundingManager));
        emit IFundingManager_v1.TransferOrchestratorToken(receiver_, amount_);

        // Test - Transfer tokens
        fundingManager.transferOrchestratorToken(receiver_, amount_);

        // Test - Verify balances
        assertEq(_token.balanceOf(receiver_), amount_);
        assertEq(_token.balanceOf(address(fundingManager)), 0);
    }

    /* Test: Function amountPaid()
        └── Given a payment is made
            └── When amountPaid() is called by the payment processor
                └── Then it should update outstanding token amounts
                └── And emit PaymentOrderProcessed event
    */
    function testAmountPaid_worksGivenPaymentMade() public {
        // Setup - Create order to generate payment
        address receiver_ = makeAddr("receiver");
        uint depositAmount_ = 1e18;
        uint collateralRedeemAmount_ = 2e18;
        uint projectSellFeeAmount_ = 1e17;

        fundingManager.exposed_createAndEmitOrder(
            receiver_,
            depositAmount_,
            collateralRedeemAmount_,
            projectSellFeeAmount_
        );

        // Setup - Mock payment processor call
        vm.startPrank(address(_orchestrator.paymentProcessor()));

        // Test - Call amountPaid
        fundingManager.amountPaid(address(_token), collateralRedeemAmount_);

        // Test - Verify outstanding amount is reduced
        assertEq(
            fundingManager.outstandingTokenAmount(address(_token)),
            0,
            "Outstanding amount should be reduced"
        );

        vm.stopPrank();
    }

    /* Test: Function setSellFee()
        ├── Given the sell fee is 0
        │   └── When the function setSellFee() is called
        │       └── Then it should set the sell fee correctly
    */
    function testSetSellFee_worksGivenZeroSellFee() public {
        // Test
        fundingManager.setSellFee(0);

        // Test - Verify state
        assertEq(fundingManager.sellFee(), 0);
    }

    /* Test: Function setSellFee()
        ├── Given the sell fee is not 0
        │   └── When the function setSellFee() is called
        │       └── Then it should set the sell fee correctly
    */
    function testSetSellFee_worksGivenNonZeroSellFee() public {
        // Test
        fundingManager.setSellFee(100);

        // Test - Verify state
        assertEq(fundingManager.sellFee(), 100);
    }

    /* Test: Function setBuyFee()
        ├── Given the buy fee is not 0
        │   └── When the function setSellFee() is called
        │       └── Then it should set the sell fee correctly
    */
    function testSetBuyFee_worksGivenNonZeroBuyFee() public {
        // Test
        fundingManager.setBuyFee(100);

        // Test - Verify state
        assertEq(fundingManager.buyFee(), 100);
    }

    /* Test: Function setBuyFee()
        ├── Given the buy fee is 0
        │   └── When the function setSellFee() is called
        │       └── Then it should revert
    */
    function testSetBuyFee_worksGivenZeroBuyFee() public {
        // Test
        fundingManager.setBuyFee(0);

        // Test - Verify state
        assertEq(fundingManager.buyFee(), 0);
    }

    /* Test: Function setProjectTreasury()
        ├── Given the project treasury is a valid address
        │   └── When the function setProjectTreasury() is called
        │       └── Then it should set the project treasury correctly
    */
    function testSetProjectTreasury_worksGivenValidAddress(
        address projectTreasury_
    ) public {
        // Setup
        vm.assume(projectTreasury_ != address(0));

        // Test
        fundingManager.setProjectTreasury(projectTreasury_);

        // Test - Verify state
        assertEq(fundingManager.getProjectTreasury(), projectTreasury_);
    }

    /* Test: Function setOracleAddress()
        ├── Given the oracle supports the IOraclePrice_v1 interface
        │   └── When the function _setOracleAddress() is called
        │       └── Then it should set the oracle address correctly
        └── Given the oracle does not support the IOraclePrice_v1 interface
            └── When the function _setOracleAddress() is called
                └── Then it should revert
    */
    function testSetOracleAddress_worksGivenValidOracle(address _oracle)
        public
    {
        // Setup
        vm.assume(address(_oracle) != address(0));

        OraclePrice_Mock newOracle = new OraclePrice_Mock();

        // Test
        fundingManager.setOracleAddress(address(newOracle));

        // Assert
        assertEq(
            fundingManager.getOracle(),
            address(newOracle),
            "Oracle address not set correctly"
        );
    }

    /* Test: Function setIsDirectOperationsOnly()
        └── Given a valid value
            └── When the function exposed_setIsDirectOperationsOnly() is called
                └── Then the value should be set correctly
    */
    function testSetIsDirectOperationsOnly_worksGivenValidValue(
        bool _isDirectOperationsOnly
    ) public {
        // Test
        fundingManager.setIsDirectOperationsOnly(_isDirectOperationsOnly);

        // Test - Verify state
        assertEq(
            fundingManager.getIsDirectOperationsOnly(),
            _isDirectOperationsOnly,
            "Is direct operations only not set correctly"
        );
    }

    /* Test: Function executeRedemptionQueue()
        └── Given caller does not have QUEUE_EXECUTOR_ROLE
            └── When executeRedemptionQueue() is called
                └── Then it should revert (modifier in place test)
    */
    function testExecuteRedemptionQueue_revertGivenCallerDoesNotHaveQueueExecutorRole(
    ) public {
        // Setup
        address nonExecutorRole = makeAddr("nonExecutorRole");
        bytes32 roleId = _authorizer.generateRoleId(
            address(fundingManager), fundingManager.getQueueExecutorRole()
        );

        // Test - Switch to non-executor role user and expect revert
        vm.prank(nonExecutorRole);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                roleId,
                nonExecutorRole
            )
        );

        // Test
        fundingManager.executeRedemptionQueue();
    }

    /* Test: Function executeRedemptionQueue()
        ├── Given caller has QUEUE_EXECUTOR_ROLE
        └── And the Payment Processor does not have the correct interface
                └── When executeRedemptionQueue() is called
                    └── Then it should revert
    */
    function testExecuteRedemptionQueue_revertGivenPaymentProcessorDoesNotHaveCorrectInterface(
    ) public {
        // Setup

        // Default testing Payment Processor does not have the correct interface,
        // which means we test the low level call failure.
        vm.expectRevert(
            abi.encodeWithSelector(
                IFM_PC_Oracle_Redeeming_v1
                    .Module__FM_PC_ExternalPrice_Redeeming_QueueExecutionFailed
                    .selector
            )
        );
        fundingManager.executeRedemptionQueue();
    }

    /* Test: Function executeRedemptionQueue()
        ├── Given caller has QUEUE_EXECUTOR_ROLE
        ├── And there are redemption orders in the queue
        └── And the payment processor has the correct interface
            └── When executeRedemptionQueue() is called
                ├── Then it should call payment processor with correct parameters
                └── And it should not revert
    */
    function testExecuteRedemptionQueue_worksGivenCallerHasQueueExecutorRole()
        public
    {
        // Setup - Create a redemption order
        address receiver_ = makeAddr("receiver");
        uint depositAmount_ = 1e18;
        uint collateralRedeemAmount_ = 2e18;
        uint projectSellFeeAmount_ = 1e17;

        // Setup payment processor with the correct interface, so the low level call
        // does not fail
        PP_Queue_ManualExecution_v1_Mock paymentProcessor =
            new PP_Queue_ManualExecution_v1_Mock();
        _addPaymentProcessorToOrchestrator(address(paymentProcessor));

        // Setup - Create order
        fundingManager.exposed_createAndEmitOrder(
            receiver_,
            depositAmount_,
            collateralRedeemAmount_,
            projectSellFeeAmount_
        );

        // Execute
        fundingManager.executeRedemptionQueue();

        // Test - Verify payment processor was called
        assertEq(
            paymentProcessor.processPaymentsTriggered(),
            1,
            "Payment processor should be triggered once"
        );
    }

    // ============================================================================
    // Test Internal

    /* Test: Function _setProjectTreasury()
        ├── Given the project treasury is the zero address
        │   └── When the function _setProjectTreasury() is called
        │       └── Then it should revert
        └── Given the project treasury is not the zero address
            └── When the function _setProjectTreasury() is called
                ├── Then it should set the project treasury correctly
                └── And it should emit an event
    */
    function testInternalSetProjectTreasury_revertGivenZeroAddress() public {
        // Test
        vm.expectRevert(
            abi.encodeWithSelector(
                IFM_PC_Oracle_Redeeming_v1
                    .Module__FM_PC_ExternalPrice_Redeeming_InvalidProjectTreasury
                    .selector
            )
        );
        fundingManager.exposed_setProjectTreasury(address(0));
    }

    function testInternalSetProjectTreasury_worksGivenValidAddress(
        address projectTreasury_
    ) public {
        // Setup
        vm.assume(projectTreasury_ != address(0));

        // Test
        vm.expectEmit(true, true, true, true);
        emit IFM_PC_Oracle_Redeeming_v1.ProjectTreasuryUpdated(
            projectTreasury, projectTreasury_
        );

        fundingManager.exposed_setProjectTreasury(projectTreasury_);

        // Assert
        assertEq(
            fundingManager.getProjectTreasury(),
            projectTreasury_,
            "Project treasury not set correctly"
        );
    }

    /* Test: Function _deductFromOpenRedemptionAmount()
        └── When the function _deductFromOpenRedemptionAmount() is called
            └── Then it should deduct the amount correctly
                └── And it should emit an event
    */
    function testInternalDeductFromOpenRedemptionAmount_worksGivenOpenRedemptionAmountUpdated(
        uint openRedemptionAmount_,
        uint amount_
    ) public {
        // Setup
        openRedemptionAmount_ = bound(openRedemptionAmount_, 1, type(uint).max);
        amount_ = bound(amount_, 1, openRedemptionAmount_);
        _setOpenRedemptionAmount(openRedemptionAmount_);

        // Test
        vm.expectEmit(true, true, true, true);
        emit IFM_PC_Oracle_Redeeming_v1.RedemptionAmountUpdated(
            openRedemptionAmount_ - amount_
        );

        fundingManager.exposed_deductFromOpenRedemptionAmount(amount_);

        // Assert
        assertEq(
            fundingManager.getOpenRedemptionAmount(),
            openRedemptionAmount_ - amount_,
            "Open redemption amount not deducted correctly"
        );
    }

    /* Test: Function _addToOpenRedemptionAmount()
        └── When the function _addToOpenRedemptionAmount() is called
            └── Then it should add the amount correctly
                └── And it should emit an event
    */
    function testInternalAddToOpenRedemptionAmount_worksGivenOpenRedemptionAmountUpdated(
        uint openRedemptionAmount_,
        uint amount_
    ) public {
        // Setup
        openRedemptionAmount_ =
            bound(openRedemptionAmount_, 0, type(uint).max - 2);
        amount_ = bound(amount_, 1, type(uint).max - openRedemptionAmount_);
        _setOpenRedemptionAmount(openRedemptionAmount_);

        // Test
        vm.expectEmit(true, true, true, true);
        emit IFM_PC_Oracle_Redeeming_v1.RedemptionAmountUpdated(
            openRedemptionAmount_ + amount_
        );

        fundingManager.exposed_addToOpenRedemptionAmount(amount_);

        // Assert
        assertEq(
            fundingManager.getOpenRedemptionAmount(),
            openRedemptionAmount_ + amount_,
            "Open redemption amount not added correctly"
        );
    }

    /* Test: Function _setOracleAddress()
        ├── Given the oracle does not support the IOraclePrice_v1 interface
        │   └── When the function _setOracleAddress() is called
        │       └── Then it should revert
        └── Given the oracle supports the IOraclePrice_v1 interface
            └── When the function _setOracleAddress() is called
                └── Then it should set the oracle address correctly
                    └── And it should emit an event
    */
    function testInternalSetOracleAddress_revertGivenOracleDoesNotSupportInterface(
    ) public {
        InvalidOraclePrice_Mock invalidOracle = new InvalidOraclePrice_Mock();
        // If no supportInterface is implemented, it reverts without the custom
        // error message.
        vm.expectRevert();
        fundingManager.exposed_setOracleAddress(address(invalidOracle));
    }

    function testInternalSetOracleAddress_worksGivenOracleSupportsInterface()
        public
    {
        // Setup
        OraclePrice_Mock newOracle = new OraclePrice_Mock();
        address currentOracle = fundingManager.getOracle();

        // Test
        vm.expectEmit(true, true, true, true);
        emit IFM_PC_Oracle_Redeeming_v1.OracleUpdated(
            currentOracle, address(newOracle)
        );

        fundingManager.exposed_setOracleAddress(address(newOracle));

        // Assert
        assertEq(
            fundingManager.getOracle(),
            address(newOracle),
            "Oracle address not set correctly"
        );
        assertNotEq(
            fundingManager.getOracle(),
            currentOracle,
            "Oracle address not updated correctly"
        );
    }

    /* Test: Function _handleCollateralTokensBeforeBuy()
        └── When the function _handleCollateralTokensBeforeBuy() is called
            └── Then it should mint tokens to the recipient
    */
    function testInternalHandleCollateralTokensBeforeBuy_worksGivenMintedTokens(
        address recipient_,
        uint amount_
    ) public {
        // Setup
        vm.assume(recipient_ != address(0));
        vm.assume(amount_ > 0);
        _prepareBuyOrSellConditions(
            address(_token), amount_, recipient_, address(fundingManager)
        );

        // Assert
        assertEq(
            _token.balanceOf(recipient_),
            amount_,
            "Recipient should the right amount of tokens"
        );
        assertEq(
            _token.balanceOf(projectTreasury),
            0,
            "Project treasury should not have any tokens"
        );

        // Test
        fundingManager.exposed_handleCollateralTokensBeforeBuy(
            recipient_, amount_
        );

        // Assert
        assertEq(
            _token.balanceOf(recipient_),
            0,
            "Tokens should be transferred to the project treasury"
        );
        assertEq(
            _token.balanceOf(projectTreasury),
            amount_,
            "Project treasury should have the right amount of tokens"
        );
    }

    /* Test: Function _handleIssuanceTokensAfterBuy()
        └── When the function _handleIssuanceTokensAfterBuy() is called
            └── Then it should mint tokens to the recipient
    */
    function testInternalHandleIssuanceTokensAfterBuy_worksGivenMintedTokens(
        address recipient_,
        uint amount_
    ) public {
        // Setup
        vm.assume(recipient_ != address(0));
        vm.assume(amount_ > 0);

        // Assert
        assertEq(
            issuanceToken.balanceOf(recipient_),
            0,
            "Recipient should not have any tokens"
        );

        // Test
        fundingManager.exposed_handleIssuanceTokensAfterBuy(recipient_, amount_);

        // Assert
        assertEq(
            issuanceToken.balanceOf(recipient_),
            amount_,
            "Recipient should have the right amount of tokens"
        );
    }

    /* Test: Function _setIssuanceToken()
        └── When the function _setIssuanceToken() is called
            └── Then it should set the issuance token correctly
                └── And it should emit an event with the right decimals
    */

    function testInternalSetIssuanceToken_worksGivenValidToken(uint8 decimals_)
        public
    {
        // Setup
        vm.assume(decimals_ > 0);
        ERC20Issuance_v1 newIssuanceToken = new ERC20Issuance_v1(
            "New Issuance Token", "NIT", decimals_, MAX_SUPPLY, address(this)
        );

        // Assert
        assertEq(
            fundingManager.getIssuanceToken(),
            address(issuanceToken),
            "Issuance token not set correctly during initialization"
        );

        // Test
        vm.expectEmit(true, true, true, true);
        emit IBondingCurveBase_v1.IssuanceTokenSet(
            address(newIssuanceToken), decimals_
        );

        fundingManager.exposed_setIssuanceToken(address(newIssuanceToken));

        // Assert
        assertEq(
            fundingManager.getIssuanceToken(),
            address(newIssuanceToken),
            "Issuance token not set correctly"
        );
    }

    /* Test: Function _redeemTokensFormulaWrapper()
        └── Given the amount is bigger than 0
            └── When the function _redeemTokensFormulaWrapper() is called
                └── Then it should return the correct amount of redeemable collateral tokens
    */
    function testInternalRedeemTokensFormulaWrapper_worksGivenValidAmount(
        uint amount_,
        uint8 issuanceTokenDecimals_,
        uint8 collateralTokenDecimals_
    ) public {
        // Setup
        amount_ = bound(amount_, 1, type(uint64).max);
        issuanceTokenDecimals_ = uint8(bound(issuanceTokenDecimals_, 1, 18));
        collateralTokenDecimals_ = uint8(bound(collateralTokenDecimals_, 1, 18));
        // Convert amount to issuance token decimals
        amount_ = amount_ * 10 ** issuanceTokenDecimals_;

        FM_PC_Oracle_Redeeming_v1_Exposed newFundingManager =
        FM_PC_Oracle_Redeeming_v1_Exposed(
            _initializeFundingManagerWithDifferentTokenDecimals(
                issuanceTokenDecimals_, collateralTokenDecimals_
            )
        );

        // Set oracle address and price
        newFundingManager.setOracleAddress(address(oracle));
        uint oraclePrice = 10 ** collateralTokenDecimals_;
        oracle.setRedemptionPrice(oraclePrice);

        // Prepare deposit amount (scaled to issuance decimals)
        uint depositAmount = amount_ * 10 ** issuanceTokenDecimals_;

        // Test
        uint actualRedeemAmount =
            newFundingManager.exposed_redeemTokensFormulaWrapper(depositAmount);

        // Calculate expected amount manually following the formula:
        // 1. Convert to collateral decimals
        uint collateralTokenDecimalConvertedAmount = FM_BC_Tools
            ._convertAmountToRequiredDecimal(
            depositAmount, issuanceTokenDecimals_, collateralTokenDecimals_
        );

        // 2. Apply oracle price and final division
        uint expectedAmount = (
            collateralTokenDecimalConvertedAmount * oraclePrice
        ) / 10 ** collateralTokenDecimals_;

        // Assert - Verify calculation matches expected
        assertEq(
            actualRedeemAmount,
            expectedAmount,
            "Redeem amount calculation incorrect"
        );
    }

    /* Test: Function testInternalIssueTokensFormulaWrapper_worksGivenValidAmount()
        └── Given a valid amount
            └── When the function exposed_issueTokensFormulaWrapper() is called
                └── Then the amount should be correctly calculated 
    */
    function testInternalIssueTokensFormulaWrapper_worksGivenValidAmount(
        uint amount_,
        uint8 issuanceTokenDecimals_,
        uint8 collateralTokenDecimals_
    ) public {
        // Setup - Bound inputs to prevent overflow
        amount_ = bound(amount_, 1, type(uint64).max);
        issuanceTokenDecimals_ = uint8(bound(issuanceTokenDecimals_, 1, 18));
        collateralTokenDecimals_ = uint8(bound(collateralTokenDecimals_, 1, 18));

        FM_PC_Oracle_Redeeming_v1_Exposed newFundingManager =
        FM_PC_Oracle_Redeeming_v1_Exposed(
            _initializeFundingManagerWithDifferentTokenDecimals(
                issuanceTokenDecimals_, collateralTokenDecimals_
            )
        );

        // Set oracle address and price
        newFundingManager.setOracleAddress(address(oracle));
        uint oraclePrice = 10 ** collateralTokenDecimals_;
        oracle.setIssuancePrice(oraclePrice);

        // Scale amount to issuance decimals
        uint scaledAmount = amount_ * 10 ** issuanceTokenDecimals_;

        // Test
        uint actualIssueAmount =
            newFundingManager.exposed_issueTokensFormulaWrapper(scaledAmount);

        // Calculate expected amount manually following the formula:
        // 1. Calculate initial mint amount with oracle price
        uint initialMintAmount =
            (oraclePrice * scaledAmount) / 10 ** collateralTokenDecimals_;

        // 2. Convert to issuance token decimals
        uint expectedAmount = FM_BC_Tools._convertAmountToRequiredDecimal(
            initialMintAmount, collateralTokenDecimals_, issuanceTokenDecimals_
        );

        // Assert - Verify calculation matches expected
        assertEq(
            actualIssueAmount,
            expectedAmount,
            "Issue amount calculation incorrect"
        );
    }

    /* Test: Function _setIsDirectOperationsOnly()
        └── Given a valid value
            └── When the function exposed_setIsDirectOperationsOnly() is called
                └── Then the value should be set correctly
    */
    function testInternalSetIsDirectOperationsOnly_worksGivenValidValue(
        bool isDirect_
    ) public {
        // Test
        fundingManager.exposed_setIsDirectOperationsOnly(isDirect_);

        // Assert
        assertEq(
            fundingManager.getIsDirectOperationsOnly(),
            isDirect_,
            "IsDirect not set correctly"
        );
    }

    /* Test: Function _setMaxProjectBuyFee()
        └── Given a valid fee
            └── When the function exposed_setMaxProjectBuyFee() is called
                └── Then the fee should be set correctly
    */
    function testInternalSetMaxProjectBuyFee_worksGivenValidFee(uint fee_)
        public
    {
        // Setup
        fee_ = bound(fee_, fundingManager.getBuyFee(), BPS - 1); // has to be lower than 100%

        // Test
        fundingManager.exposed_setMaxProjectBuyFee(fee_);

        // Assert
        assertEq(
            fundingManager.getMaxProjectBuyFee(), fee_, "Fee not set correctly"
        );
    }

    /* Test: Function _setMaxProjectBuyFee()
        └── Given a fee above BPS
            └── When the function exposed_setMaxProjectBuyFee() is called
                └── Then it should revert
    */
    function testInternalSetMaxProjectBuyFee_revertGivenFeeAboveBPS(uint fee_)
        public
    {
        // Setup
        vm.assume(fee_ >= BPS);

        // Test
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__FM_PC_ExternalPrice_Redeeming_FeeExceedsMaximum(uint256,uint256)",
                fee_,
                BPS
            )
        );
        fundingManager.exposed_setMaxProjectBuyFee(fee_);
    }

    /* Test: Function _setMaxProjectSellFee()
        └── Given a valid fee
            └── When the function exposed_setMaxProjectSellFee() is called
                └── Then the fee should be set correctly
    */
    function testInternalSetMaxProjectSellFee_worksGivenValidFee(uint fee_)
        public
    {
        // Setup
        fee_ = bound(fee_, fundingManager.getSellFee(), BPS - 1); // has to be lower than 100%

        // Test
        fundingManager.exposed_setMaxProjectSellFee(fee_);

        // Assert
        assertEq(
            fundingManager.getMaxProjectSellFee(), fee_, "Fee not set correctly"
        );
    }

    /* Test: Function _setMaxProjectSellFee()
        └── Given a fee above BPS
            └── When the function exposed_setMaxProjectSellFee() is called
                └── Then it should revert
    */
    function testInternalSetMaxProjectSellFee_revertGivenFeeAboveBPS(uint fee_)
        public
    {
        // Setup
        vm.assume(fee_ >= BPS);

        // Test
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__FM_PC_ExternalPrice_Redeeming_FeeExceedsMaximum(uint256,uint256)",
                fee_,
                BPS
            )
        );
        fundingManager.exposed_setMaxProjectSellFee(fee_);
    }

    /* Test: Function _setBuyFee()
        └── Given a valid fee
            └── When the function exposed_setBuyFee() is called
                └── Then the fee should be set correctly
    */
    function testInternalSetBuyFee_worksGivenValidFee(uint fee_) public {
        // Setup
        fee_ = bound(fee_, 1, fundingManager.getMaxProjectBuyFee());

        // Test
        fundingManager.exposed_setBuyFee(fee_);

        // Assert
        assertEq(fundingManager.getBuyFee(), fee_, "Fee not set correctly");
    }

    /* Test: Function _setMaxProjectBuyFee()
        └── Given a fee above max project buy fee
            └── When the function exposed_setBuyFee() is called
                └── Then it should revert with Module__FM_PC_ExternalPrice_Redeeming_FeeExceedsMaximum
    */
    function testInternalSetBuyFee_revertGivenFeeAboveMaxProjectBuyFee()
        public
    {
        // Setup
        uint maxFee_ = 400;
        uint fee_ = maxFee_ + 1;

        fundingManager.exposed_setMaxProjectBuyFee(maxFee_);

        // Test
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__FM_PC_ExternalPrice_Redeeming_FeeExceedsMaximum(uint256,uint256)",
                fee_,
                maxFee_
            )
        );
        fundingManager.exposed_setBuyFee(fee_);
    }

    /* Test: Function _setSellFee()
        └── Given a valid fee
            └── When the function exposed_setSellFee() is called
                └── Then the fee should be set correctly
    */
    function testInternalSetSellFee_worksGivenValidFee(uint fee_) public {
        // Setup
        fee_ = bound(fee_, 1, fundingManager.getMaxProjectSellFee());

        // Test
        fundingManager.exposed_setSellFee(fee_);

        // Assert
        assertEq(fundingManager.getSellFee(), fee_, "Fee not set correctly");
    }

    /* Test: Function _setSellFee()
        └── Given a fee above max project sell fee
            └── When the function exposed_setSellFee() is called
                └── Then the fee should be set correctly
    */
    function testInternalSetSellFee_revertGivenFeeAboveMaxProjectSellFee(
        uint fee_
    ) public {
        // Setup
        vm.assume(fee_ > fundingManager.getMaxProjectSellFee());

        // Test
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__FM_PC_ExternalPrice_Redeeming_FeeExceedsMaximum(uint256,uint256)",
                fee_,
                fundingManager.getMaxProjectSellFee()
            )
        );
        fundingManager.exposed_setSellFee(fee_);
    }

    /* Test: Function _projectFeeCollected()
        └── Given a valid project fee amount
            └── When the function exposed_projectFeeCollected() is called
                └── Then it should emit ProjectCollateralFeeAdded event with correct amount
    */
    function testInternalProjectFeeCollected_worksGivenValidAmount(
        uint projectFeeAmount_
    ) public {
        // Setup - Bound inputs to prevent overflow
        projectFeeAmount_ = bound(projectFeeAmount_, 0, type(uint128).max);

        // Test - Expect event emission
        vm.expectEmit(true, true, true, true);
        emit IBondingCurveBase_v1.ProjectCollateralFeeAdded(projectFeeAmount_);

        // Execute
        fundingManager.exposed_projectFeeCollected(projectFeeAmount_);
    }

    /* Test: Function _createAndEmitOrder()
        └── Given valid parameters
            └── When the function exposed_createAndEmitOrder() is called
                └── Then it should emit OrderCreated event with correct parameters
                └── Then the open redemption amount should be set correctly
    */
    function testInternalCreateAndEmitOrder_worksGivenValidParameters(
        uint depositAmount_,
        uint collateralRedeemAmount_,
        uint projectSellFeeAmount_
    ) public {
        // Setup
        address receiver_ = makeAddr("receiver");

        // Setup - Bound inputs to prevent overflow
        depositAmount_ = bound(depositAmount_, 1, type(uint64).max);
        collateralRedeemAmount_ =
            bound(collateralRedeemAmount_, 1, type(uint64).max);
        projectSellFeeAmount_ =
            bound(projectSellFeeAmount_, 0, collateralRedeemAmount_);

        // Setup - Get current values
        uint exchangeRate_ = oracle.getPriceForRedemption();
        uint sellFee_ = fundingManager.getSellFee();

        // Test - Expect event emission
        vm.expectEmit(true, true, true, true, address(fundingManager));
        emit IFM_PC_Oracle_Redeeming_v1.RedemptionOrderCreated(
            address(fundingManager), // paymentClient_
            1, // orderId_ (first order)
            address(this), // seller_
            receiver_, // receiver_
            depositAmount_, // sellAmount_
            exchangeRate_, // exchangeRate_
            sellFee_, // feePercentage_
            projectSellFeeAmount_, // feeAmount_
            collateralRedeemAmount_, // finalRedemptionAmount_
            address(_token), // collateralToken_
            IFM_PC_Oracle_Redeeming_v1.RedemptionState.PENDING // state_
        );

        // Execute
        fundingManager.exposed_createAndEmitOrder(
            receiver_,
            depositAmount_,
            collateralRedeemAmount_,
            projectSellFeeAmount_
        );

        // Assert
        assertEq(
            fundingManager.getOpenRedemptionAmount(),
            collateralRedeemAmount_,
            "Open redemption amount not set correctly"
        );
    }

    /* Test: Function _sellOrder()
        └── Given the sell amount is 0
            └── When the function _sellOrder() is called
                └── Then it should revert
    */
    function testInternalSellOrder_revertGivenSellAmountIsZero() public {
        // Setup
        uint sellAmount_ = 0;
        uint minAmountOut_ = 1;
        address receiver_ = makeAddr("receiver");
        // Test
        vm.expectRevert(
            IBondingCurveBase_v1
                .Module__BondingCurveBase__InvalidDepositAmount
                .selector
        );
        fundingManager.exposed_sellOrder(receiver_, sellAmount_, minAmountOut_);
    }

    /* Test: Function _sellOrder()
        └── Given the sell amount bigger than 0
            └── And minAmountOut is 0
                └── When the function _sellOrder() is called
                    └── Then it should revert
    */
    function testInternalSellOrder_revertGivenSellMinAmountOutIsZero(
        uint sellAmount_
    ) public {
        // Setup
        vm.assume(sellAmount_ > 0);
        uint minAmountOut_ = 0;
        address receiver_ = makeAddr("receiver");
        // Test
        vm.expectRevert(
            IBondingCurveBase_v1
                .Module__BondingCurveBase__InvalidMinAmountOut
                .selector
        );
        fundingManager.exposed_sellOrder(receiver_, sellAmount_, minAmountOut_);
    }

    /* Test: Function _sellOrder()
        └── Given the sell amount bigger than 0
            └── And minAmountOut bigger than 0
                └── And redeem amount is lower than minAmountOut
                    └── When the function _sellOrder() is called
                        └── Then it should revert
    */
    function testInternalSellOrder_revertGivenRedeemAmountIsLowerThanMinAmountOut(
        uint sellAmount_
    ) public {
        // Setup
        address receiver_ = makeAddr("receiver");
        sellAmount_ = bound(sellAmount_, 1e18, type(uint64).max);
        _prepareBuyOrSellConditions(
            address(issuanceToken),
            sellAmount_,
            receiver_,
            address(fundingManager)
        );

        uint redemptionPrice_ = oracle.getPriceForRedemption();
        uint minAmountOut_ = fundingManager.calculateSaleReturn(sellAmount_);

        // Change redeem price to effect redeem amount calculation
        oracle.setRedemptionPrice(redemptionPrice_ / 10);

        // Test
        vm.prank(receiver_);
        vm.expectRevert(
            IBondingCurveBase_v1
                .Module__BondingCurveBase__InsufficientOutputAmount
                .selector
        );
        fundingManager.exposed_sellOrder(receiver_, sellAmount_, minAmountOut_);
    }

    /* Test: Function _sellOrder()
        └── Given valid input parameters
            └── And project fee is bigger than 0
                └── When the function _sellOrder() is called
                    └── Then is should burn the correct amount of issuance tokens
                        └── And it should emit the correct events
    */
    function testInternalSellOrder_worksGivenValidInputParametersAndProjectBiggerThanZero(
        uint sellAmount_,
        uint projectSellFee_
    ) public {
        // Setup
        address receiver_ = makeAddr("receiver");
        sellAmount_ = bound(sellAmount_, 1e18, type(uint64).max);
        // Set sell fee
        projectSellFee_ =
            bound(projectSellFee_, 1, fundingManager.getMaxProjectSellFee());
        fundingManager.exposed_setSellFee(projectSellFee_);
        // Prepare sell condition
        _prepareBuyOrSellConditions(
            address(issuanceToken),
            sellAmount_,
            receiver_,
            address(fundingManager)
        );
        // Calculate expected values
        uint minAmountOut_ = fundingManager.calculateSaleReturn(sellAmount_);
        uint expectedTotalCollateralTokenMovedOut_ =
            fundingManager.exposed_redeemTokensFormulaWrapper(sellAmount_);
        uint expectedProjectCollateralFeeAmount_ =
            expectedTotalCollateralTokenMovedOut_ * projectSellFee_ / BPS;
        uint expectedNetCollateralRedeemAmount_ =
        expectedTotalCollateralTokenMovedOut_
            - expectedProjectCollateralFeeAmount_;

        // Test
        vm.prank(receiver_);
        // Expect events
        vm.expectEmit(true, true, true, true, address(fundingManager));
        emit IBondingCurveBase_v1.ProjectCollateralFeeAdded(
            expectedProjectCollateralFeeAmount_
        );
        vm.expectEmit(true, true, true, true, address(fundingManager));
        emit IRedeemingBondingCurveBase_v1.TokensSold(
            receiver_,
            sellAmount_,
            expectedNetCollateralRedeemAmount_,
            receiver_
        );
        // Get return values
        (uint totalCollateralTokenMovedOut_, uint projectCollateralFeeAmount_) =
        fundingManager.exposed_sellOrder(receiver_, sellAmount_, minAmountOut_);

        // Assert
        assertEq(
            totalCollateralTokenMovedOut_,
            expectedTotalCollateralTokenMovedOut_,
            "Total collateral token moved out is not correct"
        );
        assertEq(
            projectCollateralFeeAmount_,
            expectedProjectCollateralFeeAmount_,
            "Project collateral fee amount is not correct"
        );
    }

    /* Test: Function _sellOrder()
        └── Given valid input parameters
            └── And project fee is 0
                └── When the function _sellOrder() is called
                    └── Then is should burn the correct amount of issuance tokens
                        └── And it should emit the correct events
    */
    function testInternalSellOrder_worksGivenValidInputParametersAndProjectIsZero(
        uint sellAmount_
    ) public {
        // Setup
        address receiver_ = makeAddr("receiver");
        sellAmount_ = bound(sellAmount_, 1e18, type(uint64).max);
        // Set sell fee to zero
        uint projectSellFee = 0;
        fundingManager.exposed_setSellFee(projectSellFee);
        // Prepare sell condition
        _prepareBuyOrSellConditions(
            address(issuanceToken),
            sellAmount_,
            receiver_,
            address(fundingManager)
        );
        // Get min amount out for function call
        uint minAmountOut_ = fundingManager.calculateSaleReturn(sellAmount_);

        // Calculate expected values
        uint expectedTotalCollateralTokenMovedOut_ =
            fundingManager.exposed_redeemTokensFormulaWrapper(sellAmount_);
        uint expectedProjectCollateralFeeAmount_ = 0;
        uint expectedNetCollateralRedeemAmount_ =
        expectedTotalCollateralTokenMovedOut_
            - expectedProjectCollateralFeeAmount_;

        // Test
        vm.prank(receiver_);
        // Expect events
        vm.expectEmit(true, true, true, true, address(fundingManager));
        emit IRedeemingBondingCurveBase_v1.TokensSold(
            receiver_,
            sellAmount_,
            expectedNetCollateralRedeemAmount_,
            receiver_
        );
        // Get return values
        (uint totalCollateralTokenMovedOut_, uint projectCollateralFeeAmount_) =
        fundingManager.exposed_sellOrder(receiver_, sellAmount_, minAmountOut_);

        // Assert
        assertEq(
            totalCollateralTokenMovedOut_,
            expectedTotalCollateralTokenMovedOut_,
            "Total collateral token moved out is not correct"
        );
        assertEq(
            projectCollateralFeeAmount_,
            expectedProjectCollateralFeeAmount_,
            "Project collateral fee amount is not correct"
        );
    }

    function testInternalEnsureTokenBalance_works(address token_) public {
        // This function body in the contract is left empty, as
        // the FM does not hold any collateral tokens. Adding this test
        // for the code coverage.

        // Test
        fundingManager.exposed_ensureTokenBalance(token_);
    }

    function testInternalHandleCollateralTokensAfterSell_works(
        address recipient_,
        uint amount_
    ) public {
        // This function body in the contract is left empty, as
        // the FM does not hold any collateral tokens. Adding this test
        // for the code coverage.

        // Test
        fundingManager.exposed_handleCollateralTokensAfterSell(
            recipient_, amount_
        );
    }

    // ============================================================================
    // Helper Functions

    function _setOpenRedemptionAmount(uint amount_) internal {
        uint openRedemptionAmount = fundingManager.getOpenRedemptionAmount();
        if (amount_ > openRedemptionAmount) {
            fundingManager.exposed_addToOpenRedemptionAmount(
                amount_ - openRedemptionAmount
            );
        } else {
            fundingManager.exposed_deductFromOpenRedemptionAmount(
                openRedemptionAmount - amount_
            );
        }
    }

    // Helper function that mints enough tokens to a buyer/seller and approves the funding manager to spend them
    function _prepareBuyOrSellConditions(
        address token_,
        uint amount_,
        address tokenReceiver_,
        address approvalReceiver_
    ) internal {
        deal(token_, tokenReceiver_, amount_);
        vm.prank(tokenReceiver_);
        IERC20(token_).approve(approvalReceiver_, amount_);
    }

    // Helper function that initializes the funding manager with different token decimals.
    // This helper function is needed to test the wrapper functions which make use of private
    // variables for the token decimals. As I can't override them, I create a new FM for fuzz testing.
    function _initializeFundingManagerWithDifferentTokenDecimals(
        uint8 issuanceTokenDecimals_,
        uint8 collateralTokenDecimals_
    ) internal returns (address fundingManager_) {
        // Create collateral token
        ERC20Decimals_Mock newCollateralToken = new ERC20Decimals_Mock(
            "Collateral Token", "CT", collateralTokenDecimals_
        );

        // Create issuance token
        ERC20Issuance_v1 newIssuanceToken = new ERC20Issuance_v1(
            NAME, SYMBOL, issuanceTokenDecimals_, MAX_SUPPLY, address(this)
        );
        bytes memory newConfigData = abi.encode(
            projectTreasury,
            address(newIssuanceToken),
            address(newCollateralToken),
            DEFAULT_BUY_FEE,
            DEFAULT_SELL_FEE,
            MAX_SELL_FEE,
            MAX_BUY_FEE,
            DIRECT_OPERATIONS_ONLY
        );
        // Setup funding manager
        address implementation =
            address(new FM_PC_Oracle_Redeeming_v1_Exposed());
        FM_PC_Oracle_Redeeming_v1_Exposed newFundingManager =
            FM_PC_Oracle_Redeeming_v1_Exposed(Clones.clone(implementation));

        // Initialize funding manager
        newFundingManager.init(_orchestrator, _METADATA, newConfigData);

        return address(newFundingManager);
    }
}
