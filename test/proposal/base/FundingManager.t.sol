// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

// SuT
import {
    FundingManagerMock,
    IFundingManager
} from "test/utils/mocks/proposal/base/FundingManagerMock.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract FundingManagerTest is Test {
    // SuT
    FundingManagerMock fundingManager;

    // Mocks
    ERC20Mock underlier;

    // Constants copied from SuT.
    uint internal constant MAX_SUPPLY = 1_000_000_000e18;

    // Other constants.
    uint8 private constant DECIMALS = 18;
    uint private constant PROPOSAL_ID = 1;

    function setUp() public {
        underlier = new ERC20Mock("Mock", "MOCK");

        fundingManager = new FundingManagerMock();
        fundingManager.init(underlier, PROPOSAL_ID, DECIMALS);
    }

    //--------------------------------------------------------------------------
    // Tests: Initialization

    function testInit() public {
        assertEq(fundingManager.decimals(), DECIMALS);
        assertEq(
            fundingManager.name(),
            "elastic Inverter Funding Token - Proposal #1"
        );
        assertEq(fundingManager.symbol(), "eIFT-1");

        assertEq(fundingManager.totalSupply(), 0);
        assertEq(fundingManager.scaledTotalSupply(), 0);
    }

    function testReinitFails() public {
        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        fundingManager.init(underlier, PROPOSAL_ID, DECIMALS);
    }

    function testInitFailsForNonInitializerFunction() public {
        fundingManager = new FundingManagerMock();

        vm.expectRevert(OZErrors.Initializable__NotInitializing);
        fundingManager.initNoInitializer(underlier, PROPOSAL_ID, DECIMALS);
    }

    //--------------------------------------------------------------------------
    // Tests: Public View Functions

    function testDeposit(address user, uint amount) public {
        vm.assume(user != address(0) && user != address(fundingManager));
        vm.assume(amount > 1 && amount <= MAX_SUPPLY);

        // Mint tokens to depositor.
        underlier.mint(user, amount);

        // User deposits tokens.
        vm.startPrank(user);
        {
            underlier.approve(address(fundingManager), type(uint).max);
            fundingManager.deposit(amount);
        }
        vm.stopPrank();

        // User received funding tokens on 1:1 basis.
        assertEq(fundingManager.balanceOf(user), amount);
        // FundingManager fetched tokens from the user.
        assertEq(underlier.balanceOf(address(fundingManager)), amount);

        // Simulate spending from the FundingManager by burning tokens.
        uint expenses = amount / 2;
        underlier.burn(address(fundingManager), expenses);

        // Rebase manually. Rebase is executed automatically on every token
        // balance mutating function.
        fundingManager.rebase();

        // User has half the token balance as before.
        assertEq(fundingManager.balanceOf(user), amount - expenses);
    }

    mapping(address => bool) _usersCache;

    struct UserDeposits {
        address[] users;
        uint[] deposits;
    }

    function testDepositWithdraw(UserDeposits memory input) public {
        vm.assume(input.users.length <= input.deposits.length);
        vm.assume(input.users.length > 1);
        vm.assume(input.users.length < 1000);

        // Each user is unique and valid recipient.
        for (uint i; i < input.users.length; ++i) {
            vm.assume(!_usersCache[input.users[i]]);
            _usersCache[input.users[i]] = true;

            vm.assume(input.users[i] != address(0));
            vm.assume(input.users[i] != address(fundingManager));
            vm.assume(input.users[i] != address(this));
        }

        // Sum of all deposits does not exceed MAX_SUPPLY.
        // Note that the length of users is used. deposits[users.length:] will
        // not be used and is just accepted to have less fuzzer rejections.
        uint max = MAX_SUPPLY / input.users.length;
        for (uint i; i < input.users.length; ++i) {
            vm.assume(input.deposits[i] != 0);
            vm.assume(input.deposits[i] < max);
        }

        // Mint deposit amount of underliers to users.
        for (uint i; i < input.users.length; ++i) {
            underlier.mint(input.users[i], input.deposits[i]);
        }

        // Each user gives infinite allowance to fundingManager.
        for (uint i; i < input.users.length; ++i) {
            vm.prank(input.users[i]);
            underlier.approve(address(fundingManager), type(uint).max);
        }

        // Half the users deposit their underliers.
        for (uint i; i < input.users.length / 2; ++i) {
            vm.prank(input.users[i]);
            fundingManager.deposit(input.deposits[i]);

            assertEq(
                fundingManager.balanceOf(input.users[i]), input.deposits[i]
            );
        }

        // The fundingManager spends an amount of underliers.
        uint expenses = fundingManager.totalSupply() / 2;
        underlier.burn(address(fundingManager), expenses);

        // The users who funded tokens, lost half their receipt tokens.
        // Note to rebase because balanceOf is not a token-state mutating function.
        fundingManager.rebase();
        for (uint i; i < input.users.length / 2; ++i) {
            // Note that we can be off-by-one due to rounding.
            assertApproxEqAbs(
                fundingManager.balanceOf(input.users[i]),
                input.deposits[i] / 2,
                1
            );
        }

        // The other half of the users deposit their underliers.
        for (uint i = input.users.length / 2; i < input.users.length; ++i) {
            vm.prank(input.users[i]);
            fundingManager.depositFor(input.users[i], input.deposits[i]);

            assertEq(
                fundingManager.balanceOf(input.users[i]), input.deposits[i]
            );
        }
    }

    function testDepositWithdrawUntilEmptyAndRedeposit(
        UserDeposits memory input
    ) public {
        // ----------- VALIDATION ---------

        vm.assume(input.users.length <= input.deposits.length);
        vm.assume(input.users.length > 1);
        vm.assume(input.users.length < 1000);

        // Each user is unique and valid recipient.
        for (uint i; i < input.users.length; ++i) {
            vm.assume(!_usersCache[input.users[i]]);
            _usersCache[input.users[i]] = true;

            vm.assume(input.users[i] != address(0));
            vm.assume(input.users[i] != address(fundingManager));
            vm.assume(input.users[i] != address(this));
        }

        // Sum of all deposits does not exceed MAX_SUPPLY.
        // Note that the length of users is used. deposits[users.length:] will
        // not be used and is just accepted to have less fuzzer rejections.
        uint max = MAX_SUPPLY / input.users.length;
        for (uint i; i < input.users.length; ++i) {
            vm.assume(input.deposits[i] != 0);
            vm.assume(input.deposits[i] < max);
        }

        // ----------- SETUP ---------

        //Buffer variable to track how much underlying balance each user has left
        uint[] memory remainingFunds = new uint[](input.users.length);

        //the deployer deposits 1 token so the proposal is never empty
        underlier.mint(address(this), 1);
        vm.startPrank(address(this));
        underlier.approve(address(fundingManager), type(uint).max);
        fundingManager.deposit(1);
        vm.stopPrank();
        assertEq(fundingManager.balanceOf(address(this)), 1);

        // Mint deposit amount of underliers to users.
        for (uint i; i < input.users.length; ++i) {
            underlier.mint(input.users[i], input.deposits[i]);
            remainingFunds[i] = input.deposits[i];
        }

        // Each user gives infinite allowance to fundingManager.
        for (uint i; i < input.users.length; ++i) {
            vm.prank(input.users[i]);
            underlier.approve(address(fundingManager), type(uint).max);
        }

        // ---- STEP ONE: FIRST MILESTONE

        // Half the users deposit their underliers.
        for (uint i; i < input.users.length / 2; ++i) {
            vm.prank(input.users[i]);
            fundingManager.deposit(input.deposits[i]);

            assertEq(
                fundingManager.balanceOf(input.users[i]), input.deposits[i]
            );
        }

        // The fundingManager spends an amount of underliers.
        uint expenses = fundingManager.totalSupply() / 2;
        underlier.burn(address(fundingManager), expenses);

        // The users who funded tokens, lost half their receipt tokens.
        // Note to rebase because balanceOf is not a token-state mutating function.
        fundingManager.rebase();
        for (uint i; i < input.users.length / 2; ++i) {
            // Note that we can be off-by-one due to rounding.
            assertApproxEqAbs(
                fundingManager.balanceOf(input.users[i]),
                remainingFunds[i] / 2,
                1
            );
            //We also update the balance tracking
            remainingFunds[i] = fundingManager.balanceOf(input.users[i]);
        }

        // ---- STEP TWO: SECOND MILESTONE

        // The other half of the users deposit their underliers.
        for (uint i = input.users.length / 2; i < input.users.length; ++i) {
            vm.prank(input.users[i]);
            fundingManager.depositFor(input.users[i], input.deposits[i]);

            assertEq(
                fundingManager.balanceOf(input.users[i]), input.deposits[i]
            );
        }

        // The fundingManager spends an amount of underliers.
        expenses = fundingManager.totalSupply() / 2;
        underlier.burn(address(fundingManager), expenses);

        // Everybody who deposited lost half their corresponding receipt tokens.
        // Note to rebase because balanceOf is not a token-state mutating function.
        fundingManager.rebase();
        for (uint i; i < input.users.length; ++i) {
            // Note that we can be off-by-one due to rounding.
            assertApproxEqAbs(
                fundingManager.balanceOf(input.users[i]),
                remainingFunds[i] / 2,
                1
            );

            //We also update the balance tracking
            remainingFunds[i] = fundingManager.balanceOf(input.users[i]);
        }

        // ---- STEP THREE: WIND DOWN PROPOSAL

        // The proposal is deemed completed, so everybody withdraws
        for (uint i; i < input.users.length; ++i) {
            uint balance = fundingManager.balanceOf(input.users[i]);
            if (balance != 0) {
                vm.prank(input.users[i]);
                fundingManager.withdraw(balance);
            }
        }

        //Once everybody has withdrawn, only the initial token + some possible balance rounding leftovers remain.
        assertTrue(fundingManager.totalSupply() <= (1 + input.users.length));

        // ---- STEP FOUR: RE-START PROPOSAL

        // Some time passes, and now half the users deposit their underliers again to continue funding (if they had any funds left).
        for (uint i; i < input.users.length / 2; ++i) {
            if (remainingFunds[i] != 0) {
                vm.prank(input.users[i]);
                fundingManager.deposit(remainingFunds[i]);

                assertEq(
                    fundingManager.balanceOf(input.users[i]), remainingFunds[i]
                );
            }
        }
    }
}
