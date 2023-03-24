// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import "forge-std/console.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

//Internal Dependencies
import {
    ModuleTest,
    IModule,
    IProposal,
    LibString
} from "test/modules/ModuleTest.sol";

import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// SuT
import {
    SpecificFundingManager,
    ISpecificFundingManager
} from "src/modules/milestoneSubModules/SpecificFundingManager.sol";

contract SpecificFundingManagerTest is ModuleTest {
    using LibString for string;

    address milestoneModule = address(0xBeef);

    address Alice = address(0xA11CE);
    address Bob = address(0x606);

    // SuT
    SpecificFundingManager specificFundingManager;

    ERC20Mock token;

    function setUp() public {
        //Add Module to Mock Proposal

        address impl = address(new SpecificFundingManager());
        specificFundingManager = SpecificFundingManager(Clones.clone(impl));

        _setUpProposal(specificFundingManager);

        //Init Module
        specificFundingManager.init(
            _proposal, _METADATA, abi.encode(milestoneModule)
        );

        token = ERC20Mock(address(_proposal.token()));
    }

    //--------------------------------------------------------------------------
    // Test: Events

    event SpecificMilestoneFunded(
        uint indexed milestoneId, uint indexed amount, address indexed funder
    );

    event SpecificMilestoneFundingAdded(
        uint indexed milestoneId, uint indexed amount, address indexed funder
    );

    event SpecificMilestoneFundingWithdrawn(
        uint indexed milestoneId, uint indexed amount, address indexed funder
    );

    event SpecificMilestoneFundingRemoved(
        uint indexed milestoneId, address indexed funder
    );

    event FundingCollected(
        uint indexed milestoneId, uint indexed amount, address[] funders
    );

    //--------------------------------------------------------------------------
    // Test: Initialization

    //This function also tests all the getters
    function testInit() public override(ModuleTest) {
        assertTrue(milestoneModule == specificFundingManager.milestoneManager());
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        specificFundingManager.init(_proposal, _METADATA, bytes(""));
    }

    //--------------------------------------------------------------------------
    // Test: Getter

    function testGetFunderAmountForMilestoneId(
        uint id,
        uint amount1,
        uint amount2
    ) public {
        amount1 = bound(amount1, 1, 10);
        amount2 = bound(amount2, 1, 10);

        assertTrue(
            specificFundingManager.getFunderAmountForMilestoneId(id) == 0
        );

        fundSpecificMilestone(id, Alice, amount1);
        fundSpecificMilestone(id, Bob, amount2);

        assertTrue(
            specificFundingManager.getFunderAmountForMilestoneId(id)
                == amount1 + amount2
        );
    }

    function testGetFunderAddressesForMilestoneId(uint id) public {
        assertTrue(
            specificFundingManager.getFunderAddressesForMilestoneId(id).length
                == 0
        );

        fundSpecificMilestone(id, Alice, 1);
        fundSpecificMilestone(id, Bob, 1);

        assertTrue(
            specificFundingManager.getFunderAddressesForMilestoneId(id).length
                == 2
        );

        assertTrue(
            specificFundingManager.getFunderAddressesForMilestoneId(id)[0]
                == Alice
        );

        assertTrue(
            specificFundingManager.getFunderAddressesForMilestoneId(id)[1]
                == Bob
        );
    }

    function testGetFunderAmountForMilestoneId(uint id, uint amount) public {
        amount = bound(amount, 1, 10);
        assertTrue(
            specificFundingManager.getFundingAmountForMilestoneIdAndAddress(
                id, Alice
            ) == 0
        );

        fundSpecificMilestone(id, Alice, amount);

        assertTrue(
            specificFundingManager.getFundingAmountForMilestoneIdAndAddress(
                id, Alice
            ) == amount
        );
    }

    //--------------------------------------------------------------------------
    // Test: Modifier

    function testOnlyMilestoneManagerAccess(address adr) public {
        //@note is this enough?
        vm.assume(adr != milestoneModule);
        vm.expectRevert(
            ISpecificFundingManager
                .Module__ISpecificFundingManager__OnlyMilestoneManagerAccess
                .selector
        );
        vm.prank(adr);
        specificFundingManager.collectFunding(0, 0);
    }

    function testValidAmount() public {
        //@note is this enough?
        vm.expectRevert(
            ISpecificFundingManager
                .Module__ISpecificFundingManager__InvalidAmount
                .selector
        );
        specificFundingManager.fundSpecificMilestone(0, 0);
    }

    function testValidWithdrawAmount() public {
        //@note is this enough?
        vm.expectRevert(
            ISpecificFundingManager
                .Module__ISpecificFundingManager__InvalidWithdrawAmount
                .selector
        );
        specificFundingManager.withdrawSpecificMilestoneFunding(0, 10);

        fundSpecificMilestone(0, address(this), 1);

        vm.expectRevert(
            ISpecificFundingManager
                .Module__ISpecificFundingManager__InvalidWithdrawAmount
                .selector
        );
        specificFundingManager.withdrawSpecificMilestoneFunding(0, 10);
    }

    function testAllowanceHighEnough() public {
        //@note is this enough?

        token.mint(Alice, 1);

        vm.expectRevert(
            ISpecificFundingManager
                .Module__ISpecificFundingManager__AllowanceNotHighEnough
                .selector
        );

        vm.prank(Alice);
        specificFundingManager.fundSpecificMilestone(0, 1);
    }

    function testFundingNotCollected() public {
        //@note is this enough?

        vm.prank(milestoneModule);
        specificFundingManager.collectFunding(0, 1);

        vm.expectRevert(
            ISpecificFundingManager
                .Module__ISpecificFundingManager__FundingAlreadyCollected
                .selector
        );

        vm.prank(milestoneModule);
        specificFundingManager.collectFunding(0, 1);
    }

    //--------------------------------------------------------------------------
    // Test: Mutating Functions

    //fundSpecificMilestone()
    function testFundSpecificMilestone(
        uint id,
        uint amount1,
        uint amount2,
        address funder
    ) public {
        vm.assume(funder != address(0));
        amount1 = bound(amount1, 1, 2 ** 128); //Reasonable high number for testing
        amount2 = bound(amount2, 1, 2 ** 128);

        //Main functionality
        token.mint(funder, amount1);
        vm.prank(funder);
        token.approve(address(specificFundingManager), amount1);

        vm.expectEmit(true, true, true, false);
        emit SpecificMilestoneFunded(id, amount1, funder);

        //Actually call function
        vm.prank(funder);
        //Check if return value is correct
        assertTrue(
            specificFundingManager.fundSpecificMilestone(id, amount1) == amount1
        );

        //Check if Array contains funder address
        assertTrue(
            fundersContainAddress(
                funder,
                specificFundingManager.getFunderAddressesForMilestoneId(id)
            )
        );

        //Check if Milestone Funding Amount is correctly updated
        assertTrue(
            specificFundingManager.getFunderAmountForMilestoneId(id) == amount1
        );

        //Check if Funder Amount is correctly updated
        assertTrue(
            specificFundingManager.getFundingAmountForMilestoneIdAndAddress(
                id, funder
            ) == amount1
        );

        //Check if token balances updated accordingly
        assertTrue(token.balanceOf(funder) == 0);
        assertTrue(token.balanceOf(address(specificFundingManager)) == amount1);

        token.mint(funder, amount2);
        vm.prank(funder);
        token.approve(address(specificFundingManager), amount2);

        vm.expectEmit(true, true, true, false);
        emit SpecificMilestoneFundingAdded(id, amount1 + amount2, funder);

        //Actually call function
        vm.prank(funder);
        //Check if return value is correct
        assertTrue(
            specificFundingManager.fundSpecificMilestone(id, amount2)
                == amount1 + amount2
        );

        //Check if Array contains funder address
        assertTrue(
            fundersContainAddress(
                funder,
                specificFundingManager.getFunderAddressesForMilestoneId(id)
            )
        );

        //Check if Milestone Funding Amount is correctly updated
        assertTrue(
            specificFundingManager.getFunderAmountForMilestoneId(id)
                == amount1 + amount2
        );

        //Check if Funder Amount is correctly updated
        assertTrue(
            specificFundingManager.getFundingAmountForMilestoneIdAndAddress(
                id, funder
            ) == amount1 + amount2
        );

        //Check if token balances updated accordingly
        assertTrue(token.balanceOf(funder) == 0);
        assertTrue(
            token.balanceOf(address(specificFundingManager))
                == amount1 + amount2
        );
    }

    function testFundSpecificMilestoneModifier(uint id) public {
        //Modifier positions
        //validAmount
        vm.expectRevert(
            ISpecificFundingManager
                .Module__ISpecificFundingManager__InvalidAmount
                .selector
        );
        specificFundingManager.fundSpecificMilestone(id, 0);

        //allowanceHighEnough
        token.mint(Alice, 1);

        vm.expectRevert(
            ISpecificFundingManager
                .Module__ISpecificFundingManager__AllowanceNotHighEnough
                .selector
        );

        vm.prank(Alice);
        specificFundingManager.fundSpecificMilestone(id, 1);

        //fundingNotCollected
        vm.prank(milestoneModule);
        specificFundingManager.collectFunding(id, 1);

        vm.expectRevert(
            ISpecificFundingManager
                .Module__ISpecificFundingManager__FundingAlreadyCollected
                .selector
        );

        vm.prank(Alice);
        specificFundingManager.fundSpecificMilestone(id, 1);
    }

    //withdrawSpecificMilestoneFunding()

    function testWithdrawSpecificMilestoneFunding(
        uint id,
        uint amount,
        uint firstWithdrawal,
        address funder
    ) public {
        vm.assume(funder != address(0));
        amount = bound(amount, 2 ** 64 + 1, 2 ** 128); //Reasonable high number for testing
        firstWithdrawal = bound(firstWithdrawal, 1, 2 ** 64); //Reasonable high number for testing

        fundSpecificMilestone(id, funder, amount);

        //Main functionality

        vm.expectEmit(true, true, true, false);
        emit SpecificMilestoneFundingWithdrawn(
            id, amount - firstWithdrawal, funder
            );

        //Actually call function
        vm.prank(funder);
        //Check if return value is correct
        assertTrue(
            specificFundingManager.withdrawSpecificMilestoneFunding(
                id, firstWithdrawal
            ) == amount - firstWithdrawal
        );

        //Check if Array contains funder address
        assertTrue(
            fundersContainAddress(
                funder,
                specificFundingManager.getFunderAddressesForMilestoneId(id)
            )
        );

        //Check if Milestone Funding Amount is correctly updated
        assertTrue(
            specificFundingManager.getFunderAmountForMilestoneId(id)
                == amount - firstWithdrawal
        );

        //Check if Funder Amount is correctly updated
        assertTrue(
            specificFundingManager.getFundingAmountForMilestoneIdAndAddress(
                id, funder
            ) == amount - firstWithdrawal
        );

        //Check if token balances updated accordingly
        assertTrue(token.balanceOf(funder) == firstWithdrawal);
        assertTrue(
            token.balanceOf(address(specificFundingManager))
                == amount - firstWithdrawal
        );

        vm.expectEmit(true, true, false, false);
        emit SpecificMilestoneFundingRemoved(id, funder);

        //Actually call function
        vm.prank(funder);
        //Check if return value is correct
        assertTrue(
            specificFundingManager.withdrawSpecificMilestoneFunding(
                id, amount - firstWithdrawal
            ) == 0
        );

        //Check if Array does not contain funder address
        assertFalse(
            fundersContainAddress(
                funder,
                specificFundingManager.getFunderAddressesForMilestoneId(id)
            )
        );

        //Check if Milestone Funding Amount is correctly updated
        assertTrue(
            specificFundingManager.getFunderAmountForMilestoneId(id) == 0
        );

        //Check if Funder Amount is correctly updated
        assertTrue(
            specificFundingManager.getFundingAmountForMilestoneIdAndAddress(
                id, funder
            ) == 0
        );

        //Check if token balances updated accordingly
        assertTrue(token.balanceOf(funder) == amount);
        assertTrue(token.balanceOf(address(specificFundingManager)) == 0);
    }

    function testWithdrawSpecificMilestoneFundingModifier(uint id) public {
        //Modifier positions
        //validAmount
        vm.expectRevert(
            ISpecificFundingManager
                .Module__ISpecificFundingManager__InvalidAmount
                .selector
        );
        specificFundingManager.withdrawSpecificMilestoneFunding(id, 0);

        //validWithdrawAmount
        fundSpecificMilestone(id, Alice, 1);

        vm.expectRevert(
            ISpecificFundingManager
                .Module__ISpecificFundingManager__InvalidWithdrawAmount
                .selector
        );

        vm.prank(Alice);
        specificFundingManager.withdrawSpecificMilestoneFunding(id, 2);
    }

    //--------------------------------------------------------------------------
    // Helper - Functions

    function fundSpecificMilestone(uint id, address funder, uint amount)
        private
    {
        token.mint(funder, amount);
        vm.prank(funder);
        token.approve(address(specificFundingManager), amount);

        vm.prank(funder);
        specificFundingManager.fundSpecificMilestone(id, amount);
    }

    function fundersContainAddress(address adr, address[] memory funders)
        private
        returns (bool)
    {
        uint length = funders.length;
        for (uint i; i < length; ++i) {
            if (funders[i] == adr) {
                return true;
            }
        }

        return false;
    }

    // =========================================================================
}
