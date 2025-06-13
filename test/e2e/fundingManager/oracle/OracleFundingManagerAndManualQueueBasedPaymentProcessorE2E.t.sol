// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import {Vm, VmSafe} from "forge-std/Vm.sol";

// SuT
import {AUT_Roles_v2} from "@aut/role/AUT_Roles_v2.sol";

// Internal Dependencies
import {
    E2ETest,
    IOrchestratorFactory_v1,
    IOrchestrator_v2
} from "test/e2e/E2ETest.sol";

// Import modules that are used in this E2E test
import {
    PP_Queue_ManualExecution_v2,
    IPP_Queue_ManualExecution_v2
} from "@pp/PP_Queue_ManualExecution_v2.sol";
import {
    FM_PC_Oracle_Redeeming_v2,
    IFM_PC_Oracle_Redeeming_v2
} from "src/modules/fundingManager/oracle/FM_PC_Oracle_Redeeming_v2.sol";

import {
    LM_Oracle_Permissioned_v2,
    ILM_Oracle_Permissioned_v2
} from "src/modules/logicModule/LM_Oracle_Permissioned_v2.sol";

import {ERC20Issuance_Blacklist_v1} from
    "@ex/token/ERC20Issuance_Blacklist_v1.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

import {InverterBeacon_v1} from "src/proxies/InverterBeacon_v1.sol";

import {ERC20Mock} from "@mocks/external/token/ERC20Mock.sol";

import {IERC20PaymentClientBase_v3} from
    "@lm/interfaces/IERC20PaymentClientBase_v3.sol";

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
        "RedemptionOrderCreated(address,uint256,address,address,uint256,uint256,uint256,uint256,uint256,uint256,address,uint8)"
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
    ERC20Mock collateralToken;
    ERC20Issuance_Blacklist_v1 issuanceToken;
    FM_PC_Oracle_Redeeming_v2 fundingManager;
    PP_Queue_ManualExecution_v2 paymentProcessor;
    AUT_Roles_v2 authorizer;
    LM_Oracle_Permissioned_v2 permissionedOracle;
    IOrchestrator_v2 orchestrator;

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
        uint protocolFeeAmount_;
        uint finalRedemptionAmount_;
        address collateralToken_;
        IFM_PC_Oracle_Redeeming_v2.RedemptionState state_;
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
        issuanceToken =
            new ERC20Issuance_Blacklist_v1(NAME, SYMBOL, DECIMALS, MAX_SUPPLY);
        issuanceToken.setMinter(address(this), true);

        // Create collateral token with 6 decimals to simulate USDC
        collateralToken = new ERC20Mock(
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
        // Orchestrator_v2 Initialization
        //--------------------------------------------------------------------------
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
        IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        orchestrator =
            _create_E2E_Orchestrator(workflowConfig, moduleConfigurations);

        authorizer = AUT_Roles_v2(address(orchestrator.authorizer()));

        // Get funding manager
        fundingManager =
            FM_PC_Oracle_Redeeming_v2(address(orchestrator.fundingManager()));

        // Get payment processor
        paymentProcessor = PP_Queue_ManualExecution_v2(
            address(orchestrator.paymentProcessor())
        );

        // Get permissioned oracle
        address[] memory modulesList = orchestrator.listModules();
        for (uint i; i < modulesList.length; ++i) {
            if (
                ERC165Upgradeable(modulesList[i]).supportsInterface(
                    type(ILM_Oracle_Permissioned_v2).interfaceId
                )
            ) {
                permissionedOracle = LM_Oracle_Permissioned_v2(modulesList[i]);
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
        // Set roles and their admin roles in the system

        {
            //Here we create the different roles and set their initial members
            // We remember that the role id is just counting up from 1
            // 0 is the default admin role and 1 is the public role
            // The create Role function can only be called by permissioned addresses
            // In this case only the default admin can call it

            string memory roleName;
            bytes32 roleAdmin;
            address[] memory roleMembers;

            //PRICE_SETTER_ROLE_ADMIN
            roleName = "PRICE_SETTER_ROLE_ADMIN";
            roleAdmin = bytes32(0); // The default admin
            roleMembers = new address[](1);
            roleMembers[0] = priceSetterRoleAdmin;

            authorizer.createRole(roleName, roleAdmin, roleMembers);

            //PRICE_SETTER_ROLE
            roleName = "PRICE_SETTER_ROLE";
            roleAdmin = bytes32(uint(2)); // The newly created role Price Setter admin
            roleMembers = new address[](0); // No initial members as we want for the admins to set them

            authorizer.createRole(roleName, roleAdmin, roleMembers);

            //QUEUE_OPERATOR_ROLE_ADMIN
            roleName = "QUEUE_OPERATOR_ROLE_ADMIN";
            roleAdmin = bytes32(0); // The default admin
            roleMembers = new address[](1);
            roleMembers[0] = queueOperatorRoleAdmin;

            authorizer.createRole(roleName, roleAdmin, roleMembers);

            //QUEUE_OPERATOR_ROLE
            roleName = "QUEUE_OPERATOR_ROLE";
            roleAdmin = bytes32(uint(4)); // The newly created role Queue Operator admin
            roleMembers = new address[](0); // No initial members as we want for the admins to set them

            authorizer.createRole(roleName, roleAdmin, roleMembers);

            //WHITELIST_ROLE_ADMIN
            roleName = "WHITELIST_ROLE_ADMIN";
            roleAdmin = bytes32(0); // The default admin
            roleMembers = new address[](1);
            roleMembers[0] = whitelistRoleAdmin;

            authorizer.createRole(roleName, roleAdmin, roleMembers);

            //WHITELIST_ROLE
            roleName = "WHITELIST_ROLE";
            roleAdmin = bytes32(uint(6)); // The newly created role Whitelist admin
            roleMembers = new address[](0); // No initial members as we want for the admins to set them

            authorizer.createRole(roleName, roleAdmin, roleMembers);

            //QUEUE_EXECUTOR_ROLE_ADMIN
            roleName = "QUEUE_EXECUTOR_ROLE_ADMIN";
            roleAdmin = bytes32(0); // The default admin
            roleMembers = new address[](1);
            roleMembers[0] = queueExecutorRoleAdmin;

            authorizer.createRole(roleName, roleAdmin, roleMembers);

            //QUEUE_EXECUTOR_ROLE
            roleName = "QUEUE_EXECUTOR_ROLE";
            roleAdmin = bytes32(uint(8)); // The newly created role Queue Executor admin
            roleMembers = new address[](0); // No initial members as we want for the admins to set them

            authorizer.createRole(roleName, roleAdmin, roleMembers);
        }

        //--------------------------------------------------------------------------
        // Add Access Permissions to the roles
        {
            // The addAccessPermission function can only be called by permissioned addresses
            // In this case only the default admin can call it

            address target;
            bytes4 selector;
            bytes32 roleId;

            //PRICE_SETTER_ROLE - setIssuancePrice
            target = address(permissionedOracle);
            selector = permissionedOracle.setIssuancePrice.selector;
            roleId = bytes32(uint(3));
            authorizer.addAccessPermission(target, selector, roleId);

            //PRICE_SETTER_ROLE - setRedemptionPrice
            selector = permissionedOracle.setRedemptionPrice.selector;
            authorizer.addAccessPermission(target, selector, roleId);

            //PRICE_SETTER_ROLE - setIssuanceAndRedemptionPrice
            selector = permissionedOracle.setIssuanceAndRedemptionPrice.selector;
            authorizer.addAccessPermission(target, selector, roleId);

            //QUEUE_OPERATOR_ROLE - processPayments
            target = address(paymentProcessor);
            selector =
                paymentProcessor.claimPreviouslyUnclaimableToTreasury.selector;
            roleId = bytes32(uint(5));
            authorizer.addAccessPermission(target, selector, roleId);

            //QUEUE_OPERATOR_ROLE - cancelPaymentOrderThroughQueueId
            selector =
                paymentProcessor.cancelPaymentOrderThroughQueueId.selector;
            authorizer.addAccessPermission(target, selector, roleId);

            //WHITELIST_ROLE - buy
            target = address(fundingManager);
            selector = fundingManager.buy.selector;
            authorizer.addAccessPermission(target, selector, bytes32(uint(7)));

            //WHITELIST_ROLE - buyFor
            selector = fundingManager.buyFor.selector;
            authorizer.addAccessPermission(target, selector, bytes32(uint(7)));

            //WHITELIST_ROLE - sell
            selector = fundingManager.sell.selector;
            authorizer.addAccessPermission(target, selector, bytes32(uint(7)));

            //WHITELIST_ROLE - sellTo
            selector = fundingManager.sellTo.selector;
            authorizer.addAccessPermission(target, selector, bytes32(uint(7)));

            //QUEUE_EXECUTOR_ROLE - executeRedemptionQueue
            target = address(fundingManager);
            selector = fundingManager.executeRedemptionQueue.selector;
            authorizer.addAccessPermission(target, selector, bytes32(uint(9)));
        }
        //--------------------------------------------------------------------------
        // Assign roles through admins

        // Price Setter
        vm.prank(priceSetterRoleAdmin);
        authorizer.grantRole(bytes32(uint(3)), priceSetter);

        // Queue Operator
        vm.prank(queueOperatorRoleAdmin);
        authorizer.grantRole(bytes32(uint(5)), queueOperator);

        // Whitelist
        vm.prank(whitelistRoleAdmin);
        authorizer.grantRole(bytes32(uint(7)), whitelistedUser);

        // Queue Executor
        vm.prank(queueExecutorRoleAdmin);
        authorizer.grantRole(bytes32(uint(9)), queueExecutor);

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
        IPP_Queue_ManualExecution_v2.QueuedOrder memory order =
            paymentProcessor.getOrder(orderId, fundingManager);
        IERC20PaymentClientBase_v3.PaymentOrder memory paymentOrder =
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
                    uint protocolFeeAmount,
                    uint finalRedemptionAmount,
                    address collateralToken_,
                    IFM_PC_Oracle_Redeeming_v2.RedemptionState state
                ) = abi.decode(
                    entry.data,
                    (
                        address,
                        uint,
                        uint,
                        uint,
                        uint,
                        uint,
                        uint,
                        address,
                        IFM_PC_Oracle_Redeeming_v2.RedemptionState
                    )
                );

                // Assign decoded values to struct
                data.seller_ = seller;
                data.sellAmount_ = sellAmount;
                data.exchangeRate_ = exchangeRate;
                data.feePercentage_ = feePercentage;
                data.feeAmount_ = feeAmount;
                data.protocolFeeAmount_ = protocolFeeAmount;
                data.finalRedemptionAmount_ = finalRedemptionAmount;
                data.collateralToken_ = collateralToken_;
                data.state_ = state;

                return data;
            }
        }
        revert("RedemptionOrderCreated event not found");
    }
}
