// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";

// Internal Dependencies
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// SuT
import {
    LM_PC_Bounties_v1,
    ILM_PC_Bounties_v1,
    IERC20PaymentClientBase_v1
} from "@lm/LM_PC_Bounties_v1.sol";

import {LM_PC_Bounties_v1AccessMock} from
    "test/utils/mocks/modules/logicModules/LM_PC_Bounties_v1AccessMock.sol";

contract LM_PC_BountiesV1Test is ModuleTest {
    // SuT
    LM_PC_Bounties_v1AccessMock bountyManager;

    uint private constant _SENTINEL = type(uint).max;

    ILM_PC_Bounties_v1.Contributor ALICE =
        ILM_PC_Bounties_v1.Contributor(address(0xA11CE), 50_000_000);
    ILM_PC_Bounties_v1.Contributor BOB =
        ILM_PC_Bounties_v1.Contributor(address(0x606), 50_000_000);
    ILM_PC_Bounties_v1.Contributor BEEF =
        ILM_PC_Bounties_v1.Contributor(address(0xBEEF), 0);
    ILM_PC_Bounties_v1.Contributor[] DEFAULT_CONTRIBUTORS;
    ILM_PC_Bounties_v1.Contributor[] INVALID_CONTRIBUTORS;

    event BountyAdded(
        uint indexed bountyId,
        uint minimumPayoutAmount,
        uint maximumPayoutAmount,
        bytes details
    );

    event BountyUpdated(uint indexed bountyId, bytes details);

    event BountyLocked(uint indexed bountyId);

    event ClaimAdded(
        uint indexed claimId,
        uint indexed bountyId,
        ILM_PC_Bounties_v1.Contributor[] contributors,
        bytes details
    );

    event ClaimContributorsUpdated(
        uint indexed claimId, ILM_PC_Bounties_v1.Contributor[] contributors
    );

    event ClaimDetailsUpdated(uint indexed claimId, bytes details);

    event ClaimVerified(uint indexed claimId);

    function setUp() public {
        // Add Module to Mock Orchestrator_v1
        address impl = address(new LM_PC_Bounties_v1AccessMock());
        bountyManager = LM_PC_Bounties_v1AccessMock(Clones.clone(impl));

        _setUpOrchestrator(bountyManager);

        _authorizer.setIsAuthorized(address(this), true);

        DEFAULT_CONTRIBUTORS.push(ALICE);
        DEFAULT_CONTRIBUTORS.push(BOB);

        INVALID_CONTRIBUTORS.push(BEEF);

        bountyManager.init(_orchestrator, _METADATA, bytes(""));
    }

    //--------------------------------------------------------------------------
    // Test: Initialization

    function testSupportsInterface() public {
        assertTrue(
            bountyManager.supportsInterface(
                type(ILM_PC_Bounties_v1).interfaceId
            )
        );
    }

    // This function also tests all the getters
    function testInit() public override(ModuleTest) {
        assertEq(bountyManager.getFlagCount(), 0);
        assertEq(bountyManager.getFlags(), 0);
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        bountyManager.init(_orchestrator, _METADATA, bytes(""));
    }

    //--------------------------------------------------------------------------
    // Modifier

    function testOnlyClaimContributor(
        address[] memory addrs,
        uint[] memory amounts,
        address addr
    ) public {
        addrs = cutArray(50, addrs); // cut to reasonable size
        uint length = addrs.length;
        vm.assume(length <= amounts.length);

        // Restrict amounts to 20_000 to test properly(doesnt overflow)
        amounts = cutAmounts(20_000_000_000_000, amounts);
        // => maxAmount = 20_000_000_000_000 * 50 = 1_000_000_000_000_000
        uint maxAmount = 1_000_000_000_000_000;
        ILM_PC_Bounties_v1.Contributor[] memory contribs =
            createValidContributors(addrs, amounts);

        bountyManager.addBounty(1, maxAmount, bytes(""));

        bountyManager.addClaim(1, contribs, bytes(""));

        if (!contains(contribs, addr)) {
            vm.expectRevert(
                ILM_PC_Bounties_v1
                    .Module__LM_PC_Bounty__OnlyClaimContributor
                    .selector
            );
        }
        vm.prank(addr);
        bountyManager.updateClaimDetails(2, bytes("1"));
    }

    function testValidPayoutAmounts() public {
        //Check that internal function is in position
        vm.expectRevert(
            ILM_PC_Bounties_v1
                .Module__LM_PC_Bounty__InvalidPayoutAmounts
                .selector
        );

        bountyManager.addBounty(1, 0, bytes(""));
    }

    function testValidArrayLengths(
        uint minimumPayoutAmountLength,
        uint maximumPayoutAmountLength,
        uint detailArrayLength
    ) public {
        if (
            minimumPayoutAmountLength == 0 || maximumPayoutAmountLength == 0
                || detailArrayLength == 0
                || maximumPayoutAmountLength != minimumPayoutAmountLength
                || detailArrayLength != minimumPayoutAmountLength
        ) {
            vm.expectRevert(
                ILM_PC_Bounties_v1
                    .Module__LM_PC_Bounty__InvalidArrayLengths
                    .selector
            );
        }

        bountyManager.validArrayLengthsCheck(
            minimumPayoutAmountLength,
            maximumPayoutAmountLength,
            detailArrayLength
        );
    }

    function testValidBountyId(uint usedIds, uint id) public {
        usedIds = bound(usedIds, 0, 1000);

        for (uint i; i < usedIds; i++) {
            bountyManager.addBounty(1, 1, bytes(""));
        }

        if (id > usedIds || id == 0) {
            vm.expectRevert(
                ILM_PC_Bounties_v1
                    .Module__LM_PC_Bounty__InvalidBountyId
                    .selector
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
                ILM_PC_Bounties_v1.Module__LM_PC_Bounty__InvalidClaimId.selector
            );
        }

        bountyManager.getClaimInformation(id);
    }

    function test_validContributorsForBounty(
        uint minimumPayoutAmount,
        uint maximumPayoutAmount,
        address[] memory addrs,
        uint[] memory amounts
    ) public {
        uint length = addrs.length;
        vm.assume(length <= 50); // reasonable size
        vm.assume(length <= amounts.length);

        minimumPayoutAmount = bound(minimumPayoutAmount, 1, type(uint).max);
        maximumPayoutAmount = bound(maximumPayoutAmount, 1, type(uint).max);
        vm.assume(minimumPayoutAmount <= maximumPayoutAmount);

        // Restrict amounts to 20_000 to test properly(doesnt overflow)
        amounts = cutAmounts(20_000_000_000_000, amounts);

        // ID is 1
        bountyManager.addBounty(
            minimumPayoutAmount, maximumPayoutAmount, bytes("")
        );

        ILM_PC_Bounties_v1.Contributor[] memory contribs =
            new ILM_PC_Bounties_v1.Contributor[](length);

        if (length == 0) {
            vm.expectRevert(
                ILM_PC_Bounties_v1
                    .Module__LM_PC_Bounty__InvalidContributorsLength
                    .selector
            );

            bountyManager.addClaim(1, contribs, bytes(""));
        } else {
            for (uint i; i < length; i++) {
                contribs[i] = ILM_PC_Bounties_v1.Contributor({
                    addr: addrs[i],
                    claimAmount: amounts[i]
                });
            }

            uint totalAmount;
            ILM_PC_Bounties_v1.Contributor memory currentContrib;
            // Check if it reached the end -> ClaimExceedsGivenPayoutAmounts will only be checked if it ran through everything
            bool reachedEnd;

            for (uint i; i < length; i++) {
                currentContrib = contribs[i];

                totalAmount += currentContrib.claimAmount;

                if (currentContrib.claimAmount == 0) {
                    vm.expectRevert(
                        ILM_PC_Bounties_v1
                            .Module__LM_PC_Bounty__InvalidContributorAmount
                            .selector
                    );
                    break;
                }

                if (
                    currentContrib.addr == address(0)
                        || currentContrib.addr == address(bountyManager)
                        || currentContrib.addr == address(_orchestrator)
                ) {
                    vm.expectRevert(
                        ILM_PC_Bounties_v1
                            .Module__LM_PC_Bounty__InvalidContributorAddress
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
                    ILM_PC_Bounties_v1
                        .Module__LM_PC_Bounty__ClaimExceedsGivenPayoutAmounts
                        .selector
                );
            }

            bountyManager.addClaim(1, contribs, bytes(""));
        }
    }

    function testNotClaimed(bool isClaimed) public {
        _token.mint(address(_fundingManager), 100_000_000);

        uint bountyId = bountyManager.addBounty(1, 100_000_000, bytes(""));
        uint claimId =
            bountyManager.addClaim(bountyId, DEFAULT_CONTRIBUTORS, bytes(""));

        if (isClaimed) {
            bountyManager.verifyClaim(claimId, DEFAULT_CONTRIBUTORS);
            vm.expectRevert(
                ILM_PC_Bounties_v1.Module__LM_PC_Bounty__AlreadyClaimed.selector
            );
        }
        bountyManager.verifyClaim(claimId, DEFAULT_CONTRIBUTORS);
    }

    function testLocked(bool isLocked) public {
        _token.mint(address(_fundingManager), 100_000_000);

        uint bountyId = bountyManager.addBounty(1, 100_000_000, bytes(""));
        uint claimId =
            bountyManager.addClaim(bountyId, DEFAULT_CONTRIBUTORS, bytes(""));

        if (isLocked) {
            bountyManager.lockBounty(bountyId);
            vm.expectRevert(
                ILM_PC_Bounties_v1.Module__LM_PC_Bounty__BountyLocked.selector
            );
        }
        bountyManager.verifyClaim(claimId, DEFAULT_CONTRIBUTORS);
    }

    function test_contributorsNotChanged_FailsGivenBountyIsChanged(
        address changeAddress,
        uint changeAmount
    ) public {
        changeAmount = bound(changeAmount, 1, 50_000_000);
        if (
            changeAddress == address(0)
                || changeAddress == address(bountyManager)
                || changeAddress == address(_orchestrator)
        ) {
            changeAddress = address(1);
        }
        _token.mint(address(_fundingManager), 100_000_000);

        uint bountyId = bountyManager.addBounty(1, 100_000_000, bytes(""));
        uint claimId =
            bountyManager.addClaim(bountyId, DEFAULT_CONTRIBUTORS, bytes(""));

        ILM_PC_Bounties_v1.Contributor[] memory changedContributors =
            DEFAULT_CONTRIBUTORS;

        changedContributors[0] = ILM_PC_Bounties_v1.Contributor({
            addr: changeAddress,
            claimAmount: changeAmount
        });
        bountyManager.updateClaimContributors(claimId, changedContributors);
        vm.expectRevert(
            ILM_PC_Bounties_v1
                .Module__LM_PC_Bounty__ContributorsChanged
                .selector
        );

        bountyManager.verifyClaim(claimId, DEFAULT_CONTRIBUTORS);
    }

    function test_contributorsNotChanged_FailsGivenBountyArrayLengthHasChanged(
        address changeAddress,
        uint changeAmount
    ) public {
        changeAmount = bound(changeAmount, 1, 50_000_000);
        if (
            changeAddress == address(0)
                || changeAddress == address(bountyManager)
                || changeAddress == address(_orchestrator)
        ) {
            changeAddress = address(1);
        }
        _token.mint(address(_fundingManager), 150_000_000);

        uint bountyId = bountyManager.addBounty(1, 150_000_000, bytes(""));
        uint claimId =
            bountyManager.addClaim(bountyId, DEFAULT_CONTRIBUTORS, bytes(""));

        // Append element to contributor array to change the length
        DEFAULT_CONTRIBUTORS.push(
            ILM_PC_Bounties_v1.Contributor({
                addr: changeAddress,
                claimAmount: changeAmount
            })
        );

        bountyManager.updateClaimContributors(claimId, DEFAULT_CONTRIBUTORS);

        // Remove appended element to check with original array
        DEFAULT_CONTRIBUTORS.pop();
        vm.expectRevert(
            ILM_PC_Bounties_v1
                .Module__LM_PC_Bounty__ContributorsChanged
                .selector
        );
        bountyManager.verifyClaim(claimId, DEFAULT_CONTRIBUTORS);
    }

    //--------------------------------------------------------------------------
    // Getter
    // Just test if Modifier is in position, because otherwise trivial

    function testGetBountyInformationModifierInPosition() public {
        vm.expectRevert(
            ILM_PC_Bounties_v1.Module__LM_PC_Bounty__InvalidBountyId.selector
        );
        bountyManager.getBountyInformation(0);
    }

    function testGetClaimInformationModifierInPosition() public {
        vm.expectRevert(
            ILM_PC_Bounties_v1.Module__LM_PC_Bounty__InvalidClaimId.selector
        );
        bountyManager.getClaimInformation(0);
    }

    //--------------------------------------------------------------------------
    // Mutating Functions

    //-----------------------------------------
    // AddBounty

    function testAddBounty(
        uint minimumPayoutAmount,
        uint maximumPayoutAmount,
        bytes calldata details
    ) public {
        minimumPayoutAmount = bound(minimumPayoutAmount, 1, type(uint).max);
        maximumPayoutAmount = bound(maximumPayoutAmount, 1, type(uint).max);
        vm.assume(minimumPayoutAmount <= maximumPayoutAmount);

        //Check that internal function is in position

        vm.expectEmit(true, true, true, true);
        emit BountyAdded(1, minimumPayoutAmount, maximumPayoutAmount, details);

        bountyManager.addBounty(
            minimumPayoutAmount, maximumPayoutAmount, details
        );
    }

    function testAddBountyModifierInPosition() public {
        // validPayoutAmounts
        vm.expectRevert(
            ILM_PC_Bounties_v1
                .Module__LM_PC_Bounty__InvalidPayoutAmounts
                .selector
        );
        bountyManager.addBounty(0, 0, bytes(""));

        // Set this address to not authorized to test the roles correctly
        _authorizer.setIsAuthorized(address(this), false);

        // onlyBountyAdmin
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                _authorizer.generateRoleId(
                    address(bountyManager), bountyManager.BOUNTY_ISSUER_ROLE()
                ),
                address(this)
            )
        );
        bountyManager.addBounty(0, 0, bytes(""));
    }

    //-----------------------------------------
    // AddBountyBatch

    function testAddBountyBatch(uint batchSize) public {
        // Reasonable batchSize
        batchSize = bound(batchSize, 1, 1000);

        uint minimumPayoutAmount = 1;
        uint maximumPayoutAmount = 2;
        bytes memory details = bytes("");

        uint[] memory minimumPayoutAmounts = new uint[](batchSize);
        uint[] memory maximumPayoutAmounts = new uint[](batchSize);
        bytes[] memory detailsBatch = new bytes[](batchSize);

        for (uint i; i < batchSize; i++) {
            minimumPayoutAmounts[i] = minimumPayoutAmount;
            maximumPayoutAmounts[i] = maximumPayoutAmount;
            detailsBatch[i] = details;
        }

        // Check that internal function is in position

        for (uint i = 0; i < batchSize; i++) {
            vm.expectEmit(true, true, true, true);
            emit BountyAdded(
                1 + i, minimumPayoutAmount, maximumPayoutAmount, details
            );
        }
        uint[] memory ids = bountyManager.addBountyBatch(
            minimumPayoutAmounts, maximumPayoutAmounts, detailsBatch
        );
        // Check if ids are correct
        assertEq(ids.length, batchSize);
        for (uint i; i < batchSize; i++) {
            assertEq(ids[i], i + 1);
        }
    }

    function testAddBountyBatchModifierInPosition() public {
        // Setup faulty arrays
        uint[] memory minimumPayoutAmounts = new uint[](1);
        minimumPayoutAmounts[0] = 2;
        uint[] memory maximumPayoutAmounts = new uint[](1);
        maximumPayoutAmounts[0] = 1;
        bytes[] memory details = new bytes[](1);
        details[0] = bytes("");

        // validArrayLengths
        vm.expectRevert(
            ILM_PC_Bounties_v1
                .Module__LM_PC_Bounty__InvalidArrayLengths
                .selector
        );
        bountyManager.addBountyBatch(
            new uint[](0), maximumPayoutAmounts, details
        );

        // validPayoutAmounts
        vm.expectRevert(
            ILM_PC_Bounties_v1
                .Module__LM_PC_Bounty__InvalidPayoutAmounts
                .selector
        );
        bountyManager.addBountyBatch(
            minimumPayoutAmounts, maximumPayoutAmounts, details
        );

        // Set this address to not authorized to test the roles correctly
        _authorizer.setIsAuthorized(address(this), false);

        // Set maximumPayoutAmounts[0] correctly
        maximumPayoutAmounts[0] = 2;

        // onlyBountyAdmin
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                _authorizer.generateRoleId(
                    address(bountyManager), bountyManager.BOUNTY_ISSUER_ROLE()
                ),
                address(this)
            )
        );
        bountyManager.addBountyBatch(
            minimumPayoutAmounts, maximumPayoutAmounts, details
        );
    }

    //-----------------------------------------
    // AddClaim

    function testAddClaim(
        uint times,
        address[] memory addrs,
        uint[] memory amounts,
        bytes calldata details
    ) public {
        addrs = cutArray(50, addrs); // cut to reasonable size
        uint length = addrs.length;
        vm.assume(length <= amounts.length);
        times = bound(times, 1, 50);

        // Restrict amounts to 20_000 to test properly(doesnt overflow)
        amounts = cutAmounts(20_000_000_000_000, amounts);
        // => maxAmount = 20_000_000_000_000 * 50 = 1_000_000_000_000_000
        uint maxAmount = 1_000_000_000_000_000;
        ILM_PC_Bounties_v1.Contributor[] memory contribs =
            createValidContributors(addrs, amounts);

        bountyManager.addBounty(1, maxAmount, bytes(""));

        uint id;

        for (uint i = 0; i < times; i++) {
            vm.expectEmit(true, true, true, true);
            // id starts at 2 because the id counter starts at 1 and addBounty increases it by 1 again
            emit ClaimAdded(i + 2, 1, contribs, details);

            id = bountyManager.addClaim(1, contribs, details);
            assertEqualClaim(id, 1, contribs, details, false);

            // Assert set is filled correctly
            for (uint j; j < length; j++) {
                assertContributorAddressToClaimIdsContains(contribs[j].addr, id);
            }
        }
    }

    function testAddClaimModifierInPosition() public {
        bountyManager.addBounty(1, 1, bytes(""));

        // validBountyId
        vm.expectRevert(
            ILM_PC_Bounties_v1.Module__LM_PC_Bounty__InvalidBountyId.selector
        );
        bountyManager.addClaim(0, DEFAULT_CONTRIBUTORS, bytes(""));

        // _validContributorsForBounty
        vm.expectRevert(
            ILM_PC_Bounties_v1
                .Module__LM_PC_Bounty__InvalidContributorAmount
                .selector
        );
        bountyManager.addClaim(1, INVALID_CONTRIBUTORS, bytes(""));

        // notLocked
        bountyManager.lockBounty(1);

        vm.expectRevert(
            ILM_PC_Bounties_v1.Module__LM_PC_Bounty__BountyLocked.selector
        );
        bountyManager.addClaim(1, DEFAULT_CONTRIBUTORS, bytes(""));

        // Set this address to not authorized to test the roles correctly
        _authorizer.setIsAuthorized(address(this), false);

        // onlyClaimAdmin
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                _authorizer.generateRoleId(
                    address(bountyManager), bountyManager.CLAIMANT_ROLE()
                ),
                address(this)
            )
        );
        bountyManager.addClaim(0, DEFAULT_CONTRIBUTORS, bytes(""));
    }

    //-----------------------------------------
    // UpdateBounty

    function testUpdateBounty(bytes calldata details) public {
        uint id = bountyManager.addBounty(1, 1, bytes(""));

        vm.expectEmit(true, true, true, true);
        emit BountyUpdated(1, details);

        bountyManager.updateBounty(id, details);

        assertEqualBounty(id, 1, 1, details, false);
    }

    function testUpdateBountyModifierInPosition() public {
        bountyManager.addBounty(1, 1, bytes(""));

        // validBountyId
        vm.expectRevert(
            ILM_PC_Bounties_v1.Module__LM_PC_Bounty__InvalidBountyId.selector
        );
        bountyManager.updateBounty(0, bytes(""));

        // Set this address to not authorized to test the roles correctly
        _authorizer.setIsAuthorized(address(this), false);

        // onlyBountyAdmin
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                _authorizer.generateRoleId(
                    address(bountyManager), bountyManager.BOUNTY_ISSUER_ROLE()
                ),
                address(this)
            )
        );
        bountyManager.updateBounty(1, bytes(""));
        // Reset this address to authorized
        _authorizer.setIsAuthorized(address(this), true);

        // notLocked
        bountyManager.lockBounty(1);

        vm.expectRevert(
            ILM_PC_Bounties_v1.Module__LM_PC_Bounty__BountyLocked.selector
        );
        bountyManager.updateBounty(1, bytes(""));
    }

    //-----------------------------------------
    // UpdateBounty

    function testLockBounty() public {
        uint id = bountyManager.addBounty(1, 1, bytes(""));

        vm.expectEmit(true, true, true, true);
        emit BountyLocked(1);

        bountyManager.lockBounty(1);

        assertEqualBounty(id, 1, 1, bytes(""), true);
    }

    function testLockBountyModifierInPosition() public {
        bountyManager.addBounty(1, 1, bytes(""));

        // validBountyId
        vm.expectRevert(
            ILM_PC_Bounties_v1.Module__LM_PC_Bounty__InvalidBountyId.selector
        );
        bountyManager.lockBounty(0);

        // NotLocked
        bountyManager.lockBounty(1);
        vm.expectRevert(
            ILM_PC_Bounties_v1.Module__LM_PC_Bounty__BountyLocked.selector
        );
        bountyManager.lockBounty(1);

        // Set this address to not authorized to test the roles correctly
        _authorizer.setIsAuthorized(address(this), false);

        // onlyBountyAdmin
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                _authorizer.generateRoleId(
                    address(bountyManager), bountyManager.BOUNTY_ISSUER_ROLE()
                ),
                address(this)
            )
        );
        bountyManager.lockBounty(0);
    }

    //-----------------------------------------
    // UpdateClaimContributors

    function testUpdateClaimContributors(
        address[] memory addrs,
        uint[] memory amounts
    ) public {
        addrs = cutArray(50, addrs); // cut to reasonable size
        uint length = addrs.length;
        vm.assume(length <= amounts.length);

        // Restrict amounts to 20_000 to test properly(doesnt overflow)
        amounts = cutAmounts(20_000_000_000_000, amounts);
        // => maxAmount = 20_000_000_000_000 * 50 = 1_000_000_000_000_000
        uint maxAmount = 1_000_000_000_000_000;

        ILM_PC_Bounties_v1.Contributor[] memory contribs =
            createValidContributors(addrs, amounts);

        bountyManager.addBounty(1, maxAmount, bytes(""));
        uint id = bountyManager.addClaim(1, DEFAULT_CONTRIBUTORS, bytes(""));

        vm.expectEmit(true, true, true, true);
        emit ClaimContributorsUpdated(id, contribs);

        bountyManager.updateClaimContributors(id, contribs);

        assertEqualClaim(2, 1, contribs, bytes(""), false);

        // Check if default contributors are in the set
        // if not make sure their ClaimIds are removed
        if (!contains(contribs, DEFAULT_CONTRIBUTORS[0].addr)) {
            assertContributorAddressToClaimIdsContainsNot(
                DEFAULT_CONTRIBUTORS[0].addr, id
            );
        }
        if (!contains(contribs, DEFAULT_CONTRIBUTORS[1].addr)) {
            assertContributorAddressToClaimIdsContainsNot(
                DEFAULT_CONTRIBUTORS[1].addr, id
            );
        }

        // Assert set is filled correctly
        for (uint j; j < length; j++) {
            assertContributorAddressToClaimIdsContains(contribs[j].addr, id);
        }
    }

    function testUpdateClaimContributorsModifierInPosition() public {
        bountyManager.addBounty(1, 100_000_000, bytes(""));
        bountyManager.addClaim(1, DEFAULT_CONTRIBUTORS, bytes(""));

        bountyManager.addBounty(1, 100_000_000, bytes("")); // Id 3
        bountyManager.addClaim(3, DEFAULT_CONTRIBUTORS, bytes("")); // Id 4

        // validClaimId
        vm.expectRevert(
            ILM_PC_Bounties_v1.Module__LM_PC_Bounty__InvalidClaimId.selector
        );
        bountyManager.updateClaimContributors(0, DEFAULT_CONTRIBUTORS);

        // _validContributorsForBounty
        vm.expectRevert(
            ILM_PC_Bounties_v1
                .Module__LM_PC_Bounty__InvalidContributorAmount
                .selector
        );
        bountyManager.updateClaimContributors(2, INVALID_CONTRIBUTORS);

        // onlyClaimAdmin
        _authorizer.setIsAuthorized(address(this), false); // No access address
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                _authorizer.generateRoleId(
                    address(bountyManager), bountyManager.CLAIMANT_ROLE()
                ),
                address(this)
            )
        );
        bountyManager.updateClaimContributors(2, DEFAULT_CONTRIBUTORS);
        // Reset this address to authorized
        _authorizer.setIsAuthorized(address(this), true);

        // Reset this address to be authorized to test correctly
        _authorizer.setIsAuthorized(address(this), true);

        bountyManager.lockBounty(1);

        // notLocked
        vm.expectRevert(
            ILM_PC_Bounties_v1.Module__LM_PC_Bounty__BountyLocked.selector
        );

        bountyManager.updateClaimContributors(2, DEFAULT_CONTRIBUTORS);

        // notClaimed
        _token.mint(address(_fundingManager), 100_000_000);
        bountyManager.verifyClaim(4, DEFAULT_CONTRIBUTORS);

        vm.expectRevert(
            ILM_PC_Bounties_v1.Module__LM_PC_Bounty__AlreadyClaimed.selector
        );
        bountyManager.updateClaimContributors(4, DEFAULT_CONTRIBUTORS);
    }

    //-----------------------------------------
    // UpdateClaimDetails

    function testUpdateClaimDetails(bytes calldata details) public {
        bountyManager.addBounty(1, 100_000_000, bytes(""));
        bountyManager.addClaim(1, DEFAULT_CONTRIBUTORS, bytes(""));

        vm.expectEmit(true, true, true, true);
        emit ClaimDetailsUpdated(2, details);
        vm.prank(DEFAULT_CONTRIBUTORS[0].addr);
        bountyManager.updateClaimDetails(2, details);

        assertEqualClaim(2, 1, DEFAULT_CONTRIBUTORS, details, false);
    }

    function testUpdateClaimDetailsModifierInPosition() public {
        bountyManager.addBounty(1, 100_000_000, bytes(""));
        bountyManager.addClaim(1, DEFAULT_CONTRIBUTORS, bytes(""));

        bountyManager.addBounty(1, 100_000_000, bytes("")); // Id 3
        bountyManager.addClaim(3, DEFAULT_CONTRIBUTORS, bytes("")); // Id 4

        // validClaimId
        vm.expectRevert(
            ILM_PC_Bounties_v1.Module__LM_PC_Bounty__InvalidClaimId.selector
        );
        bountyManager.updateClaimDetails(0, bytes(""));

        // onlyClaimContributor
        vm.expectRevert(
            ILM_PC_Bounties_v1
                .Module__LM_PC_Bounty__OnlyClaimContributor
                .selector
        );
        bountyManager.updateClaimDetails(2, bytes(""));

        // notLocked
        bountyManager.lockBounty(1);

        vm.expectRevert(
            ILM_PC_Bounties_v1.Module__LM_PC_Bounty__BountyLocked.selector
        );
        vm.prank(DEFAULT_CONTRIBUTORS[0].addr);
        bountyManager.updateClaimDetails(2, bytes(""));

        // notClaimed
        _token.mint(address(_fundingManager), 100_000_000);
        bountyManager.verifyClaim(4, DEFAULT_CONTRIBUTORS);

        vm.expectRevert(
            ILM_PC_Bounties_v1.Module__LM_PC_Bounty__AlreadyClaimed.selector
        );
        vm.prank(DEFAULT_CONTRIBUTORS[0].addr);
        bountyManager.updateClaimDetails(4, bytes(""));
    }

    //-----------------------------------------
    // verifyClaim

    function testVerifyClaim(
        address[] memory addrs,
        uint[] memory amounts,
        bytes calldata details
    ) public {
        addrs = cutArray(50, addrs); // cut to reasonable size
        uint length = addrs.length;
        vm.assume(length <= amounts.length);

        // Restrict amounts to 20_000_000_000_000 to test properly(doesnt overflow)
        amounts = cutAmounts(20_000_000_000_000, amounts);
        // => maxAmount = 20_000_000_000_000 * 50 = 1_000_000_000_000_000
        uint maxAmount = 1_000_000_000_000_000;
        _token.mint(address(_fundingManager), maxAmount);

        ILM_PC_Bounties_v1.Contributor[] memory contribs =
            createValidContributors(addrs, amounts);

        uint bountyId = bountyManager.addBounty(1, maxAmount, details);
        uint claimId = bountyManager.addClaim(bountyId, contribs, details);

        vm.expectEmit(true, true, true, true);
        emit ClaimVerified(claimId);

        bountyManager.verifyClaim(claimId, contribs);

        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders =
            bountyManager.paymentOrders();

        assertEq(length, orders.length);

        // Amount of tokens that should be in the LM_PC_RecurringPayments_v1
        uint totalAmount;

        // Amount of tokens in a single order
        uint claimAmount;

        for (uint i = 0; i < length; i++) {
            claimAmount = contribs[i].claimAmount;
            totalAmount += claimAmount;

            assertEq(orders[i].recipient, contribs[i].addr);

            assertEq(orders[i].amount, claimAmount);

            // Decode start and end from flags and data
            bool hasStart = (uint(orders[i].flags) & (1 << 1)) != 0;
            bool hasEnd = (uint(orders[i].flags) & (1 << 3)) != 0;

            if (hasStart) {
                assertEq(uint(orders[i].data[0]), 0);
            }
            if (hasEnd) {
                assertEq(uint(orders[i].data[2]), 0);
            }
        }

        assertEqualClaim(claimId, bountyId, contribs, details, true);
    }

    function testVerifyClaimModifierInPosition() public {
        bountyManager.addBounty(1, 100_000_000, bytes(""));
        bountyManager.addClaim(1, DEFAULT_CONTRIBUTORS, bytes("")); // Id 2

        bountyManager.addBounty(1, 100_000_000, bytes("")); // Id 3
        bountyManager.addClaim(3, DEFAULT_CONTRIBUTORS, bytes("")); // Id 4

        // Set this address to not authorized to test the roles correctly
        _authorizer.setIsAuthorized(address(this), false);

        // onlyVerifyAdmin
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                _authorizer.generateRoleId(
                    address(bountyManager), bountyManager.VERIFIER_ROLE()
                ),
                address(this)
            )
        );
        bountyManager.verifyClaim(0, DEFAULT_CONTRIBUTORS);

        // Reset this address to authorized
        _authorizer.setIsAuthorized(address(this), true);

        // validClaimId
        vm.expectRevert(
            ILM_PC_Bounties_v1.Module__LM_PC_Bounty__InvalidClaimId.selector
        );
        bountyManager.verifyClaim(0, DEFAULT_CONTRIBUTORS);

        // _contributorsNotChanged

        vm.expectRevert(
            ILM_PC_Bounties_v1
                .Module__LM_PC_Bounty__ContributorsChanged
                .selector
        );
        bountyManager.verifyClaim(2, INVALID_CONTRIBUTORS);

        // notClaimed
        _token.mint(address(_fundingManager), 100_000_000);
        bountyManager.verifyClaim(2, DEFAULT_CONTRIBUTORS);

        vm.expectRevert(
            ILM_PC_Bounties_v1.Module__LM_PC_Bounty__AlreadyClaimed.selector
        );
        bountyManager.verifyClaim(2, DEFAULT_CONTRIBUTORS);

        // notLocked
        bountyManager.lockBounty(3);

        vm.expectRevert(
            ILM_PC_Bounties_v1.Module__LM_PC_Bounty__BountyLocked.selector
        );
        bountyManager.verifyClaim(4, DEFAULT_CONTRIBUTORS);
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    function test_validPayoutAmounts(
        uint minimumPayoutAmount,
        uint maximumPayoutAmount
    ) public {
        if (
            minimumPayoutAmount == 0 || maximumPayoutAmount == 0
                || maximumPayoutAmount < minimumPayoutAmount
        ) {
            vm.expectRevert(
                ILM_PC_Bounties_v1
                    .Module__LM_PC_Bounty__InvalidPayoutAmounts
                    .selector
            );
        }

        bountyManager.direct__validPayoutAmounts(
            minimumPayoutAmount, maximumPayoutAmount
        );
    }

    function test_addBounty(
        uint testAmount,
        uint minimumPayoutAmount,
        uint maximumPayoutAmount,
        bytes calldata details
    ) public {
        testAmount = bound(testAmount, 1, 30); // Reasonable Amount
        minimumPayoutAmount = bound(minimumPayoutAmount, 1, type(uint).max);
        maximumPayoutAmount = bound(maximumPayoutAmount, 1, type(uint).max);
        vm.assume(minimumPayoutAmount <= maximumPayoutAmount);

        uint id;
        for (uint i; i < testAmount; i++) {
            vm.expectEmit(true, true, true, true);
            emit BountyAdded(
                i + 1, minimumPayoutAmount, maximumPayoutAmount, details
            );

            id = bountyManager.direct__addBounty(
                minimumPayoutAmount, maximumPayoutAmount, details
            );

            assertEqualBounty(
                id, minimumPayoutAmount, maximumPayoutAmount, details, false
            );
        }
    }

    //--------------------------------------------------------------------------
    // Helper

    function cutArray(uint size, address[] memory addrs)
        internal
        pure
        returns (address[] memory)
    {
        uint length = addrs.length;
        vm.assume(length > 0); // Array has to be at least 1

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
        vm.assume(length > 0); // Array has to be at least 1

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
    ) internal view returns (ILM_PC_Bounties_v1.Contributor[] memory) {
        uint length = addrs.length;
        assert(length <= amounts.length);
        address a;

        for (uint i; i < length; i++) {
            // Convert address(0) to address (1)
            a = addrs[i];
            if (
                a == address(0) || a == address(bountyManager)
                    || a == address(_orchestrator)
            ) addrs[i] = address(0x1);

            // Convert amount 0 to 1
            if (amounts[i] == 0) {
                amounts[i] = 1;
            }
            // If Higher than 1_000_000_000_000_000 convert to 1_000_000_000_000_000
            if (amounts[i] > 1_000_000_000_000_000) {
                amounts[i] = 1_000_000_000_000_000;
            }
        }

        ILM_PC_Bounties_v1.Contributor[] memory contribs =
            new ILM_PC_Bounties_v1.Contributor[](length);
        for (uint i; i < length; i++) {
            contribs[i] = ILM_PC_Bounties_v1.Contributor({
                addr: addrs[i],
                claimAmount: amounts[i]
            });
        }
        return contribs;
    }

    function createValidContributors(
        address[] memory addrs,
        uint[] memory amounts
    ) internal view returns (ILM_PC_Bounties_v1.Contributor[] memory) {
        uint length = addrs.length;
        assert(length <= amounts.length);
        address a;

        for (uint i; i < length; i++) {
            // Convert address(0) to address (1)
            a = addrs[i];
            if (
                a == address(0) || a == address(bountyManager)
                    || a == address(_orchestrator)
            ) addrs[i] = address(0x1);

            // Convert amount 0 to 1
            if (amounts[i] == 0) {
                amounts[i] = 1;
            }
        }

        ILM_PC_Bounties_v1.Contributor[] memory contribs =
            new ILM_PC_Bounties_v1.Contributor[](length);
        for (uint i; i < length; i++) {
            contribs[i] = ILM_PC_Bounties_v1.Contributor({
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
        bool lockedToTest
    ) internal {
        ILM_PC_Bounties_v1.Bounty memory currentBounty =
            bountyManager.getBountyInformation(idToProve);

        assertEq(currentBounty.minimumPayoutAmount, minimumPayoutAmountToTest);
        assertEq(currentBounty.maximumPayoutAmount, maximumPayoutAmountToTest);
        assertEq(currentBounty.details, detailsToTest);
        assertEq(currentBounty.locked, lockedToTest);
    }

    function assertEqualClaim(
        uint idToProve,
        uint bountyidToTest,
        ILM_PC_Bounties_v1.Contributor[] memory contribsToTest,
        bytes memory detailsToTest,
        bool claimedToTest
    ) internal {
        ILM_PC_Bounties_v1.Claim memory currentClaim =
            bountyManager.getClaimInformation(idToProve);

        ILM_PC_Bounties_v1.Contributor[] memory currentContribs =
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
        assertEq(currentClaim.claimed, claimedToTest);
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
        LM_PC_Bounties_v1.Contributor[] memory searchThrough,
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
