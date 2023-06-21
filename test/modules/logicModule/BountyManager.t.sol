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
    IBountyManager.Contributor BEEF =
        IBountyManager.Contributor(address(0xBEEF), 0);
    IBountyManager.Contributor[] DEFAULT_CONTRIBUTORS;
    IBountyManager.Contributor[] INVALID_CONTRIBUTORS;

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

        INVALID_CONTRIBUTORS.push(BEEF);

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

    function testValidPayoutAmounts(
        uint minimumPayoutAmount,
        uint maximumPayoutAmount
    ) public {
        if (
            minimumPayoutAmount == 0 || maximumPayoutAmount == 0
                || maximumPayoutAmount < minimumPayoutAmount
        ) {
            vm.expectRevert(
                IBountyManager
                    .Module__BountyManager__InvalidPayoutAmounts
                    .selector
            );
        }

        bountyManager.addBounty(
            minimumPayoutAmount, maximumPayoutAmount, bytes("")
        );
    }

    function testValidBountyId(uint usedIds, uint id) public {
        usedIds = bound(usedIds, 0, 1000);

        for (uint i; i < usedIds; i++) {
            bountyManager.addBounty(1, 1, bytes(""));
        }

        if (id > usedIds || id == 0) {
            vm.expectRevert(
                IBountyManager.Module__BountyManager__InvalidBountyId.selector
            );
        }

        bountyManager.getBountyInformation(id);
    }

    function testValidClaimId(uint usedIds, uint id) public {
        usedIds = bound(usedIds, 0, 1000);

        uint bountyId = bountyManager.addBounty(1, 100_000_000, bytes(""));

        for (uint i; i < usedIds; i++) {
            bountyManager.addClaim(bountyId, DEFAULT_CONTRIBUTORS, bytes(""));
        }

        if (id > usedIds + bountyId || id == 0 || id == bountyId) {
            vm.expectRevert(
                IBountyManager.Module__BountyManager__InvalidClaimId.selector
            );
        }

        bountyManager.getClaimInformation(id);
    }
    /* 
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
    } */

    function testAccordingClaimToBounty(uint usedIds, uint picker) public {
        _token.mint(address(_fundingManager), 100_000_000);

        usedIds = bound(usedIds, 1, 100);
        uint bountyId1 = bountyManager.addBounty(1, 100_000_000, bytes("")); //id 1
        uint bountyId2 = bountyManager.addBounty(1, 100_000_000, bytes("")); //id 2
        for (uint i; i < usedIds; i++) {
            bountyManager.addClaim(bountyId1, DEFAULT_CONTRIBUTORS, bytes("")); //ids should be odd numbers
            bountyManager.addClaim(bountyId2, DEFAULT_CONTRIBUTORS, bytes("")); //ids should be even numbers
        }

        picker = bound(picker, 3, usedIds + 2);
        if ((picker % 2) == 0) {
            vm.expectRevert(
                IBountyManager
                    .Module__BountyManager__NotAccordingClaimToBounty
                    .selector
            );
        }

        bountyManager.verifyClaim(picker, bountyId1);
    }

    function testNotClaimed(bool isVerified) public {
        _token.mint(address(_fundingManager), 100_000_000);

        uint bountyId = bountyManager.addBounty(1, 100_000_000, bytes(""));
        uint claimId =
            bountyManager.addClaim(bountyId, DEFAULT_CONTRIBUTORS, bytes(""));

        if (isVerified) {
            bountyManager.verifyClaim(claimId, bountyId);
            vm.expectRevert(
                IBountyManager
                    .Module__BountyManager__BountyAlreadyClaimed
                    .selector
            );
        }
        bountyManager.verifyClaim(claimId, bountyId);
    }

    /* 

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
    //AddBounty

    function testAddBounty(
        address[] memory addrs,
        uint[] memory amounts,
        bytes calldata details
    ) public {
        addrs = cutArray(50, addrs); //cut to reasonable size
        uint length = addrs.length;
        vm.assume(length <= amounts.length);

        IBountyManager.Contributor[] memory contribs =
            createValidContributors(addrs, amounts);

        uint id;

        for (uint i = 0; i < length; i++) {
            vm.expectEmit(true, true, true, true);
            emit BountyAdded(i + 1, contribs, details);

            id = bountyManager.addBounty(contribs, details);

            assertEqualBounty(id, contribs, details, false);
        }
    }

    function testAddBountyModifierInPosition() public {
        //@todo onlyRole

        //validContributors
        vm.expectRevert(
            IBountyManager.Module__BountyManager__InvalidContributors.selector
        );
        bountyManager.addBounty(INVALID_CONTRIBUTORS, bytes(""));
    }

    //-----------------------------------------
    //UpdateBounty

    function testUpdateBounty(
        address[] memory addrs,
        uint[] memory amounts,
        bytes calldata details
    ) public {
        addrs = cutArray(50, addrs); //cut to reasonable size
        uint length = addrs.length;
        vm.assume(length <= amounts.length);

        IBountyManager.Contributor[] memory contribs =
            createValidContributors(addrs, amounts);

        uint id = bountyManager.addBounty(DEFAULT_CONTRIBUTORS, bytes(""));

        vm.expectEmit(true, true, true, true);
        emit BountyUpdated(1, contribs, details);

        bountyManager.updateBounty(1, contribs, details);

        assertEqualBounty(id, contribs, details, false);
    }

    function testUpdateBountyModifierInPosition() public {
        //@todo onlyRole

        //validContributors
        vm.expectRevert(
            IBountyManager.Module__BountyManager__InvalidBountyId.selector
        );
        bountyManager.updateBounty(0, DEFAULT_CONTRIBUTORS, bytes(""));

        bountyManager.addBounty(DEFAULT_CONTRIBUTORS, bytes(""));

        //validContributors
        vm.expectRevert(
            IBountyManager.Module__BountyManager__InvalidContributors.selector
        );
        bountyManager.updateBounty(1, INVALID_CONTRIBUTORS, bytes(""));
    }

    //-----------------------------------------
    //VerifyBounty

    function testVerifyBounty(
        address[] memory addrs,
        uint[] memory amounts,
        bytes calldata details
    ) public {
        addrs = cutArray(5, addrs); //cut to reasonable size
        uint length = addrs.length;
        vm.assume(length <= amounts.length);

        IBountyManager.Contributor[] memory contribs =
            createValidContributors(addrs, amounts);

        uint id = bountyManager.addBounty(contribs, details);

        //createValidContributors restricts individual amounts to 1_000_000_000_000_000
        //In combination with max 50 contributors thats 50_000_000_000_000_000
        _token.mint(address(_fundingManager), 50_000_000_000_000_000);

        vm.expectEmit(true, true, true, true);
        emit BountyVerified(id);

        bountyManager.verifyBounty(id);

        IPaymentClient.PaymentOrder[] memory orders =
            bountyManager.paymentOrders();

        assertEq(length, orders.length);

        //Amount of tokens that should be in the RecurringPaymentManager
        uint totalAmount;

        //Amount of tokens in a single order
        uint bountyAmount;

        for (uint i = 0; i < length; i++) {
            bountyAmount = contribs[i].bountyAmount;
            totalAmount += bountyAmount;

            assertEq(orders[i].recipient, contribs[i].addr);

            assertEq(orders[i].amount, bountyAmount);
            assertEq(orders[i].createdAt, block.timestamp);

            assertEq(orders[i].dueTo, block.timestamp);
        }

        // Check that bountyManager's token balance is sufficient for the
        // payment orders by comparing it with the total amount of orders made
        assertTrue(_token.balanceOf(address(bountyManager)) == totalAmount);

        assertEqualBounty(id, contribs, details, true); //Verified has to be true
    }

    function testVerifyBountyModifierInPosition() public {
        //@todo onlyRole

        //validContributors
        vm.expectRevert(
            IBountyManager.Module__BountyManager__InvalidBountyId.selector
        );
        bountyManager.verifyBounty(0);

        //Create Bounty and verify it
        bountyManager.addBounty(DEFAULT_CONTRIBUTORS, bytes(""));

        _token.mint(address(_fundingManager), 100_000_000);
        bountyManager.verifyBounty(1);

        //@todo
        //validContributors
        vm.expectRevert(
            IBountyManager.Module__BountyManager__BountyAlreadyVerified.selector
        );
        bountyManager.verifyBounty(1);
    }

    //--------------------------------------------------------------------------
    // Helper

    function cutArray(uint size, address[] memory addrs)
        internal
        pure
        returns (address[] memory)
    {
        uint length = addrs.length;
        vm.assume(length > 0); //Array has to be at least 1

        if (length <= size) {
            return addrs;
        }

        address[] memory cutArry = new address[](size);
        for (uint i = 0; i < size - 1; i++) {
            cutArry[i] = addrs[i];
        }
        return cutArry;
    }

    function createValidContributors(
        address[] memory addrs,
        uint[] memory amounts
    ) internal view returns (IBountyManager.Contributor[] memory) {
        uint length = addrs.length;
        assert(length <= amounts.length);
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
            //If Higher than 1_000_000_000_000_000 convert to 1_000_000_000_000_000 //@note is that a reasonable amount?
            if (amounts[i] > 1_000_000_000_000_000) {
                amounts[i] = 1_000_000_000_000_000;
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

    function assertEqualBounty(
        uint idToProve,
        IBountyManager.Contributor[] memory contribsToTest,
        bytes calldata detailsToTest,
        bool verifiedToTest
    ) internal {
        IBountyManager.Bounty memory currentBounty =
            bountyManager.getBountyInformation(idToProve);

        IBountyManager.Contributor[] memory currentContribs =
            currentBounty.contributors;

        uint length = currentContribs.length;

        assertEq(length, contribsToTest.length);
        for (uint i = 0; i < length; ++i) {
            assertEq(currentContribs[i].addr, contribsToTest[i].addr);
            assertEq(
                currentContribs[i].bountyAmount, contribsToTest[i].bountyAmount
            );
        }
        assertEq(currentBounty.details, detailsToTest);
        assertEq(currentBounty.verified, verifiedToTest);
    } */
}
