// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";


import {PaymentManager} from "src/modules/PaymentManager.sol";
// import {ERC20} from "@oz/token/ERC20/ERC20.sol";
//
import {IModule} from "src/interfaces/IModule.sol";
import {IProposal} from "src/interfaces/IProposal.sol";
// import {IERC20} from "@oz/token/ERC20/IERC20.sol";

import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {ProposalMock} from "test/utils/mocks/proposal/ProposalMock.sol";
import {AuthorizerMock} from "test/utils/mocks/AuthorizerMock.sol";


contract PaymentManagerTest is Test, ProposalMock {

    // contract definitions
    PaymentManager payment;
    ProposalMock proposal;
    ERC20Mock token;
    AuthorizerMock authorizerMock = new AuthorizerMock();

    // versioning system
    uint constant MAJOR_VERSION = 1;
    string constant GIT_URL = "https://github.com/organization/module";

    IModule.Metadata metadata = IModule.Metadata(MAJOR_VERSION, GIT_URL);

    //--------------------------------------------------------------------------
    // Modifiers

    // modifier validParams(uint amount, uint64 duration, address receiver) {
    //
    //     // fixed params
    //     uint64 start = uint64(block.timestamp);
    //
    //     // // Expect revert if amount is zero.
    //     if (amount == 0) {
    //         vm.expectRevert(bytes("invalid salary"));
    //         payment.addPayment(receiver, amount, start, duration);
    //         return;
    //     }
    //     // Expect revert if vestingDuration is zero.
    //     if (duration == 0){
    //         vm.expectRevert(bytes("invalid duration"));
    //         payment.addPayment(receiver, amount, start, duration);
    //         return;
    //     }
    //     if (start > duration + start){
    //         vm.expectRevert(bytes("invalid duration"));
    //         payment.addPayment(receiver, amount, start, duration);
    //         return;
    //     }
    //     // Expect revert if receiver is invalid.
    //     if (
    //         receiver == address(0) ||
    //         receiver == address(this) ||
    //         receiver == address(payment) ||
    //         receiver == address(token)
    //     ) {
    //         vm.expectRevert(bytes("invalid contributor"));
    //         payment.addPayment(receiver, amount, start, duration);
    //         return;
    //     }
    //
    //     _;
    // }


    //--------------------------------------------------------------------------------
    // SETUP

    constructor() ProposalMock(authorizerMock) {}

    function setUp() public {
        payment = new PaymentManager();
        token = new ERC20Mock("TestToken", "TT");
        proposal = new ProposalMock(authorizerMock);

        bytes memory data = abi.encode(address(token), address(proposal));
        payment.initialize(IProposal(address(this)), metadata, data);

        address[] memory modules = new address[](1);
        modules[0] = address(payment);

        ProposalMock(this).initModules(modules);
        authorizerMock.setIsAuthorized(address(this), true);
    }


    // NOTE should be test or just mintTokens?
    function mintTokens(uint amount) public {
        token.mint(address(this), amount);
        assertEq(token.balanceOf(address(this)), amount);
    }

    function testAddPayment()
        public
        // validParams(amount, duration, receiver)
        returns(uint, uint64, address) {

        // vesting params
        uint amount = 300;
        address receiver = address(0xBEEF); //aka. contributor/beneficiary
        uint64 start = uint64(block.timestamp);
        uint64 duration = 300; // seconds

        // mint erc20 tokens
        mintTokens(amount);

        // simulate payer's deposit to proposal
        // @todo Nejc transfer to proposal, not payment
        token.transfer(address(payment), amount);
        assertEq(token.balanceOf(address(payment)), amount);

        // initiate vesting
        payment.addPayment(receiver, amount, start, uint64(duration));

        //--------------------------------------------------------------------------
        // Validate vesting data on payment contract

        // validate beneficiary at Vesting is proper address
        bool vestingEnabled = payment.enabled(receiver);
        assertTrue(vestingEnabled);


        uint vestingStart = payment.start(receiver);
        assertEq(vestingStart, start);

        uint vestingDuration = payment.duration(receiver);
        assertEq(vestingDuration, duration);

        return (amount, duration, receiver);
    }

    function testClaim() public {
        (uint amount, uint64 duration, address receiver) =
            testAddPayment();

        vm.prank(receiver);
        uint releasableBefore = payment.releasable();
        assertEq(releasableBefore, 0);

        skip(duration);

        vm.prank(receiver);
        payment.claim();

        uint balanceAfter = token.balanceOf(receiver);
        assertEq(balanceAfter, amount);

        uint releasableAfter = payment.releasable();
        assertEq(releasableAfter, 0);
    }

    function testVestingAmounts() public {
      (uint amount, uint64 duration, address receiver)
          = testAddPayment();

        //at 1/3 duration, 1/3 tokens should be claimable
        uint balanceBefore = token.balanceOf(receiver);

        skip(duration*1/3);

        vm.prank(receiver);
        payment.claim();

        uint balanceAfter = token.balanceOf(receiver);
        assertEq(balanceAfter, amount*1/3);

        //at 2/3 duration, 2/3 tokens should be claimable
        balanceBefore = balanceAfter;

        skip(duration*1/3);

        vm.prank(receiver);
        payment.claim();

        balanceAfter = token.balanceOf(receiver);
        assertEq(balanceAfter, amount*2/3);

        //at 2 duration, all tokens should be claimable
        balanceBefore = balanceAfter;

        skip(duration);

        vm.prank(receiver);
        payment.claim();

        balanceAfter = token.balanceOf(receiver);
        assertEq(balanceAfter, amount);

    }

    function testRemovePayment() public {
        (uint amount, uint64 duration, address receiver)
            = testAddPayment();

        // make sure owner is refunded
        uint ownerBalanceBefore = token.balanceOf(address(this));
        uint receiverBalanceBefore = token.balanceOf(receiver);

        skip(duration/2);

        vm.prank(receiver);
        payment.claim();

        uint receiverBalanceAfter = token.balanceOf(receiver);
        assertEq(receiverBalanceBefore + amount/2, receiverBalanceAfter);

        payment.removePayment(receiver);

        uint ownerBalanceAfter = token.balanceOf(address(this));
        assertEq(ownerBalanceBefore + amount/2, ownerBalanceAfter);
    }

    function testPausePayment() public {
      (uint amount, uint64 duration, address receiver)
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
        (uint amount, uint64 duration, address receiver)
            = testAddPayment();

        payment.pausePayment(receiver);

        skip(duration);

        payment.continuePayment(receiver);

        // make sure receiver can claim
        uint receiverBalanceBefore = token.balanceOf(receiver);

        vm.prank(receiver);
        payment.claim();

        uint receiverBalanceAfter = token.balanceOf(receiver);
        assertEq(receiverBalanceBefore + amount, receiverBalanceAfter);
    }
}
