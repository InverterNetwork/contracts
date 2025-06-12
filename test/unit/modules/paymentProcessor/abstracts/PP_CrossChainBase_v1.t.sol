// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Internal imports
import {PP_CrossChainBase_v1} from "@pp/abstracts/PP_CrossChainBase_v1.sol";
import {IPP_CrossChainBase_v1} from "@pp/interfaces/IPP_CrossChainBase_v1.sol";
import {IPaymentProcessor_v2} from "@pp/IPaymentProcessor_v2.sol";
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";

// External imports
import {Clones} from "@oz/proxy/Clones.sol";
import {OZErrors} from "@testUtilities/OZErrors.sol";

// Tests and Mocks
import {ModuleTest} from "@unitTest/modules/ModuleTest.sol";
import {ERC20PaymentClientBaseV2Mock} from
    "@mocks/modules/paymentClient/ERC20PaymentClientBaseV2Mock.sol";
import {FundingManagerV1Mock} from
    "@mocks/modules/fundingManager/FundingManagerV1Mock.sol";
import {AuthorizerV1Mock} from "@mocks/modules/authorizer/AuthorizerV1Mock.sol";
import {PaymentProcessorV1Mock} from
    "@mocks/modules/paymentProcessor/PaymentProcessorV1Mock.sol";
import {ERC20Mock} from "@mocks/external/token/ERC20Mock.sol";

// SuT
import {PP_CrossChainBase_v1_Exposed} from
    "@mocks/modules/paymentProcessor/abstracts/PP_CrossChainBase_v1_Exposed.sol";

contract PP_CrossChainBase_v1_Test is ModuleTest {
    // ========================================================================
    // State

    PP_CrossChainBase_v1_Exposed public crossChainPaymentProcessorBase;
    ERC20PaymentClientBaseV2Mock public paymentClient;

    // ========================================================================
    // Setup
    function setUp() public {
        // Deploy and init the SUT
        address impl = address(new PP_CrossChainBase_v1_Exposed());
        crossChainPaymentProcessorBase =
            PP_CrossChainBase_v1_Exposed(Clones.clone(impl));

        // Deploy and setup the payment client for testing SUT
        impl = address(new ERC20PaymentClientBaseV2Mock());
        paymentClient = ERC20PaymentClientBaseV2Mock(Clones.clone(impl));

        // Setup the mock workflow contracts and token
        _setUpOrchestrator(paymentClient);

        // Initialize the SUT
        crossChainPaymentProcessorBase.init(
            _orchestrator, _METADATA, abi.encode("")
        );

        // Initialize payment client
        paymentClient.init(_orchestrator, _METADATA, bytes(""));
        paymentClient.setOrchestrator(_orchestrator);
        paymentClient.setToken(_token);
        paymentClient.setIsAuthorized(
            address(crossChainPaymentProcessorBase), true
        );

        // Set the testing contract to be authorized in authorizer mock
        _authorizer.setIsAuthorized(address(this), true);
    }

    // ========================================================================
    // Test Init & SupportsInterface

    function testInit() public override(ModuleTest) {
        assertEq(
            address(crossChainPaymentProcessorBase.orchestrator()),
            address(_orchestrator),
            "Orchestrator address mismatch"
        );
    }

    function testSupportsInterface() public {
        assertTrue(
            crossChainPaymentProcessorBase.supportsInterface(
                type(IPP_CrossChainBase_v1).interfaceId
            )
        );
        assertTrue(
            crossChainPaymentProcessorBase.supportsInterface(
                type(IPaymentProcessor_v2).interfaceId
            )
        );
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        crossChainPaymentProcessorBase.init(_orchestrator, _METADATA, bytes(""));
    }

    // ========================================================================
    // Test External (public + external)

    /* Test: Function getBridgeDataByPaymentId()
        └── When the function getBridgeDataByPaymentId() is called 
            └── Then it should return the correct bridge data
    */
    function testGetBridgeDataByPaymentId_worksGivenBridgeDataReturned(
        uint paymentId_,
        bytes memory bridgeData_
    ) public {
        // Set the bridge data
        crossChainPaymentProcessorBase.helper_setBridgeData(
            bridgeData_, paymentId_
        );

        // Test function call
        bytes memory bridgeData =
            crossChainPaymentProcessorBase.getBridgeDataByPaymentId(paymentId_);

        // Post-assert
        assertEq(bridgeData, bridgeData_, "Bridge data should be equal");
    }

    /* Test: Function getPaymentId()
        └── When the function getPaymentId() is called
            └── Then it should return the correct paymentId
    */
    function testGetPaymentId_worksGivenPaymentIdReturned(uint paymentId_)
        public
    {
        // Set the paymentId
        crossChainPaymentProcessorBase.helper_setPaymentId(paymentId_);

        // Test function call
        uint paymentId = crossChainPaymentProcessorBase.getPaymentId();

        // Post-assert
        assertEq(paymentId, paymentId_, "PaymentId should be equal");
    }

    /* Test: Function unclaimable()
        └── When the function unclaimable() is called
            └── Then it should return the correct unclaimable amount
    */
    function testUnclaimable_worksGivenUnclaimableAmountReturned(
        address client_,
        address token_,
        address paymentReceiver_,
        uint unclaimableAmount_
    ) public {
        // Set the unclaimable amount
        crossChainPaymentProcessorBase.helper_setUnclaimableAmount(
            client_, token_, paymentReceiver_, unclaimableAmount_
        );

        // Test function call
        uint unclaimableAmount = crossChainPaymentProcessorBase.unclaimable(
            client_, token_, paymentReceiver_
        );

        // Post-assert
        assertEq(
            unclaimableAmount,
            unclaimableAmount_,
            "Unclaimable amount should be equal"
        );
    }

    /* Test: Function claimPreviouslyUnclaimable()
        └── Given receiver has no unclaimable amount
            └── When the function claimPreviouslyUnclaimable() is called
                └── Then it should revert
    */
    function testClaimPreviouslyUnclaimable_revertsGivenReceiverHasNoUnclaimableAmount(
        address client_,
        address token_,
        address paymentReceiver_
    ) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPaymentProcessor_v2
                    .Module__PaymentProcessor__NothingToClaim
                    .selector,
                client_,
                address(this)
            )
        );
        crossChainPaymentProcessorBase.claimPreviouslyUnclaimable(
            client_, token_, paymentReceiver_
        );
    }

    /* Test: Function claimPreviouslyUnclaimable()
        └── Given receiver has unclaimable amount
            └── When the function claimPreviouslyUnclaimable() is called
                └── Then it should claim the unclaimable amount
    */
    function testClaimPreviouslyUnclaimable_worksGivenUnclaimableAmountIsClaimed(
        address client_,
        address paymentReceiver_,
        uint unclaimableAmount_
    ) public {
        // Validate test inputs
        vm.assume(unclaimableAmount_ > 0);
        helper_ensureNoAddressCollision(paymentReceiver_);

        // Mint tokens to payment processor
        _token.mint(address(crossChainPaymentProcessorBase), unclaimableAmount_);

        // Set unclaimable amounts for recipient
        crossChainPaymentProcessorBase.helper_setUnclaimableAmount(
            client_, address(_token), paymentReceiver_, unclaimableAmount_
        );

        // Pre-assert
        assertEq(
            _token.balanceOf(paymentReceiver_),
            0,
            "Payment receiver should have 0 balance"
        );
        assertEq(
            _token.balanceOf(address(crossChainPaymentProcessorBase)),
            unclaimableAmount_,
            "Payment processor should hold unclaimed amount"
        );
        uint preClaimUnclaimableAmount = crossChainPaymentProcessorBase
            .unclaimable(client_, address(_token), paymentReceiver_);
        assertEq(
            preClaimUnclaimableAmount,
            unclaimableAmount_,
            "Unclaimable amount should be set for the test"
        );

        // Test function call
        vm.prank(paymentReceiver_);
        crossChainPaymentProcessorBase.claimPreviouslyUnclaimable(
            client_, address(_token), paymentReceiver_
        );

        // Post-assert
        assertEq(
            _token.balanceOf(paymentReceiver_),
            unclaimableAmount_,
            "Payment receiver should have the unclaimable amount"
        );
        assertEq(
            _token.balanceOf(address(crossChainPaymentProcessorBase)),
            0,
            "Payment processor should have no unclaimed amount"
        );
        uint postUnclaimableAmount = crossChainPaymentProcessorBase.unclaimable(
            client_, address(_token), paymentReceiver_
        );
        assertEq(postUnclaimableAmount, 0, "Unclaimable amount should be 0");
    }

    /* Test: Function cancelRunningPayments()
        ├── Given msg.sender is a module
        └──  And msg.sender is not a payment client (modifier in place test)
            └── When the function cancelRunningPayments() is called
                └── Then it should revert
    */
    function testCancelRunningPayments_revertsGivenMsgSenderIsNotPaymentClientModule(
    ) public {
        // Test 1:
        // Set address to registered module that is not a payment client
        address addr = address(_fundingManager);

        // Test function call
        vm.prank(addr);
        vm.expectRevert(
            IPaymentProcessor_v2
                .Module__PaymentProcessor__CannotCallOnOtherClientsOrders
                .selector
        );
        crossChainPaymentProcessorBase.cancelRunningPayments(paymentClient);

        // Test 2:
        // Set address to registered module that is not a payment client
        addr = address(_paymentProcessor);

        // Test function call
        vm.prank(addr);
        vm.expectRevert(
            IPaymentProcessor_v2
                .Module__PaymentProcessor__CannotCallOnOtherClientsOrders
                .selector
        );
        crossChainPaymentProcessorBase.cancelRunningPayments(paymentClient);

        // Test 3:
        // Set address to registered module that is not a payment client
        addr = address(_authorizer);

        // Test function call
        vm.prank(addr);
        vm.expectRevert(
            IPaymentProcessor_v2
                .Module__PaymentProcessor__CannotCallOnOtherClientsOrders
                .selector
        );
        crossChainPaymentProcessorBase.cancelRunningPayments(paymentClient);
    }

    /* Test: Function cancelRunningPayments()
        ├── Given msg.sender is a module
        └── And msg.sender is not registered in the orchestrator (modifier in place test)
            └── When the function cancelRunningPayments() is called
                └── Then it should revert
    */
    function testCancelRunningPayments_revertsGivenMsgSenderIsNotRegisteredInOrchestrator(
    ) public {
        // Test 3: Deploy module which is not registered and call cancelRunningPayments()
        address fundingManager = address(new FundingManagerV1Mock());

        // Test function call
        vm.prank(fundingManager);
        vm.expectRevert(
            IPaymentProcessor_v2
                .Module__PaymentProcessor__OnlyCallableByModule
                .selector
        );
        crossChainPaymentProcessorBase.cancelRunningPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );

        // Test 3: Deploy module which is not registered and call cancelRunningPayments()
        address paymentProcessor = address(new PaymentProcessorV1Mock());

        // Test function call
        vm.prank(paymentProcessor);
        vm.expectRevert(
            IPaymentProcessor_v2
                .Module__PaymentProcessor__OnlyCallableByModule
                .selector
        );
        crossChainPaymentProcessorBase.cancelRunningPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );

        // Test 3: Deploy module which is not registered and call cancelRunningPayments()
        address authorizer = address(new AuthorizerV1Mock());

        // Test function call
        vm.prank(authorizer);
        vm.expectRevert(
            IPaymentProcessor_v2
                .Module__PaymentProcessor__OnlyCallableByModule
                .selector
        );
        crossChainPaymentProcessorBase.cancelRunningPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );
    }

    /* Test: Function cancelRunningPayments()
        └── Given msg.sender is not a module
            └── When the function cancelRunningPayments() is called
                └── Then it should revert
    */
    function testCancelRunningPayments_revertsGivenMsgSenderIsNotModule(
        address addr_
    ) public {
        // Validate test inputs
        helper_ensureNoAddressCollision(addr_);

        // Test function call
        vm.prank(addr_);
        vm.expectRevert(
            IPaymentProcessor_v2
                .Module__PaymentProcessor__OnlyCallableByModule
                .selector
        );
        crossChainPaymentProcessorBase.cancelRunningPayments(paymentClient);
    }

    /* Test: Function cancelRunningPayments()
        ├── Given msg.sender is a payment client
        └── And the module is registered in the orchestrator
            └── When the function cancelRunningPayments() is called
                └── Then it should revert
    */

    function testCancelRunningPayments_reverts() public {
        // Test function call
        vm.prank(address(paymentClient));
        vm.expectRevert("Not implemented");
        crossChainPaymentProcessorBase.cancelRunningPayments(paymentClient);
    }

    // ========================================================================
    // Test Internal

    /* Test: Function _executeBridgeTransfer() (implementation test done in downstream contract)
        └── When _executeBridgeTransfer is called
            └── Then it should return an empty bytes array
    */
    function testInternalExecuteBridgeTransfer_succeedsGivenImplemented()
        public
    {
        // Create mock payment order
        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: address(0),
            paymentToken: address(0),
            amount: 0 ether,
            originChainId: 0,
            targetChainId: 0,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        // Test function call: Should not revert
        crossChainPaymentProcessorBase.exposed_executeBridgeTransfer(order);
    }

    /* Test: Function _claimPreviouslyUnclaimable()
        └── Given the msg.sender has an unclaimable amount to claim
            └── When the internal function _claimPreviouslyUnclaimable() is called
                ├── Then the unclaimable amount should be claimed
                ├── And the unclaimable amount should be deleted from the storage
                └── And an event should be emitted
    */
    function testInternalClaimPreviouslyUnclaimable_worksGivenUnclaimableAmountIsClaimed(
        address client_,
        address paymentReceiver_,
        uint unclaimableAmount_
    ) public {
        // Validate test inputs
        vm.assume(unclaimableAmount_ > 0);
        helper_ensureNoAddressCollision(paymentReceiver_);
        helper_ensureNoAddressCollision(client_);

        // Mint tokens to payment processor
        _token.mint(address(crossChainPaymentProcessorBase), unclaimableAmount_);

        // Set unclaimable amounts for recipient
        crossChainPaymentProcessorBase.helper_setUnclaimableAmount(
            client_, address(_token), paymentReceiver_, unclaimableAmount_
        );

        // Pre-assert
        assertEq(
            _token.balanceOf(paymentReceiver_),
            0,
            "Payment receiver should have 0 balance"
        );
        assertEq(
            _token.balanceOf(address(crossChainPaymentProcessorBase)),
            unclaimableAmount_,
            "Payment processor should hold unclaimed amount"
        );
        uint preClaimUnclaimableAmount = crossChainPaymentProcessorBase
            .unclaimable(client_, address(_token), paymentReceiver_);
        assertEq(
            preClaimUnclaimableAmount,
            unclaimableAmount_,
            "Unclaimable amount should be set for the test"
        );

        // Test function call
        vm.prank(paymentReceiver_);
        crossChainPaymentProcessorBase.exposed_claimPreviouslyUnclaimable(
            client_, address(_token), paymentReceiver_
        );

        // Post-assert
        assertEq(
            _token.balanceOf(paymentReceiver_),
            unclaimableAmount_,
            "Payment receiver should have the unclaimable amount"
        );
        assertEq(
            _token.balanceOf(address(crossChainPaymentProcessorBase)),
            0,
            "Payment processor should have no unclaimed amount"
        );
        uint postUnclaimableAmount = crossChainPaymentProcessorBase.unclaimable(
            client_, address(_token), paymentReceiver_
        );
        assertEq(postUnclaimableAmount, 0, "Unclaimable amount should be 0");
    }

    /* Test: Function _validPaymentReceiver()
        └── Given address is address zero
            └── When the function _validPaymentReceiver() is called
                └── Then it should return false
    */
    function testInternalValiPaymentReceiver_worksGivenReturnsFalseIfAddressIsZero(
    ) public {
        // Set address to zero
        address addr = address(0);

        // Test function call
        bool isValid =
            crossChainPaymentProcessorBase.exposed_validPaymentReceiver(addr);

        // Post-assert
        assertEq(isValid, false, "Address should be invalid");
    }

    /* Test: Function _validPaymentReceiver()
        └── Given address is msg.sender
            └── When the function _validPaymentReceiver() is called
                └── Then it should return false
    */
    function testInternalValiPaymentReceiver_worksGivenReturnsFalseIfAddressIsMsgSender(
    ) public {
        // Set address to this contract (msg.sender for function call)
        address addr = address(this);

        // Test function call
        bool isValid =
            crossChainPaymentProcessorBase.exposed_validPaymentReceiver(addr);

        // Post-assert
        assertEq(isValid, false, "Address should be invalid");
    }

    /* Test: Function _validPaymentReceiver()
        └── Given address is the payment processor
            └── When the function _validPaymentReceiver() is called
                └── Then it should return false
    */
    function testInternalValiPaymentReceiver_worksGivenReturnsFalseIfAddressIsPaymentProcessor(
    ) public {
        // Set address to payment processor
        address addr = address(crossChainPaymentProcessorBase);

        // Test function call
        bool isValid =
            crossChainPaymentProcessorBase.exposed_validPaymentReceiver(addr);

        // Post-assert
        assertEq(isValid, false, "Address should be invalid");
    }

    /* Test: Function _validPaymentReceiver()
        └── Given address is the Orchestrator
            └── When the function _validPaymentReceiver() is called
                └── Then it should return false
    */
    function testInternalValiPaymentReceiver_worksGivenReturnsFalseIfAddressIsOrchestrator(
    ) public {
        // Set address to orchestrator
        address addr = address(_orchestrator);

        // Test function call
        bool isValid =
            crossChainPaymentProcessorBase.exposed_validPaymentReceiver(addr);

        // Post-assert
        assertEq(isValid, false, "Address should be invalid");
    }

    /* Test: Function _validPaymentReceiver()
        └── Given address is the funding manager token
            └── When the function _validPaymentReceiver() is called
                └── Then it should return false
    */
    function testInternalValiPaymentReceiver_worksGivenReturnsFalseIfAddressIsFundingManagerToken(
    ) public {
        // Set address to funding manager token
        address addr = address(_orchestrator.fundingManager().token());

        // Test function call
        bool isValid =
            crossChainPaymentProcessorBase.exposed_validPaymentReceiver(addr);

        // Post-assert
        assertEq(isValid, false, "Address should be invalid");
    }

    /* Test: Function _validPaymentReceiver()
        ├── Given address is not address zero
        ├── And address is not msg.sender
        ├── And address is not the payment processor
        ├── And address is not the Orchestrator
        └── And address is not the funding manager token
            └── When the function _validPaymentReceiver() is called
                └── Then it should return true
    */
    function testInternalValiPaymentReceiver_worksGivenReturnsTrueIfAddressIsValid(
        address addr_
    ) public {
        // Validate test inputs
        helper_ensureNoAddressCollision(addr_);

        // Test function call
        bool isValid =
            crossChainPaymentProcessorBase.exposed_validPaymentReceiver(addr_);

        // Post-assert
        assertEq(isValid, true, "Address should be valid");
    }

    /* Test: Function _validTotal()
        └── Given total is 0
            └── When the function _validTotal() is called
                └── Then it should return false
    */
    function testInternalValidTotal_worksGivenReturnsFalseIfTotalIsZero()
        public
    {
        // Set total to 0
        uint total = 0;

        // Test function call
        bool isValid = crossChainPaymentProcessorBase.exposed_validTotal(total);

        // Post-assert
        assertEq(isValid, false, "Total should be invalid");
    }

    /* Test: Function _validTotal()
        └── Given total is not 0
            └── When the function _validTotal() is called
                └── Then it should return true
    */
    function testInternalValidTotal_worksGivenReturnsTrueIfTotalIsNotZero(
        uint total_
    ) public {
        // Validate test inputs
        vm.assume(total_ > 0);

        // Test function call
        bool isValid = crossChainPaymentProcessorBase.exposed_validTotal(total_);

        // Post-assert
        assertEq(isValid, true, "Total should be valid");
    }

    /* Test: Function _validPaymentToken()
        └── Given address does not have the ERC20 interface
            └── When the function _validPaymentToken() is called
                └── Then it should return false
    */
    function testInternalValidPaymentToken_worksGivenReturnsFalseIfAddressDoesNotHaveERC20Interface(
        address addr_
    ) public {
        // Validate test inputs
        helper_ensureNoAddressCollision(addr_);

        // Test function call
        bool isValid =
            crossChainPaymentProcessorBase.exposed_validPaymentToken(addr_);

        // Post-assert
        assertEq(isValid, false, "Address should be invalid");
    }

    /* Test: Function _validPaymentToken()
        └── Given address has the ERC20 interface
            └── When the function _validPaymentToken() is called
                └── Then it should return true
    */
    function testInternalValidPaymentToken_worksGivenReturnsTrueIfAddressHasERC20Interface(
    ) public {
        // Create and initialize a new ERC20 token
        ERC20Mock token = new ERC20Mock("Test", "TST", 18);
        token.mint(address(this), 1000);

        // Test function call
        bool isValid = crossChainPaymentProcessorBase.exposed_validPaymentToken(
            address(token)
        );

        // Post-assert
        assertEq(isValid, true, "Address should be valid");
    }

    // ========================================================================
    // Helper functions

    function helper_ensureNoAddressCollision(address addr_) public view {
        // Ensure address is not a precompile (0x1 to 0x9) or vm.etch fails
        vm.assume(uint160(addr_) > 0x9);

        vm.assume(
            addr_ != address(0) && addr_ != address(this)
                && addr_ != address(crossChainPaymentProcessorBase)
                && addr_ != address(paymentClient)
                && addr_ != address(_orchestrator)
                && addr_ != address(_orchestrator.fundingManager().token())
                && addr_ != address(_fundingManager)
                && addr_ != address(_paymentProcessor)
                && addr_ != address(_authorizer)
        );
    }
}
