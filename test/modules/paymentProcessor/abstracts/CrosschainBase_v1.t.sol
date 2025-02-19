//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";
import {OZErrors} from "test/utils/errors/OZErrors.sol";
import {ICrossChainBase_v1} from
    "src/modules/paymentProcessor/interfaces/ICrossChainBase_v1.sol";
import {
    IERC20PaymentClientBase_v2,
    ERC20PaymentClientBaseV2Mock,
    ERC20Mock
} from "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV2Mock.sol";
import {CrossChainBase_v1_Exposed} from
    "test/utils/mocks/modules/paymentProcessor/CrossChainBase_v1_Exposed.sol";

import {IPaymentProcessor_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
//External Dependencies
import {OZErrors} from "test/utils/errors/OZErrors.sol";
import {Clones} from "@oz/proxy/Clones.sol";

contract CrossChainBase_v1_Test is ModuleTest {
    //--------------------------------------------------------------------------
    //Constants
    //--------------------------------------------------------------------------
    //Mocks
    ERC20PaymentClientBaseV2Mock paymentClient;
    CrossChainBase_v1_Exposed public crossChainBase;

    //--------------------------------------------------------------------------
    //Setup
    function setUp() public {
        //This function is used to setup the unit test
        //Deploy the SuT
        address impl = address(new CrossChainBase_v1_Exposed());
        crossChainBase = CrossChainBase_v1_Exposed(Clones.clone(impl));

        //Setup the module to test
        _setUpOrchestrator(crossChainBase);

        //General setup for other contracts in the workflow
        _authorizer.setIsAuthorized(address(this), true);

        //Initiate the PP with the medata and config data
        crossChainBase.init(_orchestrator, _METADATA, abi.encode(1));

        //Setup other modules needed in the unit tests.
        //In this case a payment client is needed to test the PP_Template_v1.
        impl = address(new ERC20PaymentClientBaseV2Mock());
        paymentClient = ERC20PaymentClientBaseV2Mock(Clones.clone(impl));
        //Adding the payment client is done through a timelock mechanism
        _orchestrator.initiateAddModuleWithTimelock(address(paymentClient));
        vm.warp(block.timestamp + _orchestrator.MODULE_UPDATE_TIMELOCK());
        _orchestrator.executeAddModule(address(paymentClient));
        //Init payment client
        paymentClient.init(_orchestrator, _METADATA, bytes(""));
        paymentClient.setIsAuthorized(address(crossChainBase), true);
        paymentClient.setToken(_token);
    }
    //--------------------------------------------------------------------------
    //Test: Initialization
    /*
    └──  Given the contract is not initialized
    └── When initializing the contract
        └── Then it should set the correct orchestrator address */

    function testInit() public override(ModuleTest) {
        assertEq(address(crossChainBase.orchestrator()), address(_orchestrator));
    }

    //--------------------------------------------------------------------------
    //Test: Interface Support
    /*
    └── Given the contract is initialized
    └── When checking for ICrossChainBase_v1 interface support
        └── Then it should return true
        └── When checking for an unknown interface
            └── Then it should return false */
    function testSupportsInterface() public {
        // Test for ICrossChainBase_v1 interface support
        bytes4 interfaceId = type(ICrossChainBase_v1).interfaceId;
        assertTrue(crossChainBase.supportsInterface(interfaceId));
    }

    /*  
    └──  Given the contract is already initialized
    └── When trying to reinitialize
        └── Then it should revert with Initializable__InvalidInitialization */
    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        crossChainBase.init(_orchestrator, _METADATA, abi.encode(1));
    }

    /**
     * @dev Test interface support failure case
     * └── Given the contract is initialized
     * └── When checking for an unknown interface
     *     └── Then it should return false
     */
    function testSupportsInterface_failsGivenUnknownInterface() public {
        bytes4 randomInterfaceId = bytes4(keccak256("random()"));
        assertFalse(crossChainBase.supportsInterface(randomInterfaceId));
    }

    //--------------------------------------------------------------------------
    //Test: executeBridgeTransfer

    /**
     * @dev Test bridge transfer with empty payment order
     * └── Given an empty payment order is created
     * └── When executeBridgeTransfer is called
     *     └── Then it should return empty bytes
     */
    function testExecuteBridgeTransfer_succeedsGivenEmptyPaymentOrder()
        public
    {
        address[] memory setupRecipients = new address[](1);
        setupRecipients[0] = address(1);
        uint[] memory setupAmounts = new uint[](1);
        setupAmounts[0] = 100 ether;

        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders =
            _createPaymentOrders(1, setupRecipients, setupAmounts);
        paymentClient.exposed_addPaymentOrders(orders);

        bytes memory executionData = abi.encode(0, 0); //maxFee and ttl setup

        bytes memory result = crossChainBase.exposed_executeBridgeTransfer(
            orders[0], executionData
        );
        assertEq(result, bytes(""));
    }

    //--------------------------------------------------------------------------
    //Helper Functions

    function _createPaymentOrders(
        uint orderCount,
        address[] memory recipients,
        uint[] memory amounts
    )
        internal
        view
        returns (IERC20PaymentClientBase_v2.PaymentOrder[] memory)
    {
        // Sanity checks for array lengths
        require(
            recipients.length == orderCount && amounts.length == orderCount,
            "Array lengths must match orderCount"
        );
        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders =
            new IERC20PaymentClientBase_v2.PaymentOrder[](orderCount);
        for (uint i = 0; i < orderCount; i++) {
            orders[i] = IERC20PaymentClientBase_v2.PaymentOrder({
                recipient: recipients[i],
                paymentToken: address(0xabcd),
                amount: amounts[i],
                originChainId: 0,
                targetChainId: 0,
                flags: bytes32(0),
                data: new bytes32[](0)
            });
            // orders[i] = IERC20PaymentClientBase_v2.PaymentOrder({
            //     recipient: recipients[i],
            //     paymentToken: address(0xabcd),
            //     amount: amounts[i],
            //     start: block.timestamp,
            //     cliff: 0,
            //     end: block.timestamp + 1 days
            // });
        }
        return orders;
    }
}
