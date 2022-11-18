// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// @todo mp, nuggan: Sorry, had to refactor ModuleTest contract
//                   due to faulty initialization.
//                   Need to adjust these tests again :(

import {Test} from "forge-std/Test.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

// Internal Dependencies
import {Proposal} from "src/proposal/Proposal.sol";
import {ContributorManager} from "src/proposal/base/ContributorManager.sol";
import {ListAuthorizer} from "src/modules/governance/ListAuthorizer.sol";

// Interfaces
import {IAuthorizer} from "src/modules/IAuthorizer.sol";
import {IModule, IProposal} from "src/modules/base/IModule.sol";

// Mocks
import {ProposalMock} from "test/utils/mocks/proposal/ProposalMock.sol";
import {AuthorizerMock} from "test/utils/mocks/AuthorizerMock.sol";
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
    uint internal constant _MAJOR_VERSION = 1;
    string internal constant _GIT_URL = "https://github.com/org/module";

    IModule.Metadata internal _METADATA =
        IModule.Metadata(_MAJOR_VERSION, _GIT_URL);

    function setUp() public {
        address authImpl = address(new ListAuthorizer());
        _authorizer = ListAuthorizer(Clones.clone(authImpl));

        address impl = address(new Proposal());
        _proposal = Proposal(Clones.clone(impl));

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

        address[] memory initialAuth;

        _authorizer.initialize(IProposal(_proposal), initialAuth, _METADATA);

        //authorize one address and deauthorize the deployer.
        _authorizer.addToAuthorized(ALBA);
        _authorizer.removeFromAuthorized(address(this));

        assertEq(_authorizer.isAuthorized(ALBA), true);
        assertEq(_authorizer.isAuthorized(address(this)), false);
        assertEq(_authorizer.getAmountAuthorized(), 1);
    }

    function testInitWithInitialAuthorized() public {
        //This checks initialization on a "new" authorizer.
        // Note that the Proposal created in the setup (and used here) doesn't know anything about this authorizer.

        address authImpl = address(new ListAuthorizer());
        ListAuthorizer testAuthorizer = ListAuthorizer(Clones.clone(authImpl));

        address[] memory initialAuth = new address[](2);
        initialAuth[0] = ALBA;
        initialAuth[1] = BOB;

        testAuthorizer.initialize(IProposal(_proposal), initialAuth, _METADATA);

        //assertEq(ListAuthorizer.__Module_proposal, _proposal);
        //assertEq(ListAuthorizer.__Module_metadata, _METADATA);
        assertEq(testAuthorizer.isAuthorized(address(this)), false);
        assertEq(testAuthorizer.isAuthorized(ALBA), true);
        assertEq(testAuthorizer.isAuthorized(BOB), true);
        assertEq(testAuthorizer.getAmountAuthorized(), 2);
    }

    function testInitWithoutInitialAuthorized() public {
        //This checks initialization on a "new" authorizer.
        // Note that the Proposal created in the setup (and used here) doesn't know anything about this authorizer.

        address authImpl = address(new ListAuthorizer());
        ListAuthorizer testAuthorizer = ListAuthorizer(Clones.clone(authImpl));

        address[] memory initialAuth;

        testAuthorizer.initialize(IProposal(_proposal), initialAuth, _METADATA);

        //assertEq(ListAuthorizer.__Module_proposal, _proposal);
        //assertEq(ListAuthorizer.__Module_metadata, _METADATA);
        assertEq(testAuthorizer.isAuthorized(address(this)), true);
        assertEq(testAuthorizer.getAmountAuthorized(), 1);
    }

    function testReinitFails() public {
        ProposalMock newProposal = new ProposalMock(_authorizer);

        address[] memory initialAuth = new address[](2);
        initialAuth[0] = ALBA;
        initialAuth[1] = BOB;

        vm.expectRevert();
        vm.prank(ALBA);
        _authorizer.initialize(IProposal(newProposal), initialAuth, _METADATA);

        //assertEq(ListAuthorizer.__Module_proposal, _proposal);
        //assertEq(ListAuthorizer.__Module_metadata, _METADATA);
        assertEq(_authorizer.isAuthorized(address(this)), false);
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
                ListAuthorizer.Module__AuthorizerListCannotBeEmpty.selector
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

        //Again, callback reverts but the func only doesnt't do anything

        vm.expectRevert(
            abi.encodeWithSelector(
                ListAuthorizer.Module__AddressAlreadyAuthorized.selector
            )
        );

        vm.prank(address(ALBA));
        _authorizer.transferAuthorization(BOB);

        assertEq(_authorizer.isAuthorized(ALBA), true);
        assertEq(_authorizer.isAuthorized(BOB), true);
        assertEq(_authorizer.getAmountAuthorized(), (amountAuth));
    }

    function testAccessControl() public {
        uint amountAuth = _authorizer.getAmountAuthorized();

        //test if a non authorized address fails authorization
        address SIFU = address(0x51f00);
        assertEq(_authorizer.isAuthorized(SIFU), false);

        //add authorized address/remove it and test authorization

        vm.startPrank(address(ALBA));
        _authorizer.addToAuthorized(BOB);
        _authorizer.removeFromAuthorized(BOB);
        vm.stopPrank();

        assertEq(_authorizer.isAuthorized(BOB), false);
        assertEq(_authorizer.getAmountAuthorized(), (amountAuth));
    }
}
