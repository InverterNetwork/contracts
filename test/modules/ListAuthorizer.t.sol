// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

// Internal Dependencies
import {Proposal} from "src/proposal/Proposal.sol";
import {ContributorManager} from "src/modules/governance/ContributorManager.sol";
import {ListAuthorizer} from "src/modules/governance/ListAuthorizer.sol";

// Interfaces
import {IAuthorizer} from "src/modules/IAuthorizer.sol";
import {IModule, IProposal} from "src/modules/base/IModule.sol";

// Mocks
import {ProposalMock} from "test/utils/mocks/proposal/ProposalMock.sol";
import {AuthorizerMock} from "test/utils/mocks/AuthorizerMock.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract ListAuthorizerTest is Test {
    // Mocks
    ListAuthorizer authorizer;
    ProposalMock proposal;
    address ALBA = address(0xa1ba);
    address BOB = address(0xb0b);

    function setUp() public {
        authorizer = new ListAuthorizer();

        proposal = new ProposalMock(authorizer);

        // Initialize the Authorizer
        IModule.Metadata memory data =
            IModule.Metadata(1, "https://www.github.com");

        authorizer.initialize(IProposal(proposal), data);

        //authorize one address and deauthorize the deployer.
        vm.prank(address(proposal));
        authorizer.__ListAuthorizer_addToAuthorized(ALBA);

        vm.prank(address(proposal));
        authorizer.__ListAuthorizer_removeFromAuthorized(address(this));

        assertEq(authorizer.isAuthorized(ALBA), true);
        assertEq(authorizer.isAuthorized(address(this)), false);
        assertEq(authorizer.getAmountAuthorized(), 1);
    }

    function testAddAuthorized() public {
        uint amountAuth = authorizer.getAmountAuthorized();

        vm.prank(address(proposal));
        authorizer.__ListAuthorizer_addToAuthorized(BOB);

        assertEq(authorizer.isAuthorized(BOB), true);
        assertEq(authorizer.getAmountAuthorized(), (amountAuth + 1));
    }

    function testRemoveAuthorized() public {
        //this test leaves an empty authorizer list. If we choose to disallow that it will need to be cahnged.
        uint amountAuth = authorizer.getAmountAuthorized();

        vm.prank(address(proposal));
        authorizer.__ListAuthorizer_removeFromAuthorized(ALBA);

        assertEq(authorizer.isAuthorized(ALBA), false);
        assertEq(authorizer.getAmountAuthorized(), (amountAuth - 1));
    }

    function testTransferAuthorization() public {
        uint amountAuth = authorizer.getAmountAuthorized();

        vm.prank(address(proposal));
        authorizer.__ListAuthorizer_transferAuthorization(ALBA, BOB);

        assertEq(authorizer.isAuthorized(ALBA), false);
        assertEq(authorizer.isAuthorized(BOB), true);
        assertEq(authorizer.getAmountAuthorized(), (amountAuth));
    }

    function testAccessControl() public {
        uint amountAuth = authorizer.getAmountAuthorized();

        //test if a non authorized address fails authorization
        address SIFU = address(0x51f00);
        assertEq(authorizer.isAuthorized(SIFU), false);

        //add authorized address/remove it and test authorization

        vm.startPrank(address(proposal));
        authorizer.__ListAuthorizer_addToAuthorized(BOB);
        authorizer.__ListAuthorizer_removeFromAuthorized(BOB);
        vm.stopPrank();

        assertEq(authorizer.isAuthorized(BOB), false);
        assertEq(authorizer.getAmountAuthorized(), (amountAuth));
    }
}
