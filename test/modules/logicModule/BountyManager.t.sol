// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

//Internal Dependencies
import {ModuleTest, IModule, IProposal} from "test/modules/ModuleTest.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// SuT
import {
    BountyManager,
    IBountyManager,
    IPaymentClient
} from "src/modules/logicModule/BountyManager.sol";

contract BountyManagerTest is ModuleTest {
    // SuT
    BountyManager bountyManager;

    uint private constant _SENTINEL = type(uint).max;

    IBountyManager.Contributor ALICE =
        IBountyManager.Contributor(address(0xA11CE), 50_000_000);
    IBountyManager.Contributor BOB =
        IBountyManager.Contributor(address(0x606), 50_000_000);
    IBountyManager.Contributor[] DEFAULT_CONTRIBUTORS;

    event BountyAdded(
        uint indexed id,
        IBountyManager.Contributor[] indexed contributors,
        bytes indexed details
    );
    /// @notice Event emitted when a Bounty got updated.
    event BountyUpdated(
        uint indexed id,
        IBountyManager.Contributor[] indexed contributors,
        bytes indexed details
    );

    event BountyRemoved(uint indexed id);
    event BountyVerified(uint indexed id);

    function setUp() public {
        //Add Module to Mock Proposal
        address impl = address(new BountyManager());
        bountyManager = BountyManager(Clones.clone(impl));

        _setUpProposal(bountyManager);

        _authorizer.setIsAuthorized(address(this), true);

        DEFAULT_CONTRIBUTORS.push(ALICE);
        DEFAULT_CONTRIBUTORS.push(BOB);

        bountyManager.init(_proposal, _METADATA, bytes(""));
    }

    //--------------------------------------------------------------------------
    // Test: Initialization

    //This function also tests all the getters
    function testInit() public override(ModuleTest) {}

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        bountyManager.init(_proposal, _METADATA, bytes(""));
    }

    //--------------------------------------------------------------------------
    // Modifier

    function testValidId(uint usedIds, uint id) public {
        usedIds = bound(usedIds, 0, 1000);

        uint[] memory ids = bountyManager.listBountyIds();
        for (uint i = 0; i < ids.length; i++) {
            console.log(ids[i]);
        }

        for (uint i; i < usedIds; i++) {
            bountyManager.addBounty(DEFAULT_CONTRIBUTORS, bytes(""));
        }

        ids = bountyManager.listBountyIds();
        for (uint i = 0; i < ids.length; i++) {
            console.log(ids[i]);
        }

        if (id > usedIds || id == 0) {
            vm.expectRevert(
                IBountyManager.Module__BountyManager__InvalidBountyId.selector
            );
        }

        bountyManager.getBountyInformation(id);
    }

    function testValidContributors(
        address[] memory addrs,
        uint[] memory amounts
    ) public {
        uint length = addrs.length;
        vm.assume(length <= 50); //reasonable size
        vm.assume(length <= amounts.length);

        address adr;
        uint amnt;
        bool invalid = false;
        IBountyManager.Contributor[] memory contribs =
            new IBountyManager.Contributor[](length);

        if (length == 0) {
            vm.expectRevert(
                IBountyManager
                    .Module__BountyManager__InvalidContributors
                    .selector
            );

            bountyManager.addBounty(contribs, bytes(""));
        } else {
            for (uint i; i < length; i++) {
                adr = addrs[i];
                amnt = amounts[i];
                if (
                    amnt == 0 || adr == address(0)
                        || adr == address(bountyManager)
                        || adr == address(_proposal)
                ) invalid = true;

                contribs[i] = IBountyManager.Contributor({
                    addr: addrs[i],
                    bountyAmount: amounts[i]
                });
            }

            if (invalid) {
                vm.expectRevert(
                    IBountyManager
                        .Module__BountyManager__InvalidContributors
                        .selector
                );
            }

            bountyManager.addBounty(contribs, bytes(""));
        }
    }

    function testNotVerified() public {
        //@todo after verified is done
    }

    //--------------------------------------------------------------------------
    // Getter
    // Just test if Modifier is in position, because otherwise trivial

    function testGetRecurringPaymentInformationModifierInPosition() public {
        vm.expectRevert(
            IBountyManager.Module__BountyManager__InvalidBountyId.selector
        );
        bountyManager.getBountyInformation(0);
    }

    //--------------------------------------------------------------------------
    // Mutating Functions

    //-----------------------------------------
    //AddRecurringPayment

    /* function testAddRecurringPayment(
        uint seed,
        uint amount,
        uint startEpoch,
        address recipient
    ) public {
        reasonableWarpAndInit(seed);

        //Assume correct inputs
        vm.assume(
            recipient != address(0)
                && recipient != address(recurringPaymentManager)
        );
        amount = bound(amount, 1, type(uint).max);
        uint currentEpoch = recurringPaymentManager.getCurrentEpoch();
        startEpoch = bound(startEpoch, currentEpoch, type(uint).max);

        vm.expectEmit(true, true, true, true);
        emit RecurringPaymentAdded(
            1, //Id starts at 1
            amount,
            startEpoch,
            startEpoch - 1, //lastTriggeredEpoch has to be startEpoch - 1
            recipient
        );
        recurringPaymentManager.addRecurringPayment(
            amount, startEpoch, recipient
        );

        assertEqualRecurringPayment(
            1, amount, startEpoch, startEpoch - 1, recipient
        );

        //Check for multiple Adds
        uint id;
        uint length = bound(amount, 1, 30); //Reasonable amount
        for (uint i = 2; i < length + 2; i++) {
            vm.expectEmit(true, true, true, true);
            emit RecurringPaymentAdded(
                i, //Id starts at 1
                1,
                currentEpoch,
                currentEpoch - 1, //lastTriggeredEpoch has to be startEpoch - 1
                address(0xBEEF)
            );
            id = recurringPaymentManager.addRecurringPayment(
                1, currentEpoch, address(0xBEEF)
            );
            assertEq(id, i); //Maybe a bit overtested, that id is correct but ¯\_(ツ)_/¯
            assertEqualRecurringPayment(
                i, 1, currentEpoch, currentEpoch - 1, address(0xBEEF)
            );
        }
    }

    function testAddRecurringPaymentModifierInPosition() public {
        //Init Module
        recurringPaymentManager.init(_proposal, _METADATA, abi.encode(1 weeks));

        //Warp to a reasonable time
        vm.warp(2 weeks);

        //onlyAuthorizedOrManager
        vm.prank(address(0xBEEF)); //Not Authorized

        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        recurringPaymentManager.addRecurringPayment(1, 2 weeks, address(0xBEEF));

        //validAmount
        vm.expectRevert(
            IPaymentClient.Module__PaymentClient__InvalidAmount.selector
        );
        recurringPaymentManager.addRecurringPayment(0, 2 weeks, address(0xBEEF));

        //validStartEpoch

        vm.expectRevert(
            IRecurringPaymentManager
                .Module__RecurringPaymentManager__InvalidStartEpoch
                .selector
        );
        recurringPaymentManager.addRecurringPayment(1, 0, address(0xBEEF));

        //validRecipient

        vm.expectRevert(
            IPaymentClient.Module__PaymentClient__InvalidRecipient.selector
        );
        recurringPaymentManager.addRecurringPayment(1, 2 weeks, address(0));
    } */

    //--------------------------------------------------------------------------
    // Helper

    function createValidContributors(
        address[] memory addrs,
        uint[] memory amounts
    ) internal view returns (IBountyManager.Contributor[] memory) {
        uint length = addrs.length;
        vm.assume(length == amounts.length);
        address a;

        for (uint i; i < length; i++) {
            //Convert address(0) to address (1)
            a = addrs[i];
            if (
                a == address(0) || a == address(bountyManager)
                    || a == address(_proposal)
            ) addrs[i] = address(0x1);

            //Convert amount 0 to 1
            if (amounts[i] == 0) {
                amounts[i] = 1;
            }
        }

        IBountyManager.Contributor[] memory contribs =
            new IBountyManager.Contributor[](length);
        for (uint i; i < length; i++) {
            contribs[i] = IBountyManager.Contributor({
                addr: addrs[i],
                bountyAmount: amounts[i]
            });
        }
        return contribs;
    }
}
