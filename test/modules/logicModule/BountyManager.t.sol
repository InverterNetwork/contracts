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
        uint indexed bountyId,
        uint indexed minimumPayoutAmount,
        uint indexed maximumPayoutAmount,
        bytes details
    );

    event BountyUpdated(uint indexed bountyId, bytes indexed details);

    event BountyLocked(uint indexed bountyId);

    event ClaimAdded(
        uint indexed claimId,
        uint indexed bountyId,
        IBountyManager.Contributor[] indexed contributors,
        bytes details
    );

    event ClaimContributorsUpdated(
        uint indexed claimId, IBountyManager.Contributor[] indexed contributors
    );

    event ClaimDetailsUpdated(uint indexed claimId, bytes details);

    event ClaimVerified(uint indexed BountyId, uint indexed ClaimId);

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

    //@todo Reminder that this will be moved into the ModuleTest Contract at a later point of time
    //note: if someone has a better idea to test this, it would be most welcome
    function testOnlyRole(bool authorized) public {
        if (!authorized) {
            _authorizer.setIsAuthorized(address(this), false);
            //onlyBountyAdmin
            vm.expectRevert(
                abi.encodeWithSelector(
                    IBountyManager.Module__BountyManager__OnlyRole.selector,
                    IBountyManager.Roles.BountyAdmin,
                    address(bountyManager)
                )
            );
        }
        bountyManager.addBounty(1, 2, bytes(""));
    }

    function testOnlyClaimContributor(
        address[] memory addrs,
        uint[] memory amounts,
        address addr
    ) public {
        addrs = cutArray(50, addrs); //cut to reasonable size
        uint length = addrs.length;
        vm.assume(length <= amounts.length);

        ///Restrict amounts to 20_000 to test properly(doesnt overflow)
        amounts = cutAmounts(20_000_000_000_000, amounts);
        //=> maxAmount = 20_000_000_000_000 * 50 = 1_000_000_000_000_000
        uint maxAmount = 1_000_000_000_000_000;
        IBountyManager.Contributor[] memory contribs =
            createValidContributors(addrs, amounts);

        bountyManager.addBounty(1, maxAmount, bytes(""));

        bountyManager.addClaim(1, contribs, bytes(""));

        if (!contains(contribs, addr)) {
            vm.expectRevert(
                IBountyManager
                    .Module__BountyManager__OnlyClaimContributor
                    .selector
            );
        }
        vm.prank(addr);
        bountyManager.updateClaimDetails(2, bytes("1"));
    }

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

    function testValidContributorsForBounty(
        uint minimumPayoutAmount,
        uint maximumPayoutAmount,
        address[] memory addrs,
        uint[] memory amounts
    ) public {
        uint length = addrs.length;
        vm.assume(length <= 50); //reasonable size
        vm.assume(length <= amounts.length);

        minimumPayoutAmount = bound(minimumPayoutAmount, 1, type(uint).max);
        maximumPayoutAmount = bound(maximumPayoutAmount, 1, type(uint).max);
        vm.assume(minimumPayoutAmount <= maximumPayoutAmount);

        //Restrict amounts to 20_000 to test properly(doesnt overflow)
        amounts = cutAmounts(20_000_000_000_000, amounts);

        //ID is 1
        bountyManager.addBounty(
            minimumPayoutAmount, maximumPayoutAmount, bytes("")
        );

        IBountyManager.Contributor[] memory contribs =
            new IBountyManager.Contributor[](length);

        if (length == 0) {
            vm.expectRevert(
                IBountyManager
                    .Module__BountyManager__InvalidContributorsLength
                    .selector
            );

            bountyManager.addClaim(1, contribs, bytes(""));
        } else {
            for (uint i; i < length; i++) {
                contribs[i] = IBountyManager.Contributor({
                    addr: addrs[i],
                    claimAmount: amounts[i]
                });
            }

            uint totalAmount;
            IBountyManager.Contributor memory currentContrib;
            //Check if it reached the end -> ClaimExceedsGivenPayoutAmounts will only be checked if it ran through everything
            bool reachedEnd;

            for (uint i; i < length; i++) {
                currentContrib = contribs[i];

                totalAmount += currentContrib.claimAmount;

                if (currentContrib.claimAmount == 0) {
                    vm.expectRevert(
                        IBountyManager
                            .Module__BountyManager__InvalidContributorAmount
                            .selector
                    );
                    break;
                }

                if (
                    currentContrib.addr == address(0)
                        || currentContrib.addr == address(bountyManager)
                        || currentContrib.addr == address(_proposal)
                ) {
                    vm.expectRevert(
                        IBountyManager
                            .Module__BountyManager__InvalidContributorAddress
                            .selector
                    );
                    break;
                }

                if (i == length - 1) {
                    reachedEnd = true;
                }
            }

            if (
                reachedEnd
                    && (
                        totalAmount > maximumPayoutAmount
                            || totalAmount < minimumPayoutAmount
                    )
            ) {
                vm.expectRevert(
                    IBountyManager
                        .Module__BountyManager__ClaimExceedsGivenPayoutAmounts
                        .selector
                );
            }

            bountyManager.addClaim(1, contribs, bytes(""));
        }
    }

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
                    .Module__BountyManager__ClaimNotBelongingToBounty
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

    //--------------------------------------------------------------------------
    // Getter
    // Just test if Modifier is in position, because otherwise trivial

    function testGetBountyInformationModifierInPosition() public {
        vm.expectRevert(
            IBountyManager.Module__BountyManager__InvalidBountyId.selector
        );
        bountyManager.getBountyInformation(0);
    }

    function testGetClaimInformationModifierInPosition() public {
        vm.expectRevert(
            IBountyManager.Module__BountyManager__InvalidClaimId.selector
        );
        bountyManager.getClaimInformation(0);
    }

    //--------------------------------------------------------------------------
    // Mutating Functions

    //-----------------------------------------
    //AddBounty

    function testAddBounty(
        uint testAmount,
        uint minimumPayoutAmount,
        uint maximumPayoutAmount,
        bytes calldata details
    ) public {
        testAmount = bound(testAmount, 1, 30); //Reasonable Amount
        minimumPayoutAmount = bound(minimumPayoutAmount, 1, type(uint).max);
        maximumPayoutAmount = bound(maximumPayoutAmount, 1, type(uint).max);
        vm.assume(minimumPayoutAmount <= maximumPayoutAmount);

        uint id;
        for (uint i; i < testAmount; i++) {
            vm.expectEmit(true, true, true, true);
            emit BountyAdded(
                i + 1, minimumPayoutAmount, maximumPayoutAmount, details
            );

            id = bountyManager.addBounty(
                minimumPayoutAmount, maximumPayoutAmount, details
            );

            assertEqualBounty(
                id, minimumPayoutAmount, maximumPayoutAmount, details, 0
            );
        }
    }

    function testAddBountyModifierInPosition() public {
        //validPayoutAmounts
        vm.expectRevert(
            IBountyManager.Module__BountyManager__InvalidPayoutAmounts.selector
        );
        bountyManager.addBounty(0, 0, bytes(""));

        //Set this address to not authorized to test the roles correctly
        _authorizer.setIsAuthorized(address(this), false);

        //onlyBountyAdmin
        vm.expectRevert(
            abi.encodeWithSelector(
                IBountyManager.Module__BountyManager__OnlyRole.selector,
                IBountyManager.Roles.BountyAdmin,
                address(bountyManager)
            )
        );
        bountyManager.addBounty(0, 0, bytes(""));
    }

    //-----------------------------------------
    //AddClaim

    function testAddClaim(
        uint times,
        address[] memory addrs,
        uint[] memory amounts,
        bytes calldata details
    ) public {
        addrs = cutArray(50, addrs); //cut to reasonable size
        uint length = addrs.length;
        vm.assume(length <= amounts.length);
        times = bound(times, 1, 50);

        ///Restrict amounts to 20_000 to test properly(doesnt overflow)
        amounts = cutAmounts(20_000_000_000_000, amounts);
        //=> maxAmount = 20_000_000_000_000 * 50 = 1_000_000_000_000_000
        uint maxAmount = 1_000_000_000_000_000;
        IBountyManager.Contributor[] memory contribs =
            createValidContributors(addrs, amounts);

        bountyManager.addBounty(1, maxAmount, bytes(""));

        uint id;

        for (uint i = 0; i < times; i++) {
            vm.expectEmit(true, true, true, true);
            //id starts at 2 because the id counter starts at 1 and addBounty increases it by 1 again
            emit ClaimAdded(i + 2, 1, contribs, details);

            id = bountyManager.addClaim(1, contribs, details);
            assertEqualClaim(id, 1, contribs, details);

            //Assert set is filled correctly
            for (uint j; j < length; j++) {
                assertContributorAddressToClaimIdsContains(contribs[j].addr, id);
            }
        }
    }

    function testAddClaimModifierInPosition() public {
        bountyManager.addBounty(1, 1, bytes(""));

        //validBountyId
        vm.expectRevert(
            IBountyManager.Module__BountyManager__InvalidBountyId.selector
        );
        bountyManager.addClaim(0, DEFAULT_CONTRIBUTORS, bytes(""));

        //validContributorsForBounty
        vm.expectRevert(
            IBountyManager
                .Module__BountyManager__InvalidContributorAmount
                .selector
        );
        bountyManager.addClaim(1, INVALID_CONTRIBUTORS, bytes(""));

        bountyManager.lockBounty(1);

        //notClaimed
        vm.expectRevert(
            IBountyManager.Module__BountyManager__BountyAlreadyClaimed.selector
        );
        bountyManager.addClaim(1, DEFAULT_CONTRIBUTORS, bytes(""));

        //Set this address to not authorized to test the roles correctly
        _authorizer.setIsAuthorized(address(this), false);

        //onlyClaimAdmin
        vm.expectRevert(
            abi.encodeWithSelector(
                IBountyManager.Module__BountyManager__OnlyRole.selector,
                IBountyManager.Roles.ClaimAdmin,
                address(bountyManager)
            )
        );
        bountyManager.addClaim(0, DEFAULT_CONTRIBUTORS, bytes(""));
    }

    //-----------------------------------------
    //UpdateBounty

    function testUpdateBounty(bytes calldata details) public {
        uint id = bountyManager.addBounty(1, 1, bytes(""));

        vm.expectEmit(true, true, true, true);
        emit BountyUpdated(1, details);

        bountyManager.updateBounty(id, details);

        assertEqualBounty(id, 1, 1, details, 0);
    }

    function testUpdateBountyModifierInPosition() public {
        bountyManager.addBounty(1, 1, bytes(""));

        //validBountyId
        vm.expectRevert(
            IBountyManager.Module__BountyManager__InvalidBountyId.selector
        );
        bountyManager.updateBounty(0, bytes(""));

        //Set this address to not authorized to test the roles correctly
        _authorizer.setIsAuthorized(address(this), false);

        //onlyBountyAdmin
        vm.expectRevert(
            abi.encodeWithSelector(
                IBountyManager.Module__BountyManager__OnlyRole.selector,
                IBountyManager.Roles.BountyAdmin,
                address(bountyManager)
            )
        );
        bountyManager.updateBounty(0, bytes(""));
    }

    //-----------------------------------------
    //UpdateBounty

    function testLockBounty() public {
        uint id = bountyManager.addBounty(1, 1, bytes(""));

        vm.expectEmit(true, true, true, true);
        emit BountyLocked(1);

        bountyManager.lockBounty(1);

        assertEqualBounty(id, 1, 1, bytes(""), type(uint).max);
    }

    function testLockBountyModifierInPosition() public {
        bountyManager.addBounty(1, 1, bytes(""));

        //validBountyId
        vm.expectRevert(
            IBountyManager.Module__BountyManager__InvalidBountyId.selector
        );
        bountyManager.lockBounty(0);

        //bountyAlreadyClaimed
        bountyManager.lockBounty(1);
        vm.expectRevert(
            IBountyManager.Module__BountyManager__BountyAlreadyClaimed.selector
        );
        bountyManager.lockBounty(1);

        //Set this address to not authorized to test the roles correctly
        _authorizer.setIsAuthorized(address(this), false);

        //onlyBountyAdmin
        vm.expectRevert(
            abi.encodeWithSelector(
                IBountyManager.Module__BountyManager__OnlyRole.selector,
                IBountyManager.Roles.BountyAdmin,
                address(bountyManager)
            )
        );
        bountyManager.lockBounty(0);
    }

    //-----------------------------------------
    //UpdateClaimContributors

    function testUpdateClaimContributors(
        address[] memory addrs,
        uint[] memory amounts
    ) public {
        addrs = cutArray(50, addrs); //cut to reasonable size
        uint length = addrs.length;
        vm.assume(length <= amounts.length);

        //Restrict amounts to 20_000 to test properly(doesnt overflow)
        amounts = cutAmounts(20_000_000_000_000, amounts);
        //=> maxAmount = 20_000_000_000_000 * 50 = 1_000_000_000_000_000
        uint maxAmount = 1_000_000_000_000_000;

        IBountyManager.Contributor[] memory contribs =
            createValidContributors(addrs, amounts);

        bountyManager.addBounty(1, maxAmount, bytes(""));
        uint id = bountyManager.addClaim(1, DEFAULT_CONTRIBUTORS, bytes(""));

        vm.expectEmit(true, true, true, true);
        emit ClaimContributorsUpdated(id, contribs);

        vm.prank(DEFAULT_CONTRIBUTORS[0].addr);
        bountyManager.updateClaimContributors(id, 1, contribs);

        assertEqualClaim(2, 1, contribs, bytes(""));

        //Check if default contributors are in the set
        //if not make sure their ClaimIds are removed
        if (!contains(contribs, DEFAULT_CONTRIBUTORS[0].addr)) {
            assertContributorAddressToClaimIdsContainsNot(
                DEFAULT_CONTRIBUTORS[0].addr, id
            );
        }
        if (!contains(contribs, DEFAULT_CONTRIBUTORS[1].addr)) {
            assertContributorAddressToClaimIdsContainsNot(
                DEFAULT_CONTRIBUTORS[0].addr, id
            );
        }

        //Assert set is filled correctly
        for (uint j; j < length; j++) {
            assertContributorAddressToClaimIdsContains(contribs[j].addr, id);
        }
    }

    function testUpdateClaimContributorsModifierInPosition() public {
        bountyManager.addBounty(1, 100_000_000, bytes(""));
        bountyManager.addClaim(1, DEFAULT_CONTRIBUTORS, bytes(""));

        vm.startPrank(DEFAULT_CONTRIBUTORS[0].addr);

        //validClaimId
        vm.expectRevert(
            IBountyManager.Module__BountyManager__InvalidClaimId.selector
        );
        bountyManager.updateClaimContributors(0, 1, DEFAULT_CONTRIBUTORS);

        //validBountyId
        vm.expectRevert(
            IBountyManager.Module__BountyManager__InvalidBountyId.selector
        );
        bountyManager.updateClaimContributors(2, 0, DEFAULT_CONTRIBUTORS);

        //validContributorsForBounty
        vm.expectRevert(
            IBountyManager
                .Module__BountyManager__InvalidContributorAmount
                .selector
        );
        bountyManager.updateClaimContributors(2, 1, INVALID_CONTRIBUTORS);

        vm.stopPrank();

        //onlyClaimContributor
        vm.expectRevert(
            IBountyManager.Module__BountyManager__OnlyClaimContributor.selector
        );
        bountyManager.updateClaimContributors(2, 1, DEFAULT_CONTRIBUTORS);
    }

    //-----------------------------------------
    //UpdateClaimDetails

    function testUpdateClaimDetails(bytes calldata details) public {
        bountyManager.addBounty(1, 100_000_000, bytes(""));
        bountyManager.addClaim(1, DEFAULT_CONTRIBUTORS, bytes(""));

        vm.expectEmit(true, true, true, true);
        emit ClaimDetailsUpdated(2, details);
        vm.prank(DEFAULT_CONTRIBUTORS[0].addr);
        bountyManager.updateClaimDetails(2, details);

        assertEqualClaim(2, 1, DEFAULT_CONTRIBUTORS, details);
    }

    function testUpdateClaimDetailsModifierInPosition() public {
        bountyManager.addBounty(1, 100_000_000, bytes(""));
        bountyManager.addClaim(1, DEFAULT_CONTRIBUTORS, bytes(""));

        //validClaimId
        vm.expectRevert(
            IBountyManager.Module__BountyManager__InvalidClaimId.selector
        );
        bountyManager.updateClaimDetails(0, bytes(""));

        //Set this address to not authorized to test the roles correctly
        _authorizer.setIsAuthorized(address(this), false);

        //onlyClaimContributor
        vm.expectRevert(
            IBountyManager.Module__BountyManager__OnlyClaimContributor.selector
        );
        bountyManager.updateClaimDetails(2, bytes(""));
    }

    //-----------------------------------------
    //verifyClaim

    function testVerifyClaim(
        address[] memory addrs,
        uint[] memory amounts,
        bytes calldata details
    ) public {
        addrs = cutArray(50, addrs); //cut to reasonable size
        uint length = addrs.length;
        vm.assume(length <= amounts.length);

        //Restrict amounts to 20_000_000_000_000 to test properly(doesnt overflow)
        amounts = cutAmounts(20_000_000_000_000, amounts);
        //=> maxAmount = 20_000_000_000_000 * 50 = 1_000_000_000_000_000
        uint maxAmount = 1_000_000_000_000_000;
        _token.mint(address(_fundingManager), maxAmount);

        IBountyManager.Contributor[] memory contribs =
            createValidContributors(addrs, amounts);

        uint bountyId = bountyManager.addBounty(1, maxAmount, details);
        uint claimId = bountyManager.addClaim(bountyId, contribs, details);

        vm.expectEmit(true, true, true, true);
        emit ClaimVerified(claimId, bountyId);

        bountyManager.verifyClaim(claimId, bountyId);

        IPaymentClient.PaymentOrder[] memory orders =
            bountyManager.paymentOrders();

        assertEq(length, orders.length);

        //Amount of tokens that should be in the RecurringPaymentManager
        uint totalAmount;

        //Amount of tokens in a single order
        uint claimAmount;

        for (uint i = 0; i < length; i++) {
            claimAmount = contribs[i].claimAmount;
            totalAmount += claimAmount;

            assertEq(orders[i].recipient, contribs[i].addr);

            assertEq(orders[i].amount, claimAmount);
            assertEq(orders[i].createdAt, block.timestamp);

            assertEq(orders[i].dueTo, block.timestamp);
        }

        // Check that bountyManager's token balance is sufficient for the
        // payment orders by comparing it with the total amount of orders made
        assertTrue(_token.balanceOf(address(bountyManager)) == totalAmount);

        assertEqualBounty(bountyId, 1, maxAmount, details, claimId); //Verified has to be true
    }

    function testVerifyClaimModifierInPosition() public {
        bountyManager.addBounty(1, 100_000_000, bytes(""));
        bountyManager.addClaim(1, DEFAULT_CONTRIBUTORS, bytes("")); //Id 2

        bountyManager.addBounty(1, 100_000_000, bytes(""));
        bountyManager.addClaim(3, DEFAULT_CONTRIBUTORS, bytes("")); //Id 4

        //validClaimId
        vm.expectRevert(
            IBountyManager.Module__BountyManager__InvalidClaimId.selector
        );
        bountyManager.verifyClaim(0, 1);

        //validBountyId
        vm.expectRevert(
            IBountyManager.Module__BountyManager__InvalidBountyId.selector
        );
        bountyManager.verifyClaim(2, 0);

        //accordingClaimToBounty
        vm.expectRevert(
            IBountyManager
                .Module__BountyManager__ClaimNotBelongingToBounty
                .selector
        );
        bountyManager.verifyClaim(2, 3);

        _token.mint(address(_fundingManager), 100_000_000);
        bountyManager.verifyClaim(2, 1);

        //notClaimed
        vm.expectRevert(
            IBountyManager.Module__BountyManager__BountyAlreadyClaimed.selector
        );
        bountyManager.verifyClaim(2, 1);

        //Set this address to not authorized to test the roles correctly
        _authorizer.setIsAuthorized(address(this), false);

        //onlyVerifyAdmin
        vm.expectRevert(
            abi.encodeWithSelector(
                IBountyManager.Module__BountyManager__OnlyRole.selector,
                IBountyManager.Roles.VerifyAdmin,
                address(bountyManager)
            )
        );
        bountyManager.verifyClaim(0, 1);
    }

    //--------------------------------------------------------------------------
    // Role Functions

    //@todo trivial to be removed as soon as the functionality is moved to RoleAuthorizer
    function testGrantBountyAdminRole(address addr) public {
        bountyManager.grantBountyAdminRole(addr);

        vm.prank(address(bountyManager));
        bool isAuthorized = _authorizer.isAuthorized(
            uint8(IBountyManager.Roles.BountyAdmin), addr
        );
        assertTrue(isAuthorized);
    }

    function testRevokeBountyAdminRole(address addr) public {
        bountyManager.grantBountyAdminRole(addr);
        bountyManager.revokeBountyAdminRole(addr);

        vm.prank(address(bountyManager));
        bool isAuthorized = _authorizer.isAuthorized(
            uint8(IBountyManager.Roles.BountyAdmin), addr
        );
        assertFalse(isAuthorized);
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

    function cutAmounts(uint maxAmount, uint[] memory amounts)
        internal
        pure
        returns (uint[] memory)
    {
        uint length = amounts.length;
        vm.assume(length > 0); //Array has to be at least 1

        for (uint i = 0; i < length; i++) {
            if (amounts[i] > maxAmount) {
                amounts[i] = maxAmount;
            }
        }
        return amounts;
    }

    function createPotentiallyInvalidContributors(
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
                claimAmount: amounts[i]
            });
        }
        return contribs;
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
        }

        IBountyManager.Contributor[] memory contribs =
            new IBountyManager.Contributor[](length);
        for (uint i; i < length; i++) {
            contribs[i] = IBountyManager.Contributor({
                addr: addrs[i],
                claimAmount: amounts[i]
            });
        }
        return contribs;
    }

    function assertEqualBounty(
        uint idToProve,
        uint minimumPayoutAmountToTest,
        uint maximumPayoutAmountToTest,
        bytes memory detailsToTest,
        uint claimedByToTest
    ) internal {
        IBountyManager.Bounty memory currentBounty =
            bountyManager.getBountyInformation(idToProve);

        assertEq(currentBounty.minimumPayoutAmount, minimumPayoutAmountToTest);
        assertEq(currentBounty.maximumPayoutAmount, maximumPayoutAmountToTest);
        assertEq(currentBounty.details, detailsToTest);
        assertEq(currentBounty.claimedBy, claimedByToTest);
    }

    function assertEqualClaim(
        uint idToProve,
        uint bountyidToTest,
        IBountyManager.Contributor[] memory contribsToTest,
        bytes memory detailsToTest
    ) internal {
        IBountyManager.Claim memory currentClaim =
            bountyManager.getClaimInformation(idToProve);

        IBountyManager.Contributor[] memory currentContribs =
            currentClaim.contributors;

        uint length = currentContribs.length;

        assertEq(currentClaim.bountyId, bountyidToTest);
        assertEq(length, contribsToTest.length);
        for (uint i = 0; i < length; ++i) {
            assertEq(currentContribs[i].addr, contribsToTest[i].addr);
            assertEq(
                currentContribs[i].claimAmount, contribsToTest[i].claimAmount
            );
        }
        assertEq(currentClaim.details, detailsToTest);
    }

    function assertContributorAddressToClaimIdsContains(
        address contribAddress,
        uint claimId
    ) internal {
        uint[] memory claimIds =
            bountyManager.listClaimIdsForContributorAddress(contribAddress);
        uint length = claimIds.length;
        bool found;
        for (uint i = 0; i < length; i++) {
            if (claimIds[i] == claimId) {
                found = true;
                break;
            }
        }
        assertTrue(found);
    }

    function assertContributorAddressToClaimIdsContainsNot(
        address contribAddress,
        uint claimId
    ) internal {
        uint[] memory claimIds =
            bountyManager.listClaimIdsForContributorAddress(contribAddress);
        uint length = claimIds.length;
        bool found;
        for (uint i = 0; i < length; i++) {
            if (claimIds[i] == claimId) {
                found = true;
                break;
            }
        }
        assertFalse(found);
    }

    function contains(
        BountyManager.Contributor[] memory searchThrough,
        address addr
    ) internal pure returns (bool) {
        uint lengthSearchFor = searchThrough.length;
        for (uint i = 0; i < lengthSearchFor; i++) {
            if (searchThrough[i].addr == addr) {
                return true;
            }
        }
        return false;
    }
}
