// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

// Internal Dependencies
import {Proposal} from "src/proposal/Proposal.sol";
import {Payment} from "src/modules/Payment.sol";

// Interfaces
import {IAuthorizer} from "src/interfaces/IAuthorizer.sol";
import {IProposal} from "src/interfaces/IProposal.sol";

// Mocks
import {AuthorizerMock} from "test/utils/mocks/AuthorizerMock.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract PaymentTest is Test {
    Proposal proposal;
    Payment paymentModule;

    // Mocks
    AuthorizerMock authorizer;

    function setUp() public {
        authorizer = new AuthorizerMock();
        authorizer.setIsAuthorized(address(this), true);

        proposal = new Proposal();
        paymentModule = new Payment();

        // Init proposal with payment module.
        address[] memory funders = new address[](1);
        funders[0] = address(this);
        address[] memory modules = new address[](2);
        modules[0] = address(paymentModule);
        modules[1] = address(authorizer);
        proposal.initialize(1, funders, modules, IAuthorizer(authorizer));

        // Init module.
        bytes memory data = bytes("");
        paymentModule.initialize(IProposal(proposal), data);
    }

    function testPayment() public {
        // Create token and mint 1e18 to proposal.
        ERC20Mock token = new ERC20Mock("TOKEN", "TKN");
        token.mint(address(proposal), 1e18);

        // Add payment to module.
        uint id = paymentModule.addPayment(
            address(token), address(this), 1e18, block.timestamp
        );

        // Execute payment. Sends 1e18 tokens to address(this).
        paymentModule.executePayment(id);

        // Check balances.
        assertEq(token.balanceOf(address(proposal)), 0);
        assertEq(token.balanceOf(address(this)), 1e18);
    }
}
