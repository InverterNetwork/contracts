// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Internal imports
import {IOraclePrice_v1} from "@lm/interfaces/IOraclePrice_v1.sol";
import {IFM_PC_Oracle_Redeeming_v1} from
    "@fm/oracle/interfaces/IFM_PC_Oracle_Redeeming_v1.sol";
import {IModule_v2} from "src/modules/base/IModule_v2.sol";
import {OZErrors} from "@testUtilities/OZErrors.sol";
import {
    BondingCurveBase_v1,
    IBondingCurveBase_v2
} from "@fm/bondingCurve/abstracts/BondingCurveBase_v1.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {
    RedeemingBondingCurveBase_v2,
    IRedeemingBondingCurveBase_v2
} from "@fm/bondingCurve/abstracts/RedeemingBondingCurveBase_v2.sol";
import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";
import {FM_BC_Tools} from "@fm/bondingCurve/FM_BC_Tools.sol";

// External imports
import {Clones} from "@oz/proxy/Clones.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Tests and Mocks
import {ModuleTest} from "@unitTest/modules/ModuleTest.sol";
import {ERC20PaymentClientBaseV2Mock} from
    "@mocks/modules/paymentClient/ERC20PaymentClientBaseV2Mock.sol";
import {ERC20Mock} from "@mocks/external/token/ERC20Mock.sol";
import {OraclePrice_Mock} from "@mocks/modules/logicModule/OraclePrice_Mock.sol";
import {InvalidOraclePrice_Mock} from
    "@mocks/modules/logicModule/InvalidOraclePrice_Mock.sol";
import {PP_Queue_ManualExecution_v1_Mock} from
    "@mocks/modules/paymentProcessor/PP_Queue_ManualExecution_v1_Mock.sol";

// System under testing (SUT)
import {FM_PC_Oracle_Redeeming_v1_Exposed} from
    "@mocks/modules/fundingManager/oracle/FM_PC_Oracle_Redeeming_v1_Exposed.sol";

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

    // processPayments function selector
    bytes4 internal constant PROCESS_PAYMENTS_FUNCTION_SELECTOR =
        bytes4(keccak256(bytes("processPayments(address)")));
    // sellOrder function selector
    bytes4 internal constant SELL_ORDER_FUNCTION_SELECTOR =
        bytes4(keccak256(bytes("_sellOrder(address,uint,uint)")));

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
        issuanceToken = new ERC20Issuance_v1(NAME, SYMBOL, DECIMALS, MAX_SUPPLY);
        issuanceToken.setMinter(address(this), true);

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

        // Turn on all adresses are permissioned to call all functions
        _authorizer.setAllAuthorized(true);

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
    function testSupportsInterface() public override(ModuleTest) {
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

    /* Test: Function calculateSaleReturn()
        └── Given a valid sell amount
            └── When the function calculateSaleReturn() is called
                └── Then it should return the correct sale return
    */
    function testCalculateSaleReturn_worksGivenValidSellAmount(
        uint depositAmount_,
        uint protocolIssuanceFee_,
        uint projectCollateralFee_,
        uint protocolCollateralFee_
    ) public {
        // Setup
        depositAmount_ = bound(depositAmount_, 1e18, type(uint128).max);
        protocolIssuanceFee_ =
            bound(protocolIssuanceFee_, 1, feeManager.maxFee());
        projectCollateralFee_ = bound(
            projectCollateralFee_, 1, fundingManager.getMaxProjectSellFee()
        );
        protocolCollateralFee_ =
            bound(protocolCollateralFee_, 1, feeManager.maxFee());

        // Set fee percentages
        fundingManager.exposed_setSellFee(projectCollateralFee_);
        feeManager.setCollateralWorkflowFee(
            address(_orchestrator),
            address(_paymentProcessor),
            PROCESS_PAYMENTS_FUNCTION_SELECTOR,
            true,
            protocolCollateralFee_
        );
        feeManager.setIssuanceWorkflowFee(
            address(_orchestrator),
            address(fundingManager),
            bytes4(keccak256(bytes("_sellOrder(address,uint,uint)"))),
            true,
            protocolIssuanceFee_
        );
        // Calculate return values
        uint issuanceFeeAmount = depositAmount_ * protocolIssuanceFee_ / BPS;
        uint netIssuanceDepositAmount = depositAmount_ - issuanceFeeAmount;
        uint redeemAmount = fundingManager.exposed_redeemTokensFormulaWrapper(
            netIssuanceDepositAmount
        );
        uint protocolCollateralFeeAmount =
            redeemAmount * protocolCollateralFee_ / BPS;
        uint projectCollateralFeeAmount =
            redeemAmount * projectCollateralFee_ / BPS;
        uint expectedNetCollateralRedeemAmount = redeemAmount
            - protocolCollateralFeeAmount - projectCollateralFeeAmount;

        // Test
        uint functionReturnValue =
            fundingManager.calculateSaleReturn(depositAmount_);
        // Assert
        assertEq(
            functionReturnValue,
            expectedNetCollateralRedeemAmount,
            "Net collateral redeem amount is not correct"
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
        uint protocolSellFeeAmount1_ = 1e17;
        fundingManager.exposed_createAndEmitOrder(
            receiver1_,
            depositAmount1_,
            collateralRedeemAmount1_,
            projectSellFeeAmount1_,
            protocolSellFeeAmount1_
        );

        // Test - Amount should be updated after first order
        assertEq(
            fundingManager.getOpenRedemptionAmount(),
            collateralRedeemAmount1_ + protocolSellFeeAmount1_,
            "Open redemption amount should match first collateral amount"
        );

        // Setup - Create second order
        address receiver2_ = makeAddr("receiver2");
        uint depositAmount2_ = 2e18;
        uint collateralRedeemAmount2_ = 3e18;
        uint projectSellFeeAmount2_ = 2e17;
        uint protocolSellFeeAmount2_ = 2e17;
        fundingManager.exposed_createAndEmitOrder(
            receiver2_,
            depositAmount2_,
            collateralRedeemAmount2_,
            projectSellFeeAmount2_,
            protocolSellFeeAmount2_
        );

        // Test - Amount should be updated after second order
        assertEq(
            fundingManager.getOpenRedemptionAmount(),
            collateralRedeemAmount1_ + collateralRedeemAmount2_
                + protocolSellFeeAmount1_ + protocolSellFeeAmount2_,
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
        uint protocolSellFeeAmount1_ = 1e17;

        fundingManager.exposed_createAndEmitOrder(
            receiver1_,
            depositAmount1_,
            collateralRedeemAmount1_,
            projectSellFeeAmount1_,
            protocolSellFeeAmount1_
        );

        // Test - First order should have ID 1
        assertEq(fundingManager.getOrderId(), 1, "First order should have ID 1");

        // Setup - Create second order
        address receiver2_ = makeAddr("receiver2");
        uint depositAmount2_ = 2e18;
        uint collateralRedeemAmount2_ = 3e18;
        uint projectSellFeeAmount2_ = 2e17;
        uint protocolSellFeeAmount2_ = 2e17;

        fundingManager.exposed_createAndEmitOrder(
            receiver2_,
            depositAmount2_,
            collateralRedeemAmount2_,
            projectSellFeeAmount2_,
            protocolSellFeeAmount2_
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

    /* Test: Function buyFor()
        └── Given Third Party Operations (TPO) disabled
            └── When buyFor() is called
                └── Then it should revert (Modifier in place test)
    */
    function testBuyFor_revertGivenTPODisabled() public {
        // Test - Should revert as TPO is disabled
        vm.expectRevert(
            IFM_PC_Oracle_Redeeming_v1
                .Module__FM_PC_ExternalPrice_Redeeming_ThirdPartyOperationsDisabled
                .selector
        );
        fundingManager.buyFor(address(0), 0, 0);
    }

    /* Test: Function sellTo()
        └── Given Third Party Operations (TPO) disabled
            └── When sellTo() is called
                └── Then it should revert (Modifier in place test)
    */
    function testSellTo_revertGivenTPODisabled() public {
        // Test - Should revert as TPO is disabled
        vm.expectRevert(
            IFM_PC_Oracle_Redeeming_v1
                .Module__FM_PC_ExternalPrice_Redeeming_ThirdPartyOperationsDisabled
                .selector
        );
        fundingManager.sellTo(address(0), 0, 0);
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
        vm.expectRevert(IModule_v2.Module__OnlyCallableByPaymentClient.selector);
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
        uint protocolSellFeeAmount_ = 1e17;
        fundingManager.exposed_createAndEmitOrder(
            receiver_,
            depositAmount_,
            collateralRedeemAmount_,
            projectSellFeeAmount_,
            protocolSellFeeAmount_
        );

        // Setup - Mock payment processor call
        vm.startPrank(address(_orchestrator.paymentProcessor()));

        // Test - Call amountPaid
        fundingManager.amountPaid(
            address(_token), collateralRedeemAmount_ + protocolSellFeeAmount_
        );

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
        ├── Given: Caller is not permissioned
        |   └── When the function setProjectTreasury() is called
        |       └── Then it should revert (modifier in place test)
        ├── Given: Caller is permissioned
        ├── And: the project treasury is a valid address
            └── When the function setProjectTreasury() is called
                └── Then it should set the project treasury correctly
    */
    function testSetProjectTreasury_modifierInPlace() public {
        // permissioned

        // Turn off all adresses are permissioned to call all functions
        _authorizer.setAllAuthorized(false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v2.Module__CallerNotPermissioned.selector
            )
        );
        vm.prank(address(0xB0B));
        fundingManager.setProjectTreasury(address(0));
    }

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
        ├── Given: Caller is not permissioned
        |   └── When the function setOracleAddress() is called
        |       └── Then it should revert (modifier in place test)
        ├── Given: Caller is permissioned
        ├── And: the oracle supports the IOraclePrice_v1 interface
        |    └── When the function setOracleAddress() is called
        |        └── Then it should set the oracle address correctly
        ├── Given: Caller is permissioned
        ├── And: the oracle does not support the IOraclePrice_v1 interface
            └── When the function setOracleAddress() is called
                └── Then it should revert
    */

    function testSetOracleAddress_modifierInPlace() public {
        // permissioned

        // Turn off all adresses are permissioned to call all functions
        _authorizer.setAllAuthorized(false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v2.Module__CallerNotPermissioned.selector
            )
        );
        vm.prank(address(0xB0B));
        fundingManager.setOracleAddress(address(0));
    }

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
        ├── Given: Caller is not permissioned
        |   └── When the function setIsDirectOperationsOnly() is called
        |       └── Then it should revert (modifier in place test)
        ├── Given: Caller is permissioned
        └── And: Called with a valid value
            └── When the function exposed_setIsDirectOperationsOnly() is called
                └── Then the value should be set correctly
    */

    function testSetIsDirectOperationsOnly_modifierInPlace() public {
        // permissioned

        // Turn off all adresses are permissioned to call all functions
        _authorizer.setAllAuthorized(false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v2.Module__CallerNotPermissioned.selector
            )
        );
        vm.prank(address(0xB0B));
        fundingManager.setIsDirectOperationsOnly(false);
    }

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
        └── Given caller is not permissioned
            └── When executeRedemptionQueue() is called
                └── Then it should revert (modifier in place test)
    */
    function testExecuteRedemptionQueue_modifierInPlace() public {
        // permissioned

        // Turn off all adresses are permissioned to call all functions
        _authorizer.setAllAuthorized(false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v2.Module__CallerNotPermissioned.selector
            )
        );
        vm.prank(address(0xB0B));
        fundingManager.executeRedemptionQueue();
    }

    /* Test: Function executeRedemptionQueue()
        ├── Given caller is permissioned
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
                    .selector,
                bytes("")
            )
        );
        fundingManager.executeRedemptionQueue();
    }

    /* Test: Function executeRedemptionQueue()
        ├── Given caller is permissioned
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
        uint protocolSellFeeAmount_ = 1e17;
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
            projectSellFeeAmount_,
            protocolSellFeeAmount_
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

    /* Test: Function _processCollateralTokensForBuyOperation()
        └── When the function _processCollateralTokensForBuyOperation() is called
            └── Then it should transfer the amount of tokens to the project treasury
    */
    function testInternalProcessCollateralTokensForBuyOperation_worksGivenMintedTokens(
        uint amount_
    ) public {
        // Setup
        vm.assume(amount_ > 0);

        deal(address(_token), address(fundingManager), amount_);

        // Assert
        assertEq(
            _token.balanceOf(address(fundingManager)),
            amount_,
            "Funding manager should have the right amount of tokens"
        );
        assertEq(
            _token.balanceOf(projectTreasury),
            0,
            "Project treasury should not have any tokens"
        );

        // Test
        fundingManager.exposed_processCollateralTokensForBuyOperation(amount_);

        // Assert
        assertEq(
            _token.balanceOf(address(fundingManager)),
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
            "New Issuance Token", "NIT", decimals_, MAX_SUPPLY
        );
        newIssuanceToken.setMinter(address(this), true);

        // Assert
        assertEq(
            fundingManager.getIssuanceToken(),
            address(issuanceToken),
            "Issuance token not set correctly during initialization"
        );

        // Test
        vm.expectEmit(true, true, true, true);
        emit IBondingCurveBase_v2.IssuanceTokenSet(
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
        emit IBondingCurveBase_v2.ProjectCollateralFeeAdded(projectFeeAmount_);

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
        uint projectSellFeeAmount_,
        uint protocolSellFeeAmount_
    ) public {
        // Setup
        address receiver_ = makeAddr("receiver");

        // Setup - Bound inputs to prevent overflow
        depositAmount_ = bound(depositAmount_, 1, type(uint64).max);
        collateralRedeemAmount_ =
            bound(collateralRedeemAmount_, 1, type(uint64).max);
        projectSellFeeAmount_ =
            bound(projectSellFeeAmount_, 0, collateralRedeemAmount_);
        protocolSellFeeAmount_ =
            bound(protocolSellFeeAmount_, 0, collateralRedeemAmount_);

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
            protocolSellFeeAmount_, // protocolFeeAmount_
            collateralRedeemAmount_, // finalRedemptionAmount_
            address(_token), // collateralToken_
            IFM_PC_Oracle_Redeeming_v1.RedemptionState.PENDING // state_
        );

        // Execute
        fundingManager.exposed_createAndEmitOrder(
            receiver_,
            depositAmount_,
            collateralRedeemAmount_,
            projectSellFeeAmount_,
            protocolSellFeeAmount_
        );

        // Assert
        assertEq(
            fundingManager.getOpenRedemptionAmount(),
            collateralRedeemAmount_ + protocolSellFeeAmount_,
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
            IBondingCurveBase_v2
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
            IBondingCurveBase_v2
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
            IBondingCurveBase_v2
                .Module__BondingCurveBase__InsufficientOutputAmount
                .selector
        );
        fundingManager.exposed_sellOrder(receiver_, sellAmount_, minAmountOut_);
    }

    /* Test: Function _sellOrder()
        └── Given valid input parameters
            └── And project fee is bigger than 0
            └── And protocol fee is bigger than 0
                └── When the function _sellOrder() is called
                    └── Then is should burn the correct amount of issuance tokens
                        └── And it should emit the correct events
    */
    function testInternalSellOrder_worksGivenValidInputParametersAndProjectBiggerThanZero(
        uint sellAmount_,
        uint projectSellFee_,
        uint protocolSellFee_
    ) public {
        // Setup
        address receiver_ = makeAddr("receiver");
        sellAmount_ = bound(sellAmount_, 1e18, type(uint64).max);
        // Set sell fee
        projectSellFee_ =
            bound(projectSellFee_, 1, fundingManager.getMaxProjectSellFee());
        protocolSellFee_ = bound(protocolSellFee_, 1, feeManager.maxFee());
        fundingManager.exposed_setSellFee(projectSellFee_);
        // Prepare sell condition
        _prepareBuyOrSellConditions(
            address(issuanceToken),
            sellAmount_,
            receiver_,
            address(fundingManager)
        );
        feeManager.setCollateralWorkflowFee(
            address(_orchestrator),
            address(_paymentProcessor),
            PROCESS_PAYMENTS_FUNCTION_SELECTOR,
            true,
            protocolSellFee_
        );
        // Calculate expected values

        // Minimum amount out for sell call
        uint minAmountOut_ = fundingManager.calculateSaleReturn(sellAmount_);

        // Calculate expected values
        (
            uint expectedTotalCollateralTokenMovedOut_,
            uint expectedProjectCollateralFeeAmount_,
            , /*expectedProtocolCollateralFeeAmount_*/
            uint expectedNetCollateralRedeemAmount_
        ) = _getExpectedReturnValuesSellOrder(
            sellAmount_, projectSellFee_, protocolSellFee_
        );
        // Test
        vm.prank(receiver_);
        // Expect events
        vm.expectEmit(true, true, true, true, address(fundingManager));
        emit IBondingCurveBase_v2.ProjectCollateralFeeAdded(
            expectedProjectCollateralFeeAmount_
        );
        vm.expectEmit(true, true, true, true, address(fundingManager));
        emit IRedeemingBondingCurveBase_v2.TokensSold(
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
                └── And protocol fee is 0
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
        uint protocolSellFee = 0;
        fundingManager.exposed_setSellFee(projectSellFee);
        // Prepare sell condition
        _prepareBuyOrSellConditions(
            address(issuanceToken),
            sellAmount_,
            receiver_,
            address(fundingManager)
        );
        feeManager.setCollateralWorkflowFee(
            address(_orchestrator),
            address(_paymentProcessor),
            PROCESS_PAYMENTS_FUNCTION_SELECTOR,
            true,
            protocolSellFee
        );
        // Get min amount out for function call
        uint minAmountOut_ = fundingManager.calculateSaleReturn(sellAmount_);

        // Calculate expected values
        (
            uint expectedTotalCollateralTokenMovedOut_,
            uint expectedProjectCollateralFeeAmount_,
            , /*expectedProtocolCollateralFeeAmount_*/
            uint expectedNetCollateralRedeemAmount_
        ) = _getExpectedReturnValuesSellOrder(
            sellAmount_, projectSellFee, protocolSellFee
        );

        // Test
        vm.prank(receiver_);
        // Expect events
        vm.expectEmit(true, true, true, true, address(fundingManager));
        emit IRedeemingBondingCurveBase_v2.TokensSold(
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

    /* Test: Function _getFunctionFeesAndTreasuryAddresses()
        └── When the function _getFunctionFeesAndTreasuryAddresses() is called
            └── Then it should return the correct collateral and issuance fee percentage and treasury addresses
    */
    function testInternalGetCollateralSellFeePercentage_works(
        uint issuanceFee_,
        uint collateralFee_,
        address treasury_
    ) public {
        issuanceFee_ = bound(issuanceFee_, 0, feeManager.maxFee());
        collateralFee_ = bound(collateralFee_, 0, feeManager.maxFee());
        vm.assume(treasury_ != address(0));
        // Setup
        // Set collateral fee for processPayments function
        feeManager.setCollateralWorkflowFee(
            address(_orchestrator),
            address(_paymentProcessor),
            PROCESS_PAYMENTS_FUNCTION_SELECTOR,
            true,
            collateralFee_
        );
        // Set issuance fee for sellOrder function
        feeManager.setIssuanceWorkflowFee(
            address(_orchestrator),
            address(fundingManager),
            SELL_ORDER_FUNCTION_SELECTOR,
            true,
            issuanceFee_
        );
        feeManager.setWorkflowTreasury(address(_orchestrator), treasury_);
        // Test
        (
            address collateralTreasury_,
            address issuanceTreasury_,
            uint collateralFeePercentage_,
            uint issuanceFeePercentage_
        ) = fundingManager.exposed_getFunctionFeesAndTreasuryAddresses(
            SELL_ORDER_FUNCTION_SELECTOR
        );

        // Assert
        assertEq(
            collateralFeePercentage_,
            collateralFee_,
            "Collateral sell fee percentage is not correct"
        );
        assertEq(
            collateralTreasury_, treasury_, "Collateral treasury is not correct"
        );
        assertEq(
            issuanceTreasury_, treasury_, "Issuance treasury is not correct"
        );
        assertEq(
            issuanceFeePercentage_,
            issuanceFee_,
            "Issuance fee percentage is not correct"
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
        ERC20Mock newCollateralToken =
            new ERC20Mock("Collateral Token", "CT", collateralTokenDecimals_);

        // Create issuance token
        ERC20Issuance_v1 newIssuanceToken = new ERC20Issuance_v1(
            NAME, SYMBOL, issuanceTokenDecimals_, MAX_SUPPLY
        );
        newIssuanceToken.setMinter(address(this), true);
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

    function _getExpectedReturnValuesSellOrder(
        uint sellAmount_,
        uint projectSellFee_,
        uint protocolSellFee_
    )
        internal
        view
        returns (
            uint expectedTotalCollateralTokenMovedOut_,
            uint expectedProjectCollateralFeeAmount_,
            uint expectedProtocolCollateralFeeAmount_,
            uint expectedNetCollateralRedeemAmount_
        )
    {
        // Total collateral token "moving out", i.e. total amount of collateral tokens
        // calculated based on the sell amount - issuance token sell fee
        expectedTotalCollateralTokenMovedOut_ =
            fundingManager.exposed_redeemTokensFormulaWrapper(sellAmount_);
        // Expected project collateral fee amount
        expectedProjectCollateralFeeAmount_ =
            expectedTotalCollateralTokenMovedOut_ * projectSellFee_ / BPS;
        // Expected protocol collateral fee amount
        expectedProtocolCollateralFeeAmount_ =
            expectedTotalCollateralTokenMovedOut_ * protocolSellFee_ / BPS;
        // Expected net collateral redeem amount, i.e. amount recipent gets
        expectedNetCollateralRedeemAmount_ =
        expectedTotalCollateralTokenMovedOut_
            - expectedProjectCollateralFeeAmount_
            - expectedProtocolCollateralFeeAmount_;
    }
}
