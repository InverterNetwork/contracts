//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {ModuleTest} from "test/modules/ModuleTest.sol";
import {ICrossChainBase_v1} from "@pp/interfaces/ICrossChainBase_v1.sol";
import {IERC20PaymentClientBase_v2} from
    "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV2Mock.sol";
import {CrossChainBase_v1_Exposed} from "./CrossChainBase_v1_Exposed.sol";

//External
import {Clones} from "@oz/proxy/Clones.sol";

contract CrossChainBase_v1_Test is ModuleTest {
    //--------------------------------------------------------------------------
    // Mocks
    CrossChainBase_v1_Exposed public CrossChainBase;

    //--------------------------------------------------------------------------
    // Setup
    function setUp() public {
        //This function is used to setup the unit test
        //Deploy the SuT
        address impl = address(new CrossChainBase_v1_Exposed());
        CrossChainBase = CrossChainBase_v1_Exposed(Clones.clone(impl));

        //Setup the module to test
        _setUpOrchestrator(CrossChainBase);

        //Initiate the PP with the medata and config data
        CrossChainBase.init(_orchestrator, _METADATA, abi.encode(""));
    }

    //--------------------------------------------------------------------------
    // Initialization

    function testInit() public override(ModuleTest) {
        assertEq(address(CrossChainBase.orchestrator()), address(_orchestrator));
    }

    function testSupportsInterface() public {
        // Test for ICrossChainBase_v1 interface support
        bytes4 interfaceId = type(ICrossChainBase_v1).interfaceId;
        assertTrue(CrossChainBase.supportsInterface(interfaceId));
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        CrossChainBase.init(_orchestrator, _METADATA, abi.encode(1));
    }

    // -------------------------------------------------------------------------
    // Test Internal

    /* Test: _executeBridgeTransfer()
        └── Given a payment order with zero values is created
            └── When _executeBridgeTransfer is called
                └── Then it should return an empty bytes array
     */
    function testInternalExecuteBridgeTransfer_worksGivenImplemented() public {
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
}
