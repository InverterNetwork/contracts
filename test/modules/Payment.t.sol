// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";


import {Payment} from "src/modules/Payment.sol";
import {ERC20} from "@oz/token/ERC20/ERC20.sol";

import {IModule} from "src/interfaces/IModule.sol";
import {IProposal} from "src/interfaces/IProposal.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {ProposalMock} from "test/utils/mocks/proposal/ProposalMock.sol";
import {AuthorizerMock} from "test/utils/mocks/AuthorizerMock.sol";




contract PaymentTest is Test, ProposalMock {

    // contract definitions
    Payment payment;
    ProposalMock proposal;
    ERC20Mock token;
    AuthorizerMock authorizerMock = new AuthorizerMock();


    // versioning system
    uint constant MAJOR_VERSION = 1;
    string constant GIT_URL = "https://github.com/organization/module";

    IModule.Metadata metadata = IModule.Metadata(MAJOR_VERSION, GIT_URL);

    //--------------------------------------------------------------------------------
    // SETUP

    constructor() ProposalMock(authorizerMock) {}

    function setUp() public {
        payment = new Payment();
        token = new ERC20Mock("TestToken", "TT");
        proposal = new ProposalMock(authorizerMock);

        bytes memory data = abi.encode(address(token), address(proposal));
        payment.initialize(IProposal(address(this)), metadata, data);

        address[] memory modules = new address[](1);
        modules[0] = address(payment);

        ProposalMock(this).initModules(modules);
    }

    function testTest() public {
        require(true);
    }

}
