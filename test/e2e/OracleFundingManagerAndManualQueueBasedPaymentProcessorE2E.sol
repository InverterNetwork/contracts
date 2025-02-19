// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import {Vm, VmSafe} from "forge-std/Vm.sol";

// SuT
import {AUT_Roles_v1} from "@aut/role/AUT_Roles_v1.sol";

// Internal Dependencies
import {
    E2ETest,
    IOrchestratorFactory_v1,
    IOrchestrator_v1
} from "test/e2e/E2ETest.sol";

// Import modules that are used in this E2E test
import {
    PP_Queue_ManualExecution_v1,
    IPP_Queue_ManualExecution_v1
} from "@pp/PP_Queue_ManualExecution_v1.sol";
import {
    FM_PC_Oracle_Redeeming_v1,
    IFM_PC_Oracle_Redeeming_v1
} from "src/modules/fundingManager/oracle/FM_PC_Oracle_Redeeming_v1.sol";

import {
    LM_Oracle_Permissioned_v1,
    ILM_Oracle_Permissioned_v1
} from "src/modules/logicModule/LM_Oracle_Permissioned_v1.sol";

import {ERC20Issuance_Blacklist_v1} from
    "@ex/token/ERC20Issuance_Blacklist_v1.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

import {InverterBeacon_v1} from "src/proxies/InverterBeacon_v1.sol";

import {ERC20Decimals_Mock} from "test/utils/mocks/ERC20Decimals_Mock.sol";

import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";

contract OracleFundingManagerAndManualQueueBasedPaymentProcessorE2E is
    E2ETest
{
    IOrchestratorFactory_v1.ModuleConfig[] moduleConfigurations;

    // E2E Test Variables
    // -------------------------------------------------------------------------
    // Constants
    uint constant BPS = 10_000; // Basis points (100%)

    // Issuance token constants
    string internal constant NAME = "Issuance Token";
    string internal constant SYMBOL = "ISS-TOKEN";
    uint8 internal constant DECIMALS = 18;
    uint internal constant MAX_SUPPLY = type(uint).max;

    // Collateral token constants
    string internal constant COLLATERAL_NAME = "Mock USDC";
    string internal constant COLLATERAL_SYMBOL = "M-USDC";
    uint8 internal constant COLLATERAL_DECIMALS = 6;

    // FM Fee settings
    uint constant DEFAULT_BUY_FEE = 0; // 0%
    uint constant DEFAULT_SELL_FEE = 20; // 0.2%
    uint constant MAX_BUY_FEE = 0; // 0%
    uint constant MAX_SELL_FEE = 100; // 1%
    bool constant DIRECT_OPERATIONS_ONLY = false;

    // Roles in the workflow
    bytes32 private constant WHITELIST_ROLE_ADMIN = "WHITELIST_ROLE_ADMIN";
    bytes32 private constant WHITELIST_ROLE = "WHITELIST_ROLE";

    bytes32 private constant QUEUE_EXECUTOR_ROLE_ADMIN =
        "QUEUE_EXECUTOR_ROLE_ADMIN";
    bytes32 private constant QUEUE_EXECUTOR_ROLE = "QUEUE_EXECUTOR_ROLE";

    bytes32 private constant QUEUE_OPERATOR_ROLE_ADMIN =
        "QUEUE_OPERATOR_ROLE_ADMIN";
    bytes32 private constant QUEUE_OPERATOR_ROLE = "QUEUE_OPERATOR_ROLE";

    bytes32 private constant PRICE_SETTER_ROLE_ADMIN = "PRICE_SETTER_ROLE_ADMIN";
    bytes32 private constant PRICE_SETTER_ROLE = "PRICE_SETTER_ROLE";

    // Event signatures
    bytes32 private constant REDEMPTION_ORDER_CREATED_EVENT_SIGNATURE =
    keccak256(
        "RedemptionOrderCreated(address,uint256,address,address,uint256,uint256,uint256,uint256,uint256,address,uint8)"
    );
    bytes32 private constant PAYMENT_ORDER_QUEUED_EVENT_SIGNATURE = keccak256(
        "PaymentOrderQueued(uint256,address,address,address,uint256,uint256)"
    );
    // -------------------------------------------------------------------------
    // Test variables

    // Addresses for roles
    address whitelistRoleAdmin = makeAddr("whitelistRoleAdmin");
    address whitelistedUser = makeAddr("whitelistedUser");
    address queueOperatorRoleAdmin = makeAddr("queueOperatorRoleAdmin");
    address queueOperator = makeAddr("queueOperator");
    address queueExecutorRoleAdmin = makeAddr("queueExecutorRoleAdmin");
    address queueExecutor = makeAddr("queueExecutor");
    address priceSetterRoleAdmin = makeAddr("priceSetterRoleAdmin");
    address priceSetter = makeAddr("priceSetter");
    address blacklistManager = makeAddr("blacklistManager");
    // Treasuries
    address cancelledOrdersTreasury = makeAddr("cancelledOrdersTreasury");
    address failedOrdersTreasury = makeAddr("failedOrdersTreasury");
    address projectTreasury = makeAddr("projectTreasury");

    // Contracts
    ERC20Decimals_Mock collateralToken;
    ERC20Issuance_Blacklist_v1 issuanceToken;
    FM_PC_Oracle_Redeeming_v1 fundingManager;
    PP_Queue_ManualExecution_v1 paymentProcessor;
    AUT_Roles_v1 authorizer;
    LM_Oracle_Permissioned_v1 permissionedOracle;
    IOrchestrator_v1 orchestrator;

    // Define struct to hold all event parameters
    struct RedemptionOrderCreatedEventData {
        address paymentClient_;
        uint orderId_;
        address seller_;
        address receiver_;
        uint sellAmount_;
        uint exchangeRate_;
        uint feePercentage_;
        uint feeAmount_;
        uint finalRedemptionAmount_;
        address collateralToken_;
        IFM_PC_Oracle_Redeeming_v1.RedemptionState state_;
    }

    function setUp() public override {
        // Setup common E2E framework
        super.setUp();

        // Set Up individual Modules the E2E test is going to use and store their configurations:
        // NOTE: It's important to store the module configurations in order, since _create_E2E_Orchestrator() will copy from the array.
        // The order should be:
        //      moduleConfigurations[0]  => FundingManager
        //      moduleConfigurations[1]  => Authorizer
        //      moduleConfigurations[2]  => PaymentProcessor
        //      moduleConfigurations[3:] => Additional Logic Modules

        // First create issuance token
        issuanceToken = new ERC20Issuance_Blacklist_v1(
            NAME, SYMBOL, DECIMALS, MAX_SUPPLY, address(this), address(this)
        );

        // Create collateral token with 6 decimals to simulate USDC
        collateralToken = new ERC20Decimals_Mock(
            COLLATERAL_NAME, COLLATERAL_SYMBOL, COLLATERAL_DECIMALS
        );

        setUpPermissionedOracle();
        // FundingManager
        setUpPermissionedOracleRedeemingFundingManager();
        bytes memory configData = abi.encode(
            projectTreasury, // treasury
            address(issuanceToken), // issuance token
            address(collateralToken), // collateral token
            DEFAULT_BUY_FEE, // buy fee
            DEFAULT_SELL_FEE, // sell fee
            MAX_SELL_FEE, // max sell fee
            MAX_BUY_FEE, // max buy fee
            DIRECT_OPERATIONS_ONLY // direct operations only flag
        );
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                fundingManagerMetadata, configData
            )
        );
        // Authorizer
        setUpRoleAuthorizer();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                roleAuthorizerMetadata, abi.encode(address(this))
            )
        );

        // PaymentProcessor
        setUpManualQueueBasedPaymentProcessor();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                manualQueueBasedPaymentProcessorMetadata,
                abi.encode(cancelledOrdersTreasury, failedOrdersTreasury)
            )
        );

        // Additional Logic Modules
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                oracleMetadata, abi.encode(address(collateralToken))
            )
        );
    }

    function _init() internal {
        //--------------------------------------------------------------------------
        // Orchestrator_v1 Initialization
        //--------------------------------------------------------------------------
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
        IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        orchestrator =
            _create_E2E_Orchestrator(workflowConfig, moduleConfigurations);

        // Get funding manager
        fundingManager =
            FM_PC_Oracle_Redeeming_v1(address(orchestrator.fundingManager()));

        // Get payment processor
        paymentProcessor = PP_Queue_ManualExecution_v1(
            address(orchestrator.paymentProcessor())
        );

        // Get permissioned oracle
        address[] memory modulesList = orchestrator.listModules();
        for (uint i; i < modulesList.length; ++i) {
            if (
                ERC165Upgradeable(modulesList[i]).supportsInterface(
                    type(ILM_Oracle_Permissioned_v1).interfaceId
                )
            ) {
                permissionedOracle = LM_Oracle_Permissioned_v1(modulesList[i]);
                break;
            }
        }
        // Setup workflow
        fundingManager.setOracleAddress(address(permissionedOracle));
        issuanceToken.setMinter(address(fundingManager), true);
        fundingManager.openBuy();
        fundingManager.openSell();

        _setRoles();
    }

    function _setRoles() internal {
        //--------------------------------------------------------------------------
        // Set role admins roles in the system

        bytes32 roleId;
        bytes32 adminRoleId;

        // Set role admin for price setter role
        roleId = orchestrator.authorizer().generateRoleId(
            address(permissionedOracle), permissionedOracle.getPriceSetterRole()
        );
        adminRoleId = orchestrator.authorizer().generateRoleId(
            address(permissionedOracle),
            permissionedOracle.getPriceSetterRoleAdmin()
        );
        orchestrator.authorizer().transferAdminRole(roleId, adminRoleId);

        // Set role admin for queue operator role
        roleId = orchestrator.authorizer().generateRoleId(
            address(paymentProcessor), paymentProcessor.getQueueOperatorRole()
        );
        adminRoleId = orchestrator.authorizer().generateRoleId(
            address(paymentProcessor),
            paymentProcessor.getQueueOperatorRoleAdmin()
        );
        orchestrator.authorizer().transferAdminRole(roleId, adminRoleId);

        // Set role admin for whitelist role
        roleId = orchestrator.authorizer().generateRoleId(
            address(fundingManager), fundingManager.getWhitelistRole()
        );
        adminRoleId = orchestrator.authorizer().generateRoleId(
            address(fundingManager), fundingManager.getWhitelistRoleAdmin()
        );
        orchestrator.authorizer().transferAdminRole(roleId, adminRoleId);

        // Set role admin for queue executor role
        roleId = orchestrator.authorizer().generateRoleId(
            address(fundingManager), fundingManager.getQueueExecutorRole()
        );
        adminRoleId = orchestrator.authorizer().generateRoleId(
            address(fundingManager), fundingManager.getQueueExecutorRoleAdmin()
        );
        orchestrator.authorizer().transferAdminRole(roleId, adminRoleId);

        //--------------------------------------------------------------------------
        // Assign role admin roles

        // Assign price setter role admin
        permissionedOracle.grantModuleRole(
            permissionedOracle.getPriceSetterRoleAdmin(), priceSetterRoleAdmin
        );

        // Assign queue operator role admin
        paymentProcessor.grantModuleRole(
            paymentProcessor.getQueueOperatorRoleAdmin(), queueOperatorRoleAdmin
        );

        // Assign whitelist role admin
        fundingManager.grantModuleRole(
            fundingManager.getWhitelistRoleAdmin(), whitelistRoleAdmin
        );

        // Assign queue executor role admin
        fundingManager.grantModuleRole(
            fundingManager.getQueueExecutorRoleAdmin(), queueExecutorRoleAdmin
        );

        //--------------------------------------------------------------------------
        // Assign roles through admins

        // Assign price setter role
        vm.startPrank(priceSetterRoleAdmin);
        permissionedOracle.grantModuleRole(
            permissionedOracle.getPriceSetterRole(), priceSetter
        );
        vm.stopPrank();

        // Assign queue operator role
        vm.startPrank(queueOperatorRoleAdmin);
        paymentProcessor.grantModuleRole(
            paymentProcessor.getQueueOperatorRole(), queueOperator
        );
        vm.stopPrank();

        // Assign whitelist role
        vm.startPrank(whitelistRoleAdmin);
        fundingManager.grantModuleRole(
            fundingManager.getWhitelistRole(), whitelistedUser
        );
        vm.stopPrank();

        // Assign queue executor role
        vm.startPrank(queueExecutorRoleAdmin);
        fundingManager.grantModuleRole(
            fundingManager.getQueueExecutorRole(), queueExecutor
        );
        vm.stopPrank();

        //--------------------------------------------------------------------------
        // Assign other roles in the system

        issuanceToken.setBlacklistManager(blacklistManager, true);
    }

    function test_e2e_QueueBaseFundingManagerAndPaymentProcessorLifecycle()
        public
    {
        _init();
        //--------------------------------------------------------------------------
        // Buy Tokens
        //--------------------------------------------------------------------------

        // Setup oracle price
        uint issuanceAndRedemptionPrice = 1e6;
        vm.prank(priceSetter);
        permissionedOracle.setIssuanceAndRedemptionPrice(
            issuanceAndRedemptionPrice, issuanceAndRedemptionPrice
        );

        // Prepare buy conditions
        uint buyAmount = 1000e6;
        _prepareBuyConditions(whitelistedUser, buyAmount);

        //--------------------------------------------------------------------------
        // Pre-buy assertions

        assertEq(
            collateralToken.balanceOf(whitelistedUser),
            buyAmount,
            "user should have the right amount of collateral"
        );
        assertEq(
            collateralToken.balanceOf(projectTreasury),
            0,
            "project treasury should have 0 collateral"
        );

        // Verify user has no issuance tokens before buy
        assertEq(
            issuanceToken.balanceOf(whitelistedUser),
            0,
            "Expected issuance tokens should be 0"
        );

        // Get expected issuance tokens in return
        uint expectedIssuedTokens =
            fundingManager.calculatePurchaseReturn(buyAmount);

        // Execute buy
        vm.startPrank(whitelistedUser);
        fundingManager.buy(buyAmount, expectedIssuedTokens);
        vm.stopPrank();

        //--------------------------------------------------------------------------
        // Post-buy assertions

        // Verify user received issuance tokens
        assertEq(
            issuanceToken.balanceOf(whitelistedUser),
            expectedIssuedTokens,
            "User should have received the right amount of issuance tokens"
        );

        //--------------------------------------------------------------------------
        // Sell Tokens
        //--------------------------------------------------------------------------

        uint sellAmount = expectedIssuedTokens;

        // Get expected issuance tokens in return
        uint expectedRedeemTokens =
            fundingManager.calculateSaleReturn(sellAmount);

        // Record logs before the transaction to assert the data from the event
        vm.recordLogs();

        // Execute sell
        vm.startPrank(whitelistedUser);
        fundingManager.sell(sellAmount, expectedRedeemTokens);
        vm.stopPrank();

        //--------------------------------------------------------------------------
        // Post-sell assertions

        // Verify user has no issuance tokens after sell, as the order is queued
        assertEq(
            issuanceToken.balanceOf(whitelistedUser),
            0,
            "User should have 0 issuance tokens after sell"
        );
        // Verify project treasury has all the collateral still from the buy
        assertEq(
            collateralToken.balanceOf(projectTreasury),
            buyAmount,
            "project treasury should all the collateral from the buy amount"
        );

        // Get recorded logs
        VmSafe.Log[] memory entries = vm.getRecordedLogs();
        // Get data from event
        RedemptionOrderCreatedEventData memory data = _decodeEvent(entries);
        // Get order id from event
        uint orderId = data.orderId_;

        // Get order from payment processor
        IPP_Queue_ManualExecution_v1.QueuedOrder memory order =
            paymentProcessor.getOrder(orderId, fundingManager);
        IERC20PaymentClientBase_v2.PaymentOrder memory paymentOrder =
            order.order_;

        // verify data from the payment order == data from the event,
        // which means that the payment order created in the FM was successfully queued
        assertEq(order.orderId_, data.orderId_, "Order id should be 1");
        assertEq(order.client_, data.paymentClient_, "Should be the same");
        assertEq(paymentOrder.recipient, data.receiver_, "Should be the same");
        assertEq(
            paymentOrder.amount,
            data.finalRedemptionAmount_,
            "Should be the same"
        );
        assertEq(
            paymentOrder.paymentToken,
            address(collateralToken),
            "Should be the same"
        );

        //--------------------------------------------------------------------------
        // Deposit Reserve
        //--------------------------------------------------------------------------

        uint openRedemptionAmount = fundingManager.getOpenRedemptionAmount();
        //--------------------------------------------------------------------------
        // Pre-deposit assertions
        assertEq(
            openRedemptionAmount,
            paymentOrder.amount,
            "Open redemption amount should be equal to the payment amount of the 1 order that got created"
        );
        // Approve collateral token to funding manager
        vm.prank(projectTreasury);
        collateralToken.approve(address(fundingManager), openRedemptionAmount);

        // Verify allowance is set correctly
        assertEq(
            collateralToken.allowance(projectTreasury, address(fundingManager)),
            openRedemptionAmount,
            "Allowance should be equal to the open redemption amount"
        );

        // Deposit reserve back into the funding manager
        vm.prank(projectTreasury);
        fundingManager.depositReserve(openRedemptionAmount);

        //--------------------------------------------------------------------------
        // Post-deposit assertions

        // Verify project treasury has all the collateral minus fee
        // back into the funding manager
        assertEq(
            collateralToken.balanceOf(projectTreasury),
            buyAmount - openRedemptionAmount,
            "project treasury should have only the sell fee in collateral"
        );

        // Verify funding manager has all the reserve back, deposited through
        // the depositReserve function
        assertEq(
            collateralToken.balanceOf(address(fundingManager)),
            openRedemptionAmount,
            "funding manager should have the reserve amount needed to execute the queue"
        );

        //--------------------------------------------------------------------------
        // Execute Queue
        //--------------------------------------------------------------------------

        //--------------------------------------------------------------------------
        // Pre-execute assertions

        // Verify user has no collateral tokens before queue execution
        assertEq(
            collateralToken.balanceOf(whitelistedUser),
            0,
            "User should have 0 collateral tokens before queue execution"
        );

        vm.startPrank(queueExecutor);
        fundingManager.executeRedemptionQueue();

        //--------------------------------------------------------------------------
        // Post-execute assertions

        // Verify user has the right amount of collateral tokens after queue execution
        assertEq(
            collateralToken.balanceOf(whitelistedUser),
            paymentOrder.amount,
            "User should have the right amount of collateral tokens after queue execution"
        );
    }

    function _prepareBuyConditions(address buyer, uint buyAmount) internal {
        // Mint tokens to buyer
        collateralToken.mint(buyer, buyAmount);
        // Approve tokens to funding manager
        vm.startPrank(buyer);
        collateralToken.approve(address(fundingManager), buyAmount);
        vm.stopPrank();
    }

    function _decodeEvent(VmSafe.Log[] memory entries)
        internal
        pure
        returns (RedemptionOrderCreatedEventData memory data)
    {
        // Loop through all logs to find the RedemptionOrderCreated event
        for (uint i = 0; i < entries.length; i++) {
            VmSafe.Log memory entry = entries[i];

            // Check if the event signature matches RedemptionOrderCreated
            if (entry.topics[0] == REDEMPTION_ORDER_CREATED_EVENT_SIGNATURE) {
                // Decode indexed parameters from topics
                data.paymentClient_ = address(uint160(uint(entry.topics[1])));
                data.orderId_ = uint(entry.topics[2]);
                data.receiver_ = address(uint160(uint(entry.topics[3])));

                // Use tuple decoding to reduce stack usage
                (
                    address seller,
                    uint sellAmount,
                    uint exchangeRate,
                    uint feePercentage,
                    uint feeAmount,
                    uint finalRedemptionAmount,
                    address collateralToken_,
                    IFM_PC_Oracle_Redeeming_v1.RedemptionState state
                ) = abi.decode(
                    entry.data,
                    (
                        address,
                        uint,
                        uint,
                        uint,
                        uint,
                        uint,
                        address,
                        IFM_PC_Oracle_Redeeming_v1.RedemptionState
                    )
                );

                // Assign decoded values to struct
                data.seller_ = seller;
                data.sellAmount_ = sellAmount;
                data.exchangeRate_ = exchangeRate;
                data.feePercentage_ = feePercentage;
                data.feeAmount_ = feeAmount;
                data.finalRedemptionAmount_ = finalRedemptionAmount;
                data.collateralToken_ = collateralToken_;
                data.state_ = state;

                return data;
            }
        }
        revert("RedemptionOrderCreated event not found");
    }
}
