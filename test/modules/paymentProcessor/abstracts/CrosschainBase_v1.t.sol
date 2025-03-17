//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {ModuleTest} from "test/modules/ModuleTest.sol";
import {OZErrors} from "test/utils/errors/OZErrors.sol";
import {ICrossChainBase_v1} from "@pp/interfaces/ICrosschainBase_v1.sol";
import {IERC20PaymentClientBase_v2} from
    "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV2Mock.sol";
import {CrossChainBase_v1_Exposed} from
    "test/utils/mocks/modules/paymentProcessor/CrossChainBase_v1_Exposed.sol";

//External
import {OZErrors} from "test/utils/errors/OZErrors.sol";
import {Clones} from "@oz/proxy/Clones.sol";

contract CrossChainBase_v1_Test is ModuleTest {
    //--------------------------------------------------------------------------
    //Constants
    //--------------------------------------------------------------------------
    //Mocks
    CrossChainBase_v1_Exposed public CrossChainBase;

    //--------------------------------------------------------------------------
    //Setup
    function setUp() public {
        //This function is used to setup the unit test
        //Deploy the SuT
        address impl = address(new CrossChainBase_v1_Exposed());
        CrossChainBase = CrossChainBase_v1_Exposed(Clones.clone(impl));

        //Setup the module to test
        _setUpOrchestrator(CrossChainBase);

        //Initiate the PP with the medata and config data
        CrossChainBase.init(_orchestrator, _METADATA, abi.encode(1));
    }
    //--------------------------------------------------------------------------
    //Test: Initialization
    /*
    └──  Given the contract is not initialized
    └── When initializing the contract
        └── Then it should set the correct orchestrator address */

    function testInit() public override(ModuleTest) {
        assertEq(address(CrossChainBase.orchestrator()), address(_orchestrator));
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
        assertTrue(CrossChainBase.supportsInterface(interfaceId));
    }

    /*  
    └──  Given the contract is already initialized
    └── When trying to reinitialize
        └── Then it should revert with Initializable__InvalidInitialization */
    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        CrossChainBase.init(_orchestrator, _METADATA, abi.encode(1));
    }

    /**
     * @dev Test interface support failure case
     * └── Given the contract is initialized
     * └── When checking for an unknown interface
     *     └── Then it should return false
     */
    function testSupportsInterface_failsGivenUnknownInterface() public {
        bytes4 randomInterfaceId = bytes4(keccak256("random()"));
        assertFalse(CrossChainBase.supportsInterface(randomInterfaceId));
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

        bytes memory result =
            CrossChainBase.exposed_executeBridgeTransfer(order);
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
        }
        return orders;
    }
}
