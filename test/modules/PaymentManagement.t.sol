// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";


import {PaymentManagement} from "src/modules/PaymentManagement.sol";
// import {ERC20} from "@oz/token/ERC20/ERC20.sol";
//
import {IModule} from "src/interfaces/IModule.sol";
import {IProposal} from "src/interfaces/IProposal.sol";
// import {IERC20} from "@oz/token/ERC20/IERC20.sol";

import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {ProposalMock} from "test/utils/mocks/proposal/ProposalMock.sol";
import {AuthorizerMock} from "test/utils/mocks/AuthorizerMock.sol";


contract PaymentManagementTest is Test, ProposalMock {

    // contract definitions
    PaymentManagement payment;
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
        payment = new PaymentManagement();
        token = new ERC20Mock("TestToken", "TT");
        proposal = new ProposalMock(authorizerMock);

        bytes memory data = abi.encode(address(token), address(proposal));
        payment.initialize(IProposal(address(this)), metadata, data);

        address[] memory modules = new address[](1);
        modules[0] = address(payment);

        ProposalMock(this).initModules(modules);
    }


    // NOTE should be test or just mintTokens?
    function mintTokens(uint amount) public {
        token.mint(address(this), amount);
        assertEq(token.balanceOf(address(this)), amount);
    }

    function testAddPayment()
        public
        returns(uint, address, uint64, uint64) {

        // vesting params
        uint vestingAmount = 100;
        address receiver = address(0xBEEF); //aka. contributor/beneficiary
        uint64 start = uint64(block.timestamp);
        uint64 duration = 300; // seconds

        // mint erc20 tokens
        mintTokens(vestingAmount);

        // simulate payer's deposit to proposal
        // @todo Nejc transfer to proposal, not payment
        token.transfer(address(payment), vestingAmount);
        assertEq(token.balanceOf(address(payment)), vestingAmount);

        // initiate vesting
        payment.addPayment(
            receiver,
            vestingAmount,
            start,
            duration
        );

        // make sure tokens are transfered to vesting
        assertEq(token.balanceOf(address(payment)), vestingAmount);

        //--------------------------------------------------------------------------
        // Validate vesting data on payment contract

        // validate beneficiary at Vesting is proper address
        bool vestingEnabled = payment.enabled(receiver);
        assertTrue(vestingEnabled);

        uint vestingStart = payment.start(receiver);
        assertEq(vestingStart, start);

        uint vestingDuration = payment.duration(receiver);
        assertEq(vestingDuration, duration);

        return (vestingAmount, receiver, start, duration);
    }

    function testClaim() public {
        (uint vestingAmount, address receiver, uint64 start, uint64 duration)
            = testAddPayment();

        vm.prank(receiver);
        uint releasableBefore = payment.releasable();
        assertEq(releasableBefore, 0);

        skip(duration);

        vm.prank(receiver);
        payment.claim();

        uint balanceAfter = token.balanceOf(receiver);
        console.log("balanceAfter: " ,balanceAfter);
        assertEq(balanceAfter, vestingAmount);

        uint releasableAfter = payment.releasable();
        assertEq(releasableAfter, 0);
    }

    function testRemovePayment() public {
        (uint vestingAmount, address receiver, uint64 start, uint64 duration)
            = testAddPayment();

        // make sure owner is refunded
        uint ownerBalanceBefore = token.balanceOf(address(this));

        payment.removePayment(receiver);

        uint ownerBalanceAfter = token.balanceOf(address(this));
        assertEq(ownerBalanceBefore + vestingAmount, ownerBalanceAfter);

        skip(duration);

        // make sure receiver cant claim
        uint receiverBalanceBefore = token.balanceOf(receiver);

        vm.prank(receiver);
        payment.claim();

        uint receiverBalanceAfter = token.balanceOf(receiver);
        assertEq(receiverBalanceBefore, receiverBalanceAfter);
    }

    function testPausePayment() public {
        (uint vestingAmount, address receiver, uint64 start, uint64 duration)
            = testAddPayment();

        // make sure receiver cant claim
        uint receiverBalanceBefore = token.balanceOf(receiver);

        payment.pausePayment(receiver);

        skip(duration);

        vm.prank(receiver);
        payment.claim();

        uint receiverBalanceAfter = token.balanceOf(receiver);
        assertEq(receiverBalanceBefore, receiverBalanceAfter);
    }

    function testContinuePayment() public {
        (uint vestingAmount, address receiver, uint64 start, uint64 duration)
            = testAddPayment();

        payment.pausePayment(receiver);

        skip(duration);

        payment.continuePayment(receiver);

        // make sure receiver can claim
        uint receiverBalanceBefore = token.balanceOf(receiver);

        vm.prank(receiver);
        payment.claim();

        uint receiverBalanceAfter = token.balanceOf(receiver);
        assertEq(receiverBalanceBefore + vestingAmount, receiverBalanceAfter);
    }
}
