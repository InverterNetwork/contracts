// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// SuT
import {
    GovernanceContract,
    IGovernanceContract
} from "src/external/governance/GovernanceContract.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// Internal Dependencies
import {InverterBeaconOwnableMock} from
    "test/utils/mocks/factories/beacon/InverterBeaconOwnableMock.sol";

//External Dependencies
import {IAccessControl} from "@oz/access/IAccessControl.sol";

contract GovernanceContractTest is Test {
    // SuT
    GovernanceContract gov;

    InverterBeaconOwnableMock ownedBeaconMock;
    InverterBeaconOwnableMock unownedBeaconMock;

    address communityMultisig = address(0x11111);
    address teamMultisig = address(0x22222);
    uint timelockPeriod = 1 weeks;

    //Events

    event BeaconTimelockStarted(
        address beacon,
        address newImplementation,
        uint newMinorVersion,
        uint timelockExceeded
    );
    event BeaconUpgraded(
        address beacon, address newImplementation, uint newMinorVersion
    );
    event BeaconUpgradedCanceled(address beacon);
    event TimelockPeriodSet(uint newTimelockPeriod);
    event BeaconShutdownInitiated(address beacon);
    event BeaconForcefullyUpgradedAndImplementationRestarted(
        address beacon, address newImplementation, uint newMinorVersion
    );
    event BeaconImplementationRestarted(address beacon);
    event OwnershipAccepted(address adr);

    function setUp() public {
        gov = new GovernanceContract();
        gov.init(communityMultisig, teamMultisig, timelockPeriod);

        //Create beacon owned by governance contract
        ownedBeaconMock = new InverterBeaconOwnableMock(address(gov));

        //Create beacon not owned by governance contract
        unownedBeaconMock = new InverterBeaconOwnableMock(address(this));
    }

    //--------------------------------------------------------------------------
    // Test: SupportsInterface

    function testSupportsInterface() public {
        assertTrue(gov.supportsInterface(type(IGovernanceContract).interfaceId));
    }

    //--------------------------------------------------------------------------
    // Test: Modifier

    function testValidAddress(address adr) public {
        if (adr == address(0)) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernanceContract.InvalidAddress.selector, adr
                )
            );
        }

        vm.prank(communityMultisig);
        gov.setFeeManager(adr);
    }

    function testValidAmount(uint amt) public {
        if (amt == 0) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernanceContract.InvalidAmount.selector, amt
                )
            );
        }

        vm.prank(communityMultisig);
        gov.setTimelockPeriod(amt);
    }

    function testAccessableBeacon(uint seed, address target) public {
        bool shouldFail = true;
        //Restrict seed to one of 3 variants
        seed = bound(seed, 0, 2);
        //case 1
        if (seed == 0) {
            target = address(ownedBeaconMock);
            shouldFail = false;
        }
        //Case 2
        else if (seed == 1) {
            target = address(unownedBeaconMock);
        }
        //Case 3
        else {
            //Just make sure target is not one of the other ones
            vm.assume(target != address(ownedBeaconMock));
            vm.assume(target != address(unownedBeaconMock));
        }

        if (shouldFail) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernanceContract.BeaconNotAccessible.selector, target
                )
            );
        }
        vm.prank(address(communityMultisig));
        gov.upgradeBeaconWithTimelock(target, address(0x1), 0);
    }

    function testOnlyCommunityOrTeamMultisig(address sender) public {
        if (
            !gov.hasRole(gov.COMMUNITY_MULTISIG_ROLE(), sender)
                && !gov.hasRole(gov.TEAM_MULTISIG_ROLE(), sender)
        ) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernanceContract.OnlyCommunityOrTeamMultisig.selector
                )
            );
        }

        vm.prank(sender);
        gov.upgradeBeaconWithTimelock(
            address(ownedBeaconMock), address(0xBEEF), 2
        );
    }

    function testUpgradeProcessAlreadyStarted(bool processStarted) public {
        if (processStarted) {
            vm.prank(address(communityMultisig));
            gov.upgradeBeaconWithTimelock(
                address(ownedBeaconMock), address(0x1), 0
            );
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernanceContract.UpgradeProcessNotStarted.selector
                )
            );
        }

        vm.prank(communityMultisig);
        gov.cancelUpgrade(address(ownedBeaconMock));
    }

    function testTimelockPeriodExceeded(uint seed1, uint seed2) public {
        seed1 = bound(seed1, 0, 1_000_000 weeks);
        seed2 = bound(seed2, 0, 1000 days);
        //warp now to seed
        vm.warp(seed1);

        //Create Timelock
        vm.prank(address(communityMultisig));
        gov.upgradeBeaconWithTimelock(address(ownedBeaconMock), address(0x1), 0);

        //Wait seed2 time
        vm.warp(block.timestamp + seed2);

        //If waited time is smaller than timelock period throw error
        if (seed2 < timelockPeriod) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernanceContract.TimelockPeriodNotExceeded.selector
                )
            );
        }

        vm.prank(communityMultisig);
        gov.triggerUpgradeBeaconWithTimelock(address(ownedBeaconMock));
    }

    //--------------------------------------------------------------------------
    // Test: Init

    function testInit() public {
        //Assert Admin roles
        //COMMUNITY_MULTISIG_ROLE is its own admin
        assertEq(
            gov.getRoleAdmin(gov.COMMUNITY_MULTISIG_ROLE()),
            gov.COMMUNITY_MULTISIG_ROLE()
        );
        //COMMUNITY_MULTISIG_ROLE is its TEAM_MULTISIG_ROLE admin
        assertEq(
            gov.getRoleAdmin(gov.TEAM_MULTISIG_ROLE()),
            gov.COMMUNITY_MULTISIG_ROLE()
        );
        //COMMUNITY_MULTISIG_ROLE is its DEFAULT_ADMIN_ROLE admin
        assertEq(
            gov.getRoleAdmin(gov.DEFAULT_ADMIN_ROLE()),
            gov.COMMUNITY_MULTISIG_ROLE()
        );

        //Assert role distribution
        assertTrue(
            gov.hasRole(gov.COMMUNITY_MULTISIG_ROLE(), communityMultisig)
        );
        assertTrue(gov.hasRole(gov.TEAM_MULTISIG_ROLE(), teamMultisig));

        //assert timelock Period
        assertEq(gov.timelockPeriod(), timelockPeriod);
    }

    function testInitModifierInPosition() public {
        //initializer
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        gov.init(communityMultisig, teamMultisig, timelockPeriod);

        gov = new GovernanceContract();
        //validAddress(newCommunityMultisig)
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernanceContract.InvalidAddress.selector, address(0)
            )
        );
        gov.init(address(0), teamMultisig, timelockPeriod);

        //validAddress(newTeamMultisig)
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernanceContract.InvalidAddress.selector, address(0)
            )
        );
        gov.init(communityMultisig, address(0), timelockPeriod);

        //validAmount(newTimelockPeriod)
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernanceContract.InvalidAmount.selector, 0
            )
        );
        gov.init(communityMultisig, teamMultisig, 0);
    }

    //--------------------------------------------------------------------------
    // Test: Getter Functions

    function testGetBeaconTimelock() public {
        //Tivial Test
        //100% Testcoverage here we go xD
        gov.getBeaconTimelock(address(0));
    }

    //--------------------------------------------------------------------------
    // Test: FeeManager Functions

    function testGetFeeManager() public {
        //Tivial Test
        gov.getFeeManager();
    }

    function testSetFeeManagerModifierInPosition() public {
        //onlyRole(COMMUNITY_MULTISIG_ROLE)
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                gov.COMMUNITY_MULTISIG_ROLE()
            )
        );
        gov.setFeeManager(address(0x1));

        //validAddress(newFeeManager)
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernanceContract.InvalidAddress.selector, address(0)
            )
        );
        vm.prank(address(communityMultisig));
        gov.setFeeManager(address(0));
    }

    //--------------------------------------------------------------------------
    // Test: Beacon Functions

    //---------------------------
    // Upgrade

    function testUpgradeBeaconWithTimelock(
        uint seed,
        bytes32 salt,
        address newImplementation,
        uint newMinorVersion
    ) public {
        vm.assume(newImplementation != address(0));

        //To properly randomise Beacon deployment use create2 and salt
        address beacon = deployBeaconWithSaltAndTransferOwnershipToGov(salt);

        //Resonable warp
        vm.warp(bound(seed, 0, 1_000_000 weeks));

        vm.expectEmit(true, true, true, true);

        // We emit the event we expect to see.
        emit BeaconTimelockStarted(
            beacon,
            newImplementation,
            newMinorVersion,
            timelockPeriod + block.timestamp
        );
        vm.prank(address(communityMultisig));
        gov.upgradeBeaconWithTimelock(
            beacon, newImplementation, newMinorVersion
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
    }

    function testUpgradeBeaconWithTimelockModifierInPosition() public {
        //onlyCommunityOrTeamMultisig
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernanceContract.OnlyCommunityOrTeamMultisig.selector
            )
        );
        gov.upgradeBeaconWithTimelock(address(ownedBeaconMock), address(0x1), 0);

        //accessableBeacon(beacon)
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernanceContract.BeaconNotAccessible.selector, address(0)
            )
        );
        vm.prank(communityMultisig);
        gov.upgradeBeaconWithTimelock(address(0), address(0x1), 0);

        //validAddress(newImplementation)
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernanceContract.InvalidAddress.selector, address(0)
            )
        );
        vm.prank(communityMultisig);
        gov.upgradeBeaconWithTimelock(address(ownedBeaconMock), address(0), 0);
    }

    function testTriggerUpgradeBeaconWithTimelock() public {
        vm.prank(address(communityMultisig));
        gov.upgradeBeaconWithTimelock(address(ownedBeaconMock), address(0x1), 0);

        //Resonable warp
        vm.warp(block.timestamp + timelockPeriod + 1);

        vm.expectEmit(true, true, true, true);
        emit BeaconUpgraded(address(ownedBeaconMock), address(0x1), 0);

        vm.prank(address(communityMultisig));
        gov.triggerUpgradeBeaconWithTimelock(address(ownedBeaconMock));

        assertFalse(
            gov.getBeaconTimelock(address(ownedBeaconMock)).timelockActive
        );
        //Make sure ownedBeaconMock got called
        assertEq(ownedBeaconMock.functionCalled(), 1);
        assertEq(ownedBeaconMock.implementation(), address(0x1));
        assertEq(ownedBeaconMock.minorVersion(), 0);
        assertEq(ownedBeaconMock.forcefulCall(), false);
    }

    function testTriggerUpgradeBeaconWithTimelockModifierInPosition() public {
        //onlyCommunityOrTeamMultisig
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernanceContract.OnlyCommunityOrTeamMultisig.selector
            )
        );
        gov.triggerUpgradeBeaconWithTimelock(address(ownedBeaconMock));

        //accessableBeacon(beacon)
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernanceContract.BeaconNotAccessible.selector, address(0)
            )
        );
        vm.prank(communityMultisig);
        gov.triggerUpgradeBeaconWithTimelock(address(0));

        //upgradeProcessAlreadyStarted(beacon)

        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernanceContract.UpgradeProcessNotStarted.selector
            )
        );
        vm.prank(communityMultisig);
        gov.triggerUpgradeBeaconWithTimelock(address(ownedBeaconMock));

        //timelockPeriodExceeded(beacon)

        vm.prank(communityMultisig);
        gov.upgradeBeaconWithTimelock(address(ownedBeaconMock), address(0x1), 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernanceContract.TimelockPeriodNotExceeded.selector
            )
        );
        vm.prank(communityMultisig);
        gov.triggerUpgradeBeaconWithTimelock(address(ownedBeaconMock));
    }

    function testCancelUpgrade() public {
        vm.prank(address(communityMultisig));
        gov.upgradeBeaconWithTimelock(address(ownedBeaconMock), address(0x1), 0);

        //Resonable warp
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
        //onlyCommunityOrTeamMultisig
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernanceContract.OnlyCommunityOrTeamMultisig.selector
            )
        );
        gov.cancelUpgrade(address(ownedBeaconMock));

        //upgradeProcessAlreadyStarted(beacon)

        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernanceContract.UpgradeProcessNotStarted.selector
            )
        );
        vm.prank(communityMultisig);
        gov.cancelUpgrade(address(ownedBeaconMock));
    }

    function testSetTimelockPeriodModifierInPosition() public {
        //onlyRole(COMMUNITY_MULTISIG_ROLE)
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                gov.COMMUNITY_MULTISIG_ROLE()
            )
        );
        gov.setTimelockPeriod(1);

        //validAmount(newTimelockPeriod)
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernanceContract.InvalidAmount.selector, 0
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

        //Make sure ownedBeaconMock got called
        assertEq(ownedBeaconMock.functionCalled(), 1);
    }

    function testInitiateBeaconShutdownModifierInPosition() public {
        //onlyCommunityOrTeamMultisig
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernanceContract.OnlyCommunityOrTeamMultisig.selector
            )
        );
        gov.initiateBeaconShutdown(address(ownedBeaconMock));

        //accessableBeacon(beacon)
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernanceContract.BeaconNotAccessible.selector,
                address(unownedBeaconMock)
            )
        );
        vm.prank(communityMultisig);
        gov.initiateBeaconShutdown(address(unownedBeaconMock));
    }

    function testForceUpgradeBeaconAndRestartImplementation() public {
        vm.expectEmit(true, true, true, true);
        emit BeaconForcefullyUpgradedAndImplementationRestarted(
            address(ownedBeaconMock), address(0x1), 0
        );

        vm.prank(address(communityMultisig));
        gov.forceUpgradeBeaconAndRestartImplementation(
            address(ownedBeaconMock), address(0x1), 0
        );

        assertFalse(
            gov.getBeaconTimelock(address(ownedBeaconMock)).timelockActive
        );
        //Make sure ownedBeaconMock got called
        assertEq(ownedBeaconMock.functionCalled(), 1);
        assertEq(ownedBeaconMock.implementation(), address(0x1));
        assertEq(ownedBeaconMock.minorVersion(), 0);
        assertEq(ownedBeaconMock.forcefulCall(), true);
    }

    function testForceUpgradeBeaconAndRestartImplementationModifierInPosition()
        public
    {
        //onlyRole(COMMUNITY_MULTISIG_ROLE)
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                gov.COMMUNITY_MULTISIG_ROLE()
            )
        );
        gov.forceUpgradeBeaconAndRestartImplementation(
            address(ownedBeaconMock), address(0x1), 0
        );

        //accessableBeacon(beacon)
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernanceContract.BeaconNotAccessible.selector, address(0)
            )
        );
        vm.prank(communityMultisig);
        gov.forceUpgradeBeaconAndRestartImplementation(
            address(0), address(0x1), 0
        );

        //validAddress(newImplementation)
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernanceContract.InvalidAddress.selector, address(0)
            )
        );
        vm.prank(communityMultisig);
        gov.forceUpgradeBeaconAndRestartImplementation(
            address(ownedBeaconMock), address(0), 0
        );
    }

    function testRestartBeaconImplementation() public {
        vm.expectEmit(true, true, true, true);
        emit BeaconImplementationRestarted(address(ownedBeaconMock));

        vm.prank(address(communityMultisig));
        gov.restartBeaconImplementation(address(ownedBeaconMock));

        //Make sure ownedBeaconMock got called
        assertEq(ownedBeaconMock.functionCalled(), 1);
    }

    function testRestartBeaconImplementationModifierInPosition() public {
        //onlyRole(COMMUNITY_MULTISIG_ROLE)
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                gov.COMMUNITY_MULTISIG_ROLE()
            )
        );
        gov.restartBeaconImplementation(address(ownedBeaconMock));

        //accessableBeacon(beacon)
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernanceContract.BeaconNotAccessible.selector,
                address(unownedBeaconMock)
            )
        );
        vm.prank(communityMultisig);
        gov.restartBeaconImplementation(address(unownedBeaconMock));
    }

    //--------------------------------------------------------------------------
    // Test: Ownable2Step Functions

    function testAcceptOwnership(bytes32 _salt) public {
        //onlyCommunityOrTeamMultisig
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernanceContract.OnlyCommunityOrTeamMultisig.selector
            )
        );
        gov.acceptOwnership(address(unownedBeaconMock));
    }

    function testAcceptOwnership(uint seed, address target) public {
        bool shouldFail = true;
        //Restrict seed to one of 3 variants
        seed = bound(seed, 0, 2);
        //case 1 Can change ownership
        if (seed == 0) {
            //Prepare beacon to tranfer ownership
            unownedBeaconMock.transferOwnership(address(gov));
            target = address(unownedBeaconMock);
            shouldFail = false;
        }
        //Case 2 cannot change ownership
        else if (seed == 1) {
            target = address(unownedBeaconMock);
        }
        //Case 3 is not a contract
        else {
            vm.assume(target.code.length != 0);
        }

        if (shouldFail) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernanceContract.CallToTargetContractFailed.selector
                )
            );
        }
        vm.prank(address(communityMultisig));
        gov.acceptOwnership(target);
    }

    function testAcceptOwnershipModifierInPosition() public {
        //onlyCommunityOrTeamMultisig
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernanceContract.OnlyCommunityOrTeamMultisig.selector
            )
        );
        gov.acceptOwnership(address(unownedBeaconMock));
    }

    //--------------------------------------------------------------------------
    // Helper Functions

    function deployBeaconWithSaltAndTransferOwnershipToGov(bytes32 _salt)
        internal
        returns (address)
    {
        // This syntax is a newer way to invoke create2 without assembly, you just need to pass salt
        InverterBeaconOwnableMock mock =
            new InverterBeaconOwnableMock{salt: _salt}(address(gov));

        return address(mock);
    }
}
