// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

//Internal Dependencies
import {ModuleTest, IModule, IOrchestrator} from "test/modules/ModuleTest.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

// SuT
import {
    RebasingFundingManager,
    IFundingManager
} from "src/modules/fundingManager/RebasingFundingManager.sol";

contract RebasingFundingManagerTest is ModuleTest {
    bool hasDependency;
    string[] dependencies = new string[](0);

    struct UserDeposits {
        address[] users;
        uint[] deposits;
    }

    // SuT
    RebasingFundingManager fundingManager;

    mapping(address => bool) _usersCache;

    UserDeposits userDeposits;

    /// The deposit cap of underlying tokens. We keep it one factor below the MAX_SUPPLY of the rebasing token.
    /// Note that this sets the deposit limit for the fundign manager.
    uint internal constant DEPOSIT_CAP = 100_000_000e18;

    // Other constants.
    uint8 private constant DECIMALS = 18;
    uint private constant ORCHESTRATOR_ID = 1;

    function setUp() public {
        //because generateValidUserDeposits uses a mechanism to generate random numbers based on blocktimestamp we warp it
        vm.warp(1_680_220_800); // March 31, 2023 at 00:00 GMT

        //Add Module to Mock Orchestrator

        address impl = address(new RebasingFundingManager());
        fundingManager = RebasingFundingManager(Clones.clone(impl));

        _setUpOrchestrator(fundingManager);

        //Init Module
        fundingManager.init(
            _orchestrator, _METADATA, abi.encode(address(_token))
        );
    }

    function testSupportsInterface() public {
        bytes4 invalidInterface = 0xabcdef12;
        bytes4 rebasingInterface = type(IFundingManager).interfaceId;
        bytes4 moduleInterface = type(IModule).interfaceId;
        if (
            invalidInterface == rebasingInterface
                || invalidInterface == rebasingInterface
        ) {
            assertTrue(fundingManager.supportsInterface(invalidInterface));
        } else {
            assertTrue(!fundingManager.supportsInterface(invalidInterface));
            assertTrue(fundingManager.supportsInterface(rebasingInterface));
            assertTrue(fundingManager.supportsInterface(moduleInterface));
        }
    }

    //--------------------------------------------------------------------------
    // Test: Initialization

    //This function also tests all the getters
    //--------------------------------------------------------------------------
    // Tests: Initialization

    function testInit() public override(ModuleTest) {
        assertEq(fundingManager.decimals(), DECIMALS);
        assertEq(
            fundingManager.name(), "Inverter Funding Token - Orchestrator #1"
        );
        assertEq(fundingManager.symbol(), "IFT-1");

        assertEq(fundingManager.totalSupply(), 0);
        assertEq(fundingManager.scaledTotalSupply(), 0);
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        fundingManager.init(_orchestrator, _METADATA, abi.encode());
    }

    function testInit2RebasingFundingManager() public {
        // Attempting to call the init2 function with malformed data
        // SHOULD FAIL
        vm.expectRevert(
            IModule.Module__NoDependencyOrMalformedDependencyData.selector
        );
        fundingManager.init2(_orchestrator, abi.encode(123));

        // Calling init2 for the first time with no dependency
        // SHOULD FAIL
        bytes memory dependencyData = abi.encode(hasDependency, dependencies);
        vm.expectRevert(
            IModule.Module__NoDependencyOrMalformedDependencyData.selector
        );
        fundingManager.init2(_orchestrator, dependencyData);

        // Calling init2 for the first time with dependency = true
        // SHOULD PASS
        dependencyData = abi.encode(true, dependencies);
        fundingManager.init2(_orchestrator, dependencyData);

        // Attempting to call the init2 function again.
        // SHOULD FAIL
        vm.expectRevert(IModule.Module__CannotCallInit2Again.selector);
        fundingManager.init2(_orchestrator, dependencyData);
    }

    //--------------------------------------------------------------------------
    // Tests: Public View Functions

    function testDeposit(address user, uint amount) public {
        vm.assume(user != address(0) && user != address(fundingManager));
        amount = bound(amount, 2, DEPOSIT_CAP);

        // Mint tokens to depositor.
        _token.mint(user, amount);

        // User deposits tokens.
        vm.startPrank(user);
        {
            _token.approve(address(fundingManager), type(uint).max);
            fundingManager.deposit(amount);
        }
        vm.stopPrank();

        // User received funding tokens on 1:1 basis.
        assertEq(fundingManager.balanceOf(user), amount);
        // FundingManager fetched tokens from the user.
        assertEq(_token.balanceOf(address(fundingManager)), amount);

        // Simulate spending from the FundingManager by burning tokens.
        uint expenses = amount / 2;
        _token.burn(address(fundingManager), expenses);

        // Rebase manually. Rebase is executed automatically on every token
        // balance mutating function.
        fundingManager.rebase();

        // User has half the token balance as before.
        assertEq(fundingManager.balanceOf(user), amount - expenses);
    }

    function testSelfDepositFails(address user, uint amount) public {
        vm.assume(user != address(0) && user != address(fundingManager));
        amount = bound(amount, 2, DEPOSIT_CAP - 1);

        vm.expectRevert(
            IFundingManager.Module__FundingManager__CannotSelfDeposit.selector
        );

        // User deposits tokens.
        vm.prank(address(fundingManager));
        fundingManager.deposit(1);

        // Mint tokens to depositor.
        _token.mint(user, amount + 1);

        // User deposits tokens.
        vm.startPrank(user);
        {
            _token.approve(address(fundingManager), type(uint).max);
            fundingManager.deposit(amount);
        }
        vm.stopPrank();

        if (amount + 1 > DEPOSIT_CAP) {
            vm.expectRevert(
                IFundingManager
                    .Module__FundingManager__CannotSelfDeposit
                    .selector
            );
        }
        vm.startPrank(user);
        {
            fundingManager.deposit(1);
        }
        vm.stopPrank();
    }

    function testDepositAndSpendFunds(
        uint userAmount,
        uint[] calldata depositAmounts
    ) public {
        userAmount = bound(userAmount, 2, 999);
        vm.assume(userAmount <= depositAmounts.length);

        UserDeposits memory input =
            generateValidUserDeposits(userAmount, depositAmounts);

        // Mint deposit amount of underliers to users.
        for (uint i; i < input.users.length; ++i) {
            _token.mint(input.users[i], input.deposits[i]);
        }

        // Each user gives infinite allowance to fundingManager.
        for (uint i; i < input.users.length; ++i) {
            vm.prank(input.users[i]);
            _token.approve(address(fundingManager), type(uint).max);
        }

        // Half the users deposit their underliers.
        uint undelierDeposited = 0; // keeps track of amount deposited so we can use it later
        for (uint i; i < (input.users.length / 2); ++i) {
            vm.prank(input.users[i]);
            fundingManager.deposit(input.deposits[i]);

            assertEq(
                fundingManager.balanceOf(input.users[i]), input.deposits[i]
            );
            assertEq(_token.balanceOf(input.users[i]), 0);

            assertEq(
                _token.balanceOf(address(fundingManager)),
                undelierDeposited + input.deposits[i]
            );
            undelierDeposited += input.deposits[i];
        }

        // A big amount of underliers tokens leave the manager, f.ex at Milestone start.
        uint expenses = undelierDeposited / 2;
        _token.burn(address(fundingManager), expenses);

        // Confirm that the users who funded tokens, lost half their receipt tokens.
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

    function testDepositSpendUntilEmptyRedepositAndWindDown(
        uint userAmount,
        uint[] calldata depositAmounts
    ) public {
        userAmount = bound(userAmount, 1, 999);
        vm.assume(userAmount <= depositAmounts.length);

        UserDeposits memory input =
            generateValidUserDeposits(userAmount, depositAmounts);

        // ----------- SETUP ---------

        //Buffer variable to track how much underlying balance each user has left
        uint[] memory remainingFunds = new uint[](input.users.length);

        //the deployer deposits 1 token so the orchestrator is never empty
        _token.mint(address(this), 1);
        vm.startPrank(address(this));
        _token.approve(address(fundingManager), type(uint).max);
        fundingManager.deposit(1);
        vm.stopPrank();
        assertEq(fundingManager.balanceOf(address(this)), 1);

        // Mint deposit amount of underliers to users.
        for (uint i; i < input.users.length; ++i) {
            _token.mint(input.users[i], input.deposits[i]);
            remainingFunds[i] = input.deposits[i];
        }

        // Each user gives infinite allowance to fundingManager.
        for (uint i; i < input.users.length; ++i) {
            vm.prank(input.users[i]);
            _token.approve(address(fundingManager), type(uint).max);
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
        _token.burn(address(fundingManager), expenses);

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
        _token.burn(address(fundingManager), expenses);

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

        // ---- STEP THREE: WIND DOWN ORCHESTRATOR

        // The orchestrator is deemed completed, so everybody withdraws
        for (uint i; i < input.users.length; ++i) {
            uint balance = fundingManager.balanceOf(input.users[i]);
            if (balance != 0) {
                vm.prank(input.users[i]);
                //to test both withdraw and withdrawTo
                if (i % 2 == 0) {
                    fundingManager.withdraw(balance);
                } else {
                    fundingManager.withdrawTo(input.users[i], balance);
                }
            }
        }

        //Once everybody has withdrawn, only the initial token + some possible balance rounding leftovers remain.
        assertTrue(fundingManager.totalSupply() <= (1 + input.users.length));

        // ---- STEP FOUR: RE-START ORCHESTRATOR

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

    //--------------------------------------------------------------------------
    // Tests: OnlyOrchestrator Mutating Functions

    function testTransferOrchestratorToken(address to, uint amount) public {}

    function testTransferOrchestratorTokenFails(address caller, address to)
        public
    {
        _token.mint(address(fundingManager), 2);

        if (caller != address(_orchestrator)) {
            vm.expectRevert(IModule.Module__OnlyCallableByOrchestrator.selector);
        }
        vm.prank(caller);
        fundingManager.transferOrchestratorToken(address(0xBEEF), 1);

        if (to == address(0) || to == address(fundingManager)) {
            vm.expectRevert(
                IFundingManager.Module__FundingManager__InvalidAddress.selector
            );
        }

        vm.prank(address(_orchestrator));
        fundingManager.transferOrchestratorToken(to, 1);
    }

    //--------------------------------------------------------------------------
    // Helper Functions

    function generateValidUserDeposits(
        uint amountOfDepositors,
        uint[] memory depositAmounts
    ) internal returns (UserDeposits memory) {
        // We cap the amount each user will deposit so we dont exceed the total supply.
        uint maxDeposit = (DEPOSIT_CAP / amountOfDepositors);
        for (uint i = 0; i < amountOfDepositors; i++) {
            //we generate a "random" address
            address addr = address(uint160(i + 1));
            if (
                addr != address(0) && addr != address(fundingManager)
                    && !_usersCache[addr] && addr != address(this)
            ) {
                //This should be enough for the case we generated a duplicate address
                addr = address(uint160(block.timestamp - i));
            }

            // Store the address and mark it as used.
            userDeposits.users.push(addr);
            _usersCache[addr] = true;

            //This is to avoid the fuzzer to generate a deposit amount that is too big
            depositAmounts[i] = bound(depositAmounts[i], 1, maxDeposit - 1);
            userDeposits.deposits.push(depositAmounts[i]);
        }
        return userDeposits;
    }

    // =========================================================================
}
