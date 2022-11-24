// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// @todo mp, nuggan: Sorry, had to refactor ModuleTest contract
//                   due to faulty initialization.
//                   Need to adjust these tests again :(

import {Test} from "forge-std/Test.sol";

// SuT
import {
    ListAuthorizer,
    IAuthorizer
} from "src/modules/governance/ListAuthorizer.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

// Internal Dependencies
import {Proposal} from "src/proposal/Proposal.sol";

// Interfaces
import {IModule, IProposal} from "src/modules/base/IModule.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {ModuleMock} from "test/utils/mocks/modules/base/ModuleMock.sol";
import {PaymentProcessorMock} from
    "test/utils/mocks/modules/PaymentProcessorMock.sol";

contract ListAuthorizerTest is Test {
    // Mocks
    ListAuthorizer _authorizer;
    Proposal internal _proposal = new Proposal();
    ERC20Mock internal _token = new ERC20Mock("Mock Token", "MOCK");
    PaymentProcessorMock _paymentProcessor = new PaymentProcessorMock();
    address ALBA = address(0xa1ba);
    address BOB = address(0xb0b);

    // Proposal Constants
    uint internal constant _PROPOSAL_ID = 1;

    // Module Constants
    uint constant MAJOR_VERSION = 1;
    uint constant MINOR_VERSION = 1;
    string constant URL = "https://github.com/organization/module";
    string constant TITLE = "Module";

    IModule.Metadata _METADATA =
        IModule.Metadata(MAJOR_VERSION, MINOR_VERSION, URL, TITLE);

    function setUp() public {
        address authImpl = address(new ListAuthorizer());
        _authorizer = ListAuthorizer(Clones.clone(authImpl));

        address propImpl = address(new Proposal());
        _proposal = Proposal(Clones.clone(propImpl));

        ModuleMock module = new  ModuleMock();
        address[] memory modules = new address[](1);
        modules[0] = address(module);

        _proposal.init(
            _PROPOSAL_ID,
            address(this),
            _token,
            modules,
            _authorizer,
            _paymentProcessor
        );

        address[] memory initialAuth = new address[](1);
        initialAuth[0] = address(this);

        _authorizer.init(
            IProposal(_proposal), _METADATA, abi.encode(initialAuth)
        );

        //authorize one address and deauthorize the initializer.
        _authorizer.addToAuthorized(ALBA);
        _authorizer.removeFromAuthorized(address(this));

        assertEq(_authorizer.isAuthorized(ALBA), true);
        assertEq(_authorizer.isAuthorized(address(this)), false);
        assertEq(_authorizer.getAmountAuthorized(), 1);
    }

    function testInitWithInitialAuthorized() public {
        //Checks that address list gets correctly stored on initialization
        // We "reuse" the proposal created in the setup, but the proposal doesn't know about this new authorizator.

        address authImpl = address(new ListAuthorizer());
        ListAuthorizer testAuthorizer = ListAuthorizer(Clones.clone(authImpl));

        address[] memory initialAuth = new address[](2);
        initialAuth[0] = ALBA;
        initialAuth[1] = BOB;

        testAuthorizer.init(
            IProposal(_proposal), _METADATA, abi.encode(initialAuth)
        );
        assertEq(address(testAuthorizer.proposal()), address(_proposal));
        assertEq(testAuthorizer.isAuthorized(ALBA), true);
        assertEq(testAuthorizer.isAuthorized(BOB), true);
        assertEq(testAuthorizer.isAuthorized(address(this)), false);
        assertEq(testAuthorizer.getAmountAuthorized(), 2);
    }

    function testReinitFails() public {
        //Create a mock new proposal
        Proposal newProposal = Proposal(Clones.clone(address(new Proposal())));

        address[] memory initialAuth = new address[](1);
        initialAuth[0] = address(this);

        vm.expectRevert();
        _authorizer.init(
            IProposal(newProposal), _METADATA, abi.encode(initialAuth)
        );
        assertEq(_authorizer.isAuthorized(address(this)), false);
        assertEq(address(_authorizer.proposal()), address(_proposal));
        assertEq(_authorizer.isAuthorized(ALBA), true);
        assertEq(_authorizer.getAmountAuthorized(), 1);
    }

    function testAddAuthorized() public {
        uint amountAuth = _authorizer.getAmountAuthorized();

        vm.prank(address(ALBA));
        _authorizer.addToAuthorized(BOB);

        assertEq(_authorizer.isAuthorized(BOB), true);
        assertEq(_authorizer.getAmountAuthorized(), (amountAuth + 1));
    }

    function testRemoveLastAuthorizedFails() public {
        uint amountAuth = _authorizer.getAmountAuthorized();

        vm.expectRevert(
            abi.encodeWithSelector(
                ListAuthorizer
                    .Module__ListAuthorizer__AuthorizerListCannotBeEmpty
                    .selector
            )
        );

        vm.prank(address(ALBA));
        _authorizer.removeFromAuthorized(ALBA);

        assertEq(_authorizer.isAuthorized(ALBA), true);
        assertEq(_authorizer.getAmountAuthorized(), amountAuth);
    }

    function testRemoveAuthorized() public {
        vm.prank(ALBA);
        _authorizer.addToAuthorized(BOB);

        uint amountAuth = _authorizer.getAmountAuthorized();

        vm.prank(address(ALBA));
        _authorizer.removeFromAuthorized(ALBA);

        assertEq(_authorizer.isAuthorized(ALBA), false);
        assertEq(_authorizer.getAmountAuthorized(), (amountAuth - 1));
    }

    function testTransferAuthorization() public {
        uint amountAuth = _authorizer.getAmountAuthorized();

        vm.prank(address(ALBA));
        _authorizer.transferAuthorization(BOB);

        assertEq(_authorizer.isAuthorized(ALBA), false);
        assertEq(_authorizer.isAuthorized(BOB), true);
        assertEq(_authorizer.getAmountAuthorized(), (amountAuth));
    }

    function testTransferAuthorizationToAlreadyAuthorizedFails() public {
        vm.prank(ALBA);
        _authorizer.addToAuthorized(BOB);

        uint amountAuth = _authorizer.getAmountAuthorized();

        vm.expectRevert(
            abi.encodeWithSelector(
                ListAuthorizer
                    .Module__ListAuthorizer__AddressAlreadyAuthorized
                    .selector
            )
        );
        vm.prank(address(ALBA));
        _authorizer.transferAuthorization(BOB);

        assertEq(_authorizer.isAuthorized(ALBA), true);
        assertEq(_authorizer.isAuthorized(BOB), true);
        assertEq(_authorizer.getAmountAuthorized(), (amountAuth));
    }

    function testUnauthorizedCallsFail() public {
        //test if a non authorized address fails authorization
        address SIFU = address(0x51f00);
        assertEq(_authorizer.isAuthorized(SIFU), false);

        //add without authorization fails
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        vm.prank(address(SIFU));
        _authorizer.addToAuthorized(SIFU);

        //remove without authorization fails
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        vm.prank(address(SIFU));
        _authorizer.removeFromAuthorized(ALBA);

        //transfer withour authorization fails
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        vm.prank(address(SIFU));
        _authorizer.removeFromAuthorized(address(1337));
    }
}
