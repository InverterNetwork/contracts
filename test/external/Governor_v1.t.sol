// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// SuT
import {
    Governor_v1, IGovernor_v1
} from "src/external/governance/Governor_v1.sol";

import {Governor_v1_Exposed} from
    "test/utils/mocks/external/Governor_v1_Exposed.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// Internal Dependencies
import {IInverterBeacon_v1} from "src/proxies/interfaces/IInverterBeacon_v1.sol";
import {
    IModuleFactory_v1,
    IModule_v1
} from "src/factories/interfaces/IModuleFactory_v1.sol";

import {InverterBeaconV1OwnableMock} from
    "test/utils/mocks/proxies/InverterBeaconV1OwnableMock.sol";
import {ModuleFactoryV1Mock} from
    "test/utils/mocks/factories/ModuleFactoryV1Mock.sol";

// External Dependencies
import {IAccessControl} from "@oz/access/IAccessControl.sol";

import {Clones} from "@oz/proxy/Clones.sol";

contract GovernorV1Test is Test {
    // SuT
    Governor_v1_Exposed gov;

    ModuleFactoryV1Mock modFactory;

    InverterBeaconV1OwnableMock ownedBeaconMock;
    InverterBeaconV1OwnableMock unownedBeaconMock;

    address communityMultisig = address(0x11111);
    address teamMultisig = address(0x22222);
    uint timelockPeriod = 1 weeks;

    // Events

    event BeaconTimelockStarted(
        address beacon,
        address newImplementation,
        uint newMinorVersion,
        uint newPatchVersion,
        uint timelockExceeded
    );
    event BeaconUpgraded(
        address beacon,
        address newImplementation,
        uint newMinorVersion,
        uint newPatchVersion
    );
    event BeaconUpgradedCanceled(address beacon);
    event TimelockPeriodSet(uint newTimelockPeriod);
    event FeeManagerUpdated(address feeManager);
    event ModuleFactoryUpdated(address moduleFactory);
    event BeaconShutdownInitiated(address beacon);
    event BeaconForcefullyUpgradedAndImplementationRestarted(
        address beacon,
        address newImplementation,
        uint newMinorVersion,
        uint newPatchVersion
    );
    event BeaconImplementationRestarted(address beacon);
    event OwnershipAccepted(address adr);

    function setUp() public {
        modFactory = new ModuleFactoryV1Mock();

        address impl = address(new Governor_v1_Exposed());
        gov = Governor_v1_Exposed(Clones.clone(impl));
        gov.init(
            communityMultisig,
            teamMultisig,
            timelockPeriod,
            address(makeAddr("FeeManager")),
            address(address(modFactory))
        );

        // Create beacon owned by governor
        ownedBeaconMock = new InverterBeaconV1OwnableMock(address(gov));

        // Create beacon not owned by governor contract
        unownedBeaconMock = new InverterBeaconV1OwnableMock(address(this));
    }

    //--------------------------------------------------------------------------
    // Test: SupportsInterface

    function testSupportsInterface() public {
        assertTrue(gov.supportsInterface(type(IGovernor_v1).interfaceId));
    }

    //--------------------------------------------------------------------------
    // Test: Modifier

    function testOnlyLinkedModuleFactory(address adr) public {
        if (adr != address(modFactory)) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernor_v1.Governor__OnlyLinkedModuleFactory.selector
                )
            );
        }

        IInverterBeacon_v1[] memory beacons = new IInverterBeacon_v1[](0);

        vm.prank(adr);
        gov.moduleFactoryInitCallback(beacons);
    }

    function testLinkedBeaconsEmpty(bool empty) public {
        IModule_v1.Metadata memory metadata;
        if (!empty) {
            vm.prank(communityMultisig);
            gov.registerMetadataInModuleFactory(metadata, ownedBeaconMock);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernor_v1.Governor__LinkedBeaconsNotEmpty.selector
                )
            );
        }

        IInverterBeacon_v1[] memory beacons = new IInverterBeacon_v1[](0);

        vm.prank(address(modFactory));
        gov.moduleFactoryInitCallback(beacons);
    }

    function testValidAddress(address adr) public {
        if (adr == address(0)) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernor_v1.Governor__InvalidAddress.selector, adr
                )
            );
        }

        vm.prank(communityMultisig);
        gov.setModuleFactory(adr);
    }

    function testValidTimelockPeriod(uint amt) public {
        if (amt < 48 hours) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernor_v1.Governor__InvalidTimelockPeriod.selector, amt
                )
            );
        }

        vm.prank(communityMultisig);
        gov.setTimelockPeriod(amt);
    }

    function testAccessibleBeacon(uint seed, address target) public {
        vm.assume(target != 0x4e59b44847b379578588920cA78FbF26c0B4956C); // Create2Deployer
        bool shouldFail = true;
        // Restrict seed to one of 3 variants
        seed = bound(seed, 0, 2);
        // case 1
        if (seed == 0) {
            target = address(ownedBeaconMock);
            shouldFail = false;
        }
        // Case 2
        else if (seed == 1) {
            target = address(unownedBeaconMock);
        }
        // Case 3
        else {
            // Just make sure target is not one of the other ones
            vm.assume(target != address(ownedBeaconMock));
            vm.assume(target != address(unownedBeaconMock));
        }

        if (shouldFail) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernor_v1.Governor__BeaconNotAccessible.selector, target
                )
            );
        }
        vm.prank(address(communityMultisig));
        gov.upgradeBeaconWithTimelock(target, address(0x1), 0, 0);
    }

    function testOnlyCommunityOrTeamMultisig(address sender) public {
        if (
            !gov.hasRole(gov.COMMUNITY_MULTISIG_ROLE(), sender)
                && !gov.hasRole(gov.TEAM_MULTISIG_ROLE(), sender)
        ) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernor_v1.Governor__OnlyCommunityOrTeamMultisig.selector
                )
            );
        }

        vm.prank(sender);
        gov.upgradeBeaconWithTimelock(
            address(ownedBeaconMock), address(0xBEEF), 2, 0
        );
    }

    function testUpgradeProcessAlreadyStarted(bool processStarted) public {
        if (processStarted) {
            vm.prank(address(communityMultisig));
            gov.upgradeBeaconWithTimelock(
                address(ownedBeaconMock), address(0x1), 0, 0
            );
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernor_v1.Governor__UpgradeProcessNotStarted.selector
                )
            );
        }

        vm.prank(communityMultisig);
        gov.cancelUpgrade(address(ownedBeaconMock));
    }

    function testTimelockPeriodExceeded(uint seed1, uint seed2) public {
        seed1 = bound(seed1, 0, 1_000_000 weeks);
        seed2 = bound(seed2, 0, 1000 days);
        // warp now to seed
        vm.warp(seed1);

        // Create Timelock
        vm.prank(address(communityMultisig));
        gov.upgradeBeaconWithTimelock(
            address(ownedBeaconMock), address(0x1), 0, 0
        );

        // Wait seed2 time
        vm.warp(block.timestamp + seed2);

        // If waited time is smaller than timelock period throw error
        if (seed2 < timelockPeriod) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernor_v1.Governor__TimelockPeriodNotExceeded.selector
                )
            );
        }

        vm.prank(communityMultisig);
        gov.triggerUpgradeBeaconWithTimelock(address(ownedBeaconMock));
    }

    //--------------------------------------------------------------------------
    // Test: Init

    function testInit() public {
        // Assert Admin roles
        // COMMUNITY_MULTISIG_ROLE is its own admin
        assertEq(
            gov.getRoleAdmin(gov.COMMUNITY_MULTISIG_ROLE()),
            gov.COMMUNITY_MULTISIG_ROLE()
        );
        // COMMUNITY_MULTISIG_ROLE is its TEAM_MULTISIG_ROLE admin
        assertEq(
            gov.getRoleAdmin(gov.TEAM_MULTISIG_ROLE()),
            gov.COMMUNITY_MULTISIG_ROLE()
        );
        // COMMUNITY_MULTISIG_ROLE is its DEFAULT_ADMIN_ROLE admin
        assertEq(
            gov.getRoleAdmin(gov.DEFAULT_ADMIN_ROLE()),
            gov.COMMUNITY_MULTISIG_ROLE()
        );

        // Assert role distribution
        assertTrue(
            gov.hasRole(gov.COMMUNITY_MULTISIG_ROLE(), communityMultisig)
        );
        assertTrue(gov.hasRole(gov.TEAM_MULTISIG_ROLE(), teamMultisig));

        // assert timelock Period
        assertEq(gov.timelockPeriod(), timelockPeriod);

        // assert FeeManager
        assertEq(gov.getFeeManager(), makeAddr("FeeManager"));
    }

    function testInitModifierInPosition() public {
        // initializer
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        gov.init(
            communityMultisig,
            teamMultisig,
            timelockPeriod,
            makeAddr("FeeManager"),
            address(modFactory)
        );

        address impl = address(new Governor_v1_Exposed());
        gov = Governor_v1_Exposed(Clones.clone(impl));
        // validAddress(newCommunityMultisig)
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__InvalidAddress.selector, address(0)
            )
        );
        gov.init(
            address(0),
            teamMultisig,
            timelockPeriod,
            makeAddr("FeeManager"),
            address(modFactory)
        );

        // validAddress(newTeamMultisig)
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__InvalidAddress.selector, address(0)
            )
        );
        gov.init(
            communityMultisig,
            address(0),
            timelockPeriod,
            makeAddr("FeeManager"),
            address(modFactory)
        );

        // validTimelockPeriod(newTimelockPeriod)
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__InvalidTimelockPeriod.selector, 0
            )
        );
        gov.init(
            communityMultisig,
            teamMultisig,
            0,
            makeAddr("FeeManager"),
            address(modFactory)
        );

        // validAddress(newFeeManager)
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__InvalidAddress.selector, address(0)
            )
        );

        gov.init(
            communityMultisig,
            teamMultisig,
            timelockPeriod,
            address(0),
            address(modFactory)
        );

        // validAddress(_feeManager)
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__InvalidAddress.selector, address(0)
            )
        );

        gov.init(
            communityMultisig,
            teamMultisig,
            timelockPeriod,
            makeAddr("FeeManager"),
            address(0)
        );
    }

    //--------------------------------------------------------------------------
    // Test: moduleFactoryInitCallback

    function testModuleFactoryInitCallback(uint beaconAmount) public {
        vm.assume(beaconAmount < 1000);

        IInverterBeacon_v1[] memory newBeacons =
            new IInverterBeacon_v1[](beaconAmount);

        for (uint i = 0; i < beaconAmount; i++) {
            newBeacons[i] = IInverterBeacon_v1(
                address(new InverterBeaconV1OwnableMock(address(gov)))
            );
        }

        vm.prank(address(modFactory));
        gov.moduleFactoryInitCallback(newBeacons);

        IInverterBeacon_v1[] memory linkedBeacons = gov.getLinkedBeacons();
        assertEq(newBeacons.length, linkedBeacons.length);

        for (uint i = 0; i < linkedBeacons.length; i++) {
            assertEq(address(newBeacons[i]), address(linkedBeacons[i]));
        }
    }

    function testModuleFactoryInitCallbackFailsForIncorrectBeacon() public {
        IInverterBeacon_v1[] memory newBeacons = new IInverterBeacon_v1[](1);
        newBeacons[0] = unownedBeaconMock;

        // _isBeaconAccessible
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__BeaconNotAccessible.selector,
                address(unownedBeaconMock)
            )
        );

        vm.prank(address(modFactory));
        gov.moduleFactoryInitCallback(newBeacons);
    }

    function testModuleFactoryInitCallbackModifierInPosition() public {
        IInverterBeacon_v1[] memory newBeacons = new IInverterBeacon_v1[](0);

        // onlyLinkedModuleFactory
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__OnlyLinkedModuleFactory.selector
            )
        );

        gov.moduleFactoryInitCallback(newBeacons);

        // linkedBeaconsEmpty
        IModule_v1.Metadata memory metadata;
        vm.prank(communityMultisig);
        gov.registerMetadataInModuleFactory(metadata, ownedBeaconMock);
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__LinkedBeaconsNotEmpty.selector
            )
        );
        vm.prank(address(modFactory));
        gov.moduleFactoryInitCallback(newBeacons);
    }

    //--------------------------------------------------------------------------
    // Test: Getter Functions

    function testGetBeaconTimelock() public view {
        // Tivial Test
        // 100% Testcoverage here we go xD
        gov.getBeaconTimelock(address(0));
    }

    //--------------------------------------------------------------------------
    // Test: FeeManager Functions

    function testGetFeeManager() public view {
        // Tivial Test
        gov.getFeeManager();
    }

    function testSetFeeManager() public {
        vm.prank(address(communityMultisig));
        vm.expectEmit(true, true, true, true);
        emit FeeManagerUpdated(address(0x1));
        gov.setFeeManager(address(0x1));
    }

    function testSetFeeManagerModifierInPosition() public {
        // onlyRole(COMMUNITY_MULTISIG_ROLE)
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                gov.COMMUNITY_MULTISIG_ROLE()
            )
        );
        gov.setFeeManager(address(0x1));

        // validAddress(newFeeManager)
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__InvalidAddress.selector, address(0)
            )
        );
        vm.prank(address(communityMultisig));
        gov.setFeeManager(address(0));
    }

    function testSetModuleFactoryModifierInPosition() public {
        // onlyRole(COMMUNITY_MULTISIG_ROLE)
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                gov.COMMUNITY_MULTISIG_ROLE()
            )
        );
        gov.setModuleFactory(address(0x1));

        // validAddress(newModuleFactory)
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__InvalidAddress.selector, address(0)
            )
        );
        vm.prank(address(communityMultisig));
        gov.setModuleFactory(address(0));
    }

    function testSetModuleFactory() public {
        vm.prank(address(communityMultisig));
        vm.expectEmit(true, true, true, true);
        emit ModuleFactoryUpdated(address(0x1));
        gov.setModuleFactory(address(0x1));
    }

    function testSetFeeManagerMaxFeeModifierInPosition() public {
        // onlyRole(COMMUNITY_MULTISIG_ROLE)
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                gov.COMMUNITY_MULTISIG_ROLE()
            )
        );
        gov.setFeeManagerMaxFee(0);
    }

    function testSetFeeManagerDefaultProtocolTreasuryModifierInPosition()
        public
    {
        // onlyRole(COMMUNITY_MULTISIG_ROLE)
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                gov.COMMUNITY_MULTISIG_ROLE()
            )
        );
        gov.setFeeManagerDefaultProtocolTreasury(address(0x1));
    }

    function testSetFeeManagerWorkflowTreasuriesModifierInPosition() public {
        // onlyRole(COMMUNITY_MULTISIG_ROLE)
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                gov.COMMUNITY_MULTISIG_ROLE()
            )
        );
        gov.setFeeManagerWorkflowTreasuries(address(0x1), address(0x1));
    }

    function testSetFeeManagerDefaultCollateralFeeModifierInPosition() public {
        // onlyRole(COMMUNITY_MULTISIG_ROLE)
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                gov.COMMUNITY_MULTISIG_ROLE()
            )
        );
        gov.setFeeManagerDefaultCollateralFee(1);
    }

    function testSetFeeManagerDefaultIssuanceFeeModifierInPosition() public {
        // onlyRole(COMMUNITY_MULTISIG_ROLE)
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                gov.COMMUNITY_MULTISIG_ROLE()
            )
        );
        gov.setFeeManagerDefaultIssuanceFee(1);
    }

    function testSetFeeManagerCollateralWorkflowFeeModifierInPosition()
        public
    {
        // onlyCommunityOrTeamMultisig
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__OnlyCommunityOrTeamMultisig.selector
            )
        );
        gov.setFeeManagerCollateralWorkflowFee(
            address(0x1), address(0x1), bytes4(""), true, 1
        );
    }

    function testSetFeeManagerIssuanceWorkflowFeeModifierInPosition() public {
        // onlyCommunityOrTeamMultisig
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__OnlyCommunityOrTeamMultisig.selector
            )
        );
        gov.setFeeManagerIssuanceWorkflowFee(
            address(0x1), address(0x1), bytes4(""), true, 1
        );
    }

    //--------------------------------------------------------------------------
    // Test: Register Beacons

    function testRegisterMetadataInModuleFactory() public {
        IModule_v1.Metadata memory metadata;

        vm.prank(communityMultisig);
        gov.registerMetadataInModuleFactory(
            metadata, IInverterBeacon_v1(ownedBeaconMock)
        );

        // Check if beacon is in linked beacon list
        assertEq(address(ownedBeaconMock), address(gov.getLinkedBeacons()[0]));

        // expect that the target function is called
        assertEq(modFactory.howManyCalls(), 1);
    }

    function testRegisterMetadataInModuleFactoryModifierInPosition() public {
        // onlyCommunityOrTeamMultisig
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__OnlyCommunityOrTeamMultisig.selector
            )
        );

        IModule_v1.Metadata memory metadata;
        gov.registerMetadataInModuleFactory(
            metadata, IInverterBeacon_v1(ownedBeaconMock)
        );

        // accessibleBeacon(beacon)
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__BeaconNotAccessible.selector, address(0)
            )
        );
        vm.prank(communityMultisig);
        gov.registerMetadataInModuleFactory(
            metadata, IInverterBeacon_v1(address(0))
        );
    }

    /*
    Test: registerNonModuleBeacon
    ├── Given: caller is neither the community multisig nor the team multisig
    │   └── When: registerNonModuleBeacon is called
    │       └── Then: revert with error
    └── Given: caller is the community multisig or the team multisig
        └── When: registerNonModuleBeacon is called
            └── Then: The internal function _registerNonModuleBeacon is called
     */

    function testregisterNonModuleBeacon_ModifierInPosition() public {
        // onlyCommunityOrTeamMultisig
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__OnlyCommunityOrTeamMultisig.selector
            )
        );
        gov.registerNonModuleBeacon(IInverterBeacon_v1(ownedBeaconMock));
    }

    function testregisterNonModuleBeacon_internalFunctionCalled() public {
        vm.expectEmit(true, true, true, true);
        emit IGovernor_v1.BeaconAddedToLinkedBeacons(address(ownedBeaconMock));

        vm.prank(communityMultisig);
        gov.registerNonModuleBeacon(IInverterBeacon_v1(ownedBeaconMock));
    }

    //--------------------------------------------------------------------------
    // Test: Beacon Functions

    //---------------------------
    // Upgrade

    function testUpgradeBeaconWithTimelock(
        uint seed,
        bytes32 salt,
        address newImplementation,
        uint newMinorVersion,
        uint newPatchVersion
    ) public {
        vm.assume(newImplementation != address(0));

        // To properly randomise Beacon deployment use create2 and salt
        address beacon = deployBeaconWithSaltAndTransferOwnershipToGov(salt);

        // Resonable warp
        vm.warp(bound(seed, 0, 1_000_000 weeks));

        vm.expectEmit(true, true, true, true);

        // We emit the event we expect to see.
        emit BeaconTimelockStarted(
            beacon,
            newImplementation,
            newMinorVersion,
            newPatchVersion,
            timelockPeriod + block.timestamp
        );
        vm.prank(address(communityMultisig));
        gov.upgradeBeaconWithTimelock(
            beacon, newImplementation, newMinorVersion, newPatchVersion
        );

        assertTrue(gov.getBeaconTimelock(beacon).timelockActive);
        assertEq(
            gov.getBeaconTimelock(beacon).timelockUntil,
            timelockPeriod + block.timestamp
        );
        assertEq(
            gov.getBeaconTimelock(beacon).intendedImplementation,
            newImplementation
        );
        assertEq(
            gov.getBeaconTimelock(beacon).intendedMinorVersion, newMinorVersion
        );
        assertEq(
            gov.getBeaconTimelock(beacon).intendedPatchVersion, newPatchVersion
        );
    }

    function testUpgradeBeaconWithTimelockModifierInPosition() public {
        // onlyCommunityOrTeamMultisig
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__OnlyCommunityOrTeamMultisig.selector
            )
        );
        gov.upgradeBeaconWithTimelock(
            address(ownedBeaconMock), address(0x1), 0, 0
        );

        // accessibleBeacon(beacon)
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__BeaconNotAccessible.selector, address(0)
            )
        );
        vm.prank(communityMultisig);
        gov.upgradeBeaconWithTimelock(address(0), address(0x1), 0, 0);

        // validAddress(newImplementation)
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__InvalidAddress.selector, address(0)
            )
        );
        vm.prank(communityMultisig);
        gov.upgradeBeaconWithTimelock(
            address(ownedBeaconMock), address(0), 0, 0
        );
    }

    function testTriggerUpgradeBeaconWithTimelock() public {
        vm.prank(address(communityMultisig));
        gov.upgradeBeaconWithTimelock(
            address(ownedBeaconMock), address(0x1), 0, 0
        );

        // Resonable warp
        vm.warp(block.timestamp + timelockPeriod + 1);

        vm.expectEmit(true, true, true, true);
        emit BeaconUpgraded(address(ownedBeaconMock), address(0x1), 0, 0);

        vm.prank(address(communityMultisig));
        gov.triggerUpgradeBeaconWithTimelock(address(ownedBeaconMock));

        assertFalse(
            gov.getBeaconTimelock(address(ownedBeaconMock)).timelockActive
        );
        // Make sure ownedBeaconMock got called
        assertEq(ownedBeaconMock.functionCalled(), 1);
        assertEq(ownedBeaconMock.implementation(), address(0x1));
        assertEq(ownedBeaconMock.minorVersion(), 0);
        assertEq(ownedBeaconMock.patchVersion(), 0);
        assertEq(ownedBeaconMock.forcefulCall(), false);
    }

    function testTriggerUpgradeBeaconWithTimelockModifierInPosition() public {
        // onlyCommunityOrTeamMultisig
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__OnlyCommunityOrTeamMultisig.selector
            )
        );
        gov.triggerUpgradeBeaconWithTimelock(address(ownedBeaconMock));

        // accessibleBeacon(beacon)
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__BeaconNotAccessible.selector, address(0)
            )
        );
        vm.prank(communityMultisig);
        gov.triggerUpgradeBeaconWithTimelock(address(0));

        // upgradeProcessAlreadyStarted(beacon)

        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__UpgradeProcessNotStarted.selector
            )
        );
        vm.prank(communityMultisig);
        gov.triggerUpgradeBeaconWithTimelock(address(ownedBeaconMock));

        // timelockPeriodExceeded(beacon)

        vm.prank(communityMultisig);
        gov.upgradeBeaconWithTimelock(
            address(ownedBeaconMock), address(0x1), 0, 0
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__TimelockPeriodNotExceeded.selector
            )
        );
        vm.prank(communityMultisig);
        gov.triggerUpgradeBeaconWithTimelock(address(ownedBeaconMock));
    }

    function testCancelUpgrade() public {
        vm.prank(address(communityMultisig));
        gov.upgradeBeaconWithTimelock(
            address(ownedBeaconMock), address(0x1), 0, 0
        );

        // Resonable warp
        vm.warp(block.timestamp + timelockPeriod + 1);

        vm.expectEmit(true, true, true, true);
        emit BeaconUpgradedCanceled(address(ownedBeaconMock));

        vm.prank(address(communityMultisig));
        gov.cancelUpgrade(address(ownedBeaconMock));

        assertFalse(
            gov.getBeaconTimelock(address(ownedBeaconMock)).timelockActive
        );
    }

    function testCancelUpgradeModifierInPosition() public {
        // onlyCommunityOrTeamMultisig
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__OnlyCommunityOrTeamMultisig.selector
            )
        );
        gov.cancelUpgrade(address(ownedBeaconMock));

        // upgradeProcessAlreadyStarted(beacon)

        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__UpgradeProcessNotStarted.selector
            )
        );
        vm.prank(communityMultisig);
        gov.cancelUpgrade(address(ownedBeaconMock));
    }

    function testSetTimelockPeriod() public {
        vm.prank(address(communityMultisig));
        vm.expectEmit(true, true, true, true);
        emit TimelockPeriodSet(2 days);
        gov.setTimelockPeriod(2 days);
    }

    function testSetTimelockPeriodModifierInPosition() public {
        // onlyRole(COMMUNITY_MULTISIG_ROLE)
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                gov.COMMUNITY_MULTISIG_ROLE()
            )
        );
        gov.setTimelockPeriod(1);

        // validTimelockPeriod(newTimelockPeriod)
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__InvalidTimelockPeriod.selector, 0
            )
        );
        vm.prank(address(communityMultisig));
        gov.setTimelockPeriod(0);
    }

    //--------------------------------------------------------------------------
    // Test: Emergency Shutdown Functions

    function testInitiateBeaconShutdown() public {
        vm.expectEmit(true, true, true, true);
        emit BeaconShutdownInitiated(address(ownedBeaconMock));

        vm.prank(address(communityMultisig));
        gov.initiateBeaconShutdown(address(ownedBeaconMock));

        // Make sure ownedBeaconMock got called
        assertEq(ownedBeaconMock.functionCalled(), 1);
    }

    function testInitiateBeaconShutdownModifierInPosition() public {
        // onlyCommunityOrTeamMultisig
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__OnlyCommunityOrTeamMultisig.selector
            )
        );
        gov.initiateBeaconShutdown(address(ownedBeaconMock));

        // accessibleBeacon(beacon)
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__BeaconNotAccessible.selector,
                address(unownedBeaconMock)
            )
        );
        vm.prank(communityMultisig);
        gov.initiateBeaconShutdown(address(unownedBeaconMock));
    }

    function testInitiateBeaconShutdownForAllLinkedBeacons(uint beaconAmount)
        public
    {
        vm.assume(beaconAmount < 1000);

        // Create beacons
        IInverterBeacon_v1[] memory newBeacons =
            new IInverterBeacon_v1[](beaconAmount);

        for (uint i = 0; i < beaconAmount; i++) {
            newBeacons[i] = IInverterBeacon_v1(
                address(new InverterBeaconV1OwnableMock(address(gov)))
            );
        }

        // Fill Governor with beacons
        vm.prank(address(modFactory));
        gov.moduleFactoryInitCallback(newBeacons);

        for (uint i = 0; i < beaconAmount; i++) {
            vm.expectEmit(true, true, true, true);
            emit BeaconShutdownInitiated(address(newBeacons[i]));
        }

        vm.prank(address(communityMultisig));
        gov.initiateBeaconShutdownForAllLinkedBeacons();

        for (uint i = 0; i < beaconAmount; i++) {
            // Make sure ownedBeaconMock got called
            assertEq(
                InverterBeaconV1OwnableMock(address(newBeacons[i]))
                    .functionCalled(),
                1
            );
        }
    }

    function testInitiateBeaconShutdownForAllLinkedBeaconsModifierInPosition()
        public
    {
        // onlyCommunityOrTeamMultisig
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__OnlyCommunityOrTeamMultisig.selector
            )
        );
        gov.initiateBeaconShutdownForAllLinkedBeacons();
    }

    function testForceUpgradeBeaconAndRestartImplementation() public {
        vm.expectEmit(true, true, true, true);
        emit BeaconForcefullyUpgradedAndImplementationRestarted(
            address(ownedBeaconMock), address(0x1), 0, 0
        );

        vm.prank(address(communityMultisig));
        gov.forceUpgradeBeaconAndRestartImplementation(
            address(ownedBeaconMock), address(0x1), 0, 0
        );

        assertFalse(
            gov.getBeaconTimelock(address(ownedBeaconMock)).timelockActive
        );
        // Make sure ownedBeaconMock got called
        assertEq(ownedBeaconMock.functionCalled(), 1);
        assertEq(ownedBeaconMock.implementation(), address(0x1));
        assertEq(ownedBeaconMock.minorVersion(), 0);
        assertEq(ownedBeaconMock.patchVersion(), 0);
        assertEq(ownedBeaconMock.forcefulCall(), true);
    }

    function testForceUpgradeBeaconAndRestartImplementationModifierInPosition()
        public
    {
        // onlyRole(COMMUNITY_MULTISIG_ROLE)
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                gov.COMMUNITY_MULTISIG_ROLE()
            )
        );
        gov.forceUpgradeBeaconAndRestartImplementation(
            address(ownedBeaconMock), address(0x1), 0, 0
        );

        // accessibleBeacon(beacon)
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__BeaconNotAccessible.selector, address(0)
            )
        );
        vm.prank(communityMultisig);
        gov.forceUpgradeBeaconAndRestartImplementation(
            address(0), address(0x1), 0, 0
        );

        // validAddress(newImplementation)
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__InvalidAddress.selector, address(0)
            )
        );
        vm.prank(communityMultisig);
        gov.forceUpgradeBeaconAndRestartImplementation(
            address(ownedBeaconMock), address(0), 0, 0
        );
    }

    function testRestartBeaconImplementation() public {
        vm.expectEmit(true, true, true, true);
        emit BeaconImplementationRestarted(address(ownedBeaconMock));

        vm.prank(address(communityMultisig));
        gov.restartBeaconImplementation(address(ownedBeaconMock));

        // Make sure ownedBeaconMock got called
        assertEq(ownedBeaconMock.functionCalled(), 1);
    }

    function testRestartBeaconImplementationModifierInPosition() public {
        // onlyRole(COMMUNITY_MULTISIG_ROLE)
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                gov.COMMUNITY_MULTISIG_ROLE()
            )
        );
        gov.restartBeaconImplementation(address(ownedBeaconMock));

        // accessibleBeacon(beacon)
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__BeaconNotAccessible.selector,
                address(unownedBeaconMock)
            )
        );
        vm.prank(communityMultisig);
        gov.restartBeaconImplementation(address(unownedBeaconMock));
    }

    //--------------------------------------------------------------------------
    // Test: Ownable2Step Functions

    function testAcceptOwnership() public {
        // onlyCommunityOrTeamMultisig
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__OnlyCommunityOrTeamMultisig.selector
            )
        );
        gov.acceptOwnership(address(unownedBeaconMock));
    }

    function testAcceptOwnership(uint seed, address target) public {
        bool shouldFail = true;
        // Restrict seed to one of 3 variants
        seed = bound(seed, 0, 2);
        // case 1 Can change ownership
        if (seed == 0) {
            // Prepare beacon to tranfer ownership
            unownedBeaconMock.transferOwnership(address(gov));
            target = address(unownedBeaconMock);
            shouldFail = false;
        }
        // Case 2 cannot change ownership
        else if (seed == 1) {
            target = address(unownedBeaconMock);
        }
        // Case 3 is not a contract
        else {
            vm.assume(target.code.length != 0);
        }

        if (shouldFail) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernor_v1.Governor__CallToTargetContractFailed.selector
                )
            );
        }
        vm.prank(address(communityMultisig));
        gov.acceptOwnership(target);
    }

    function testAcceptOwnershipModifierInPosition() public {
        // onlyCommunityOrTeamMultisig
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__OnlyCommunityOrTeamMultisig.selector
            )
        );
        gov.acceptOwnership(address(unownedBeaconMock));
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /*
    Test: _addBeaconToLinkedBeacons
    ├── Given: Beacon is not accessible
    │   └── When: _addBeaconToLinkedBeacons is called
    │       └── Then: revert with Governor__BeaconNotAccessible
    └── Given: Beacon is accessible
        └── When: _addBeaconToLinkedBeacons is called
            └── Then: Beacon is added to linkedBeacons
                └── And: emits BeaconLinked event
     */

    function test_addBeaconToLinkedBeacons_BeaconNotAccessible() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor_v1.Governor__BeaconNotAccessible.selector, address(0)
            )
        );
        gov.exposed_addBeaconToLinkedBeacons(IInverterBeacon_v1(address(0)));
    }

    function test_addBeaconToLinkedBeacons_BeaconIsAccessible() public {
        // Given: Beacon is accessible

        // And: emits BeaconLinked event
        vm.expectEmit(true, true, true, true);
        emit IGovernor_v1.BeaconAddedToLinkedBeacons(address(ownedBeaconMock));
        gov.exposed_addBeaconToLinkedBeacons(
            IInverterBeacon_v1(ownedBeaconMock)
        );

        IInverterBeacon_v1[] memory beacons = gov.getLinkedBeacons();

        // Then: Beacon is added to linkedBeacons
        assertEq(beacons.length, 1);
        assertEq(address(beacons[0]), address(ownedBeaconMock));
    }

    //--------------------------------------------------------------------------
    // Helper Functions

    function deployBeaconWithSaltAndTransferOwnershipToGov(bytes32 _salt)
        internal
        returns (address)
    {
        // This syntax is a newer way to invoke create2 without assembly, you just need to pass salt
        InverterBeaconV1OwnableMock mock =
            new InverterBeaconV1OwnableMock{salt: _salt}(address(gov));

        return address(mock);
    }
}
