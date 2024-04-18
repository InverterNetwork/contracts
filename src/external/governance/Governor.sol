// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IGovernor} from "src/external/governance/IGovernor.sol";
import {
    InverterBeacon,
    IInverterBeacon
} from "src/factories/beacon/InverterBeacon.sol";

// External Dependencies
import {ERC165} from "@oz/utils/introspection/ERC165.sol";
import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from
    "@oz-up/access/AccessControlUpgradeable.sol";
import {Ownable2Step} from "@oz/access/Ownable2Step.sol";

contract Governor is ERC165, IGovernor, AccessControlUpgradeable {
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlUpgradeable, ERC165)
        returns (bool)
    {
        return interfaceId == type(IGovernor).interfaceId
            || super.supportsInterface(interfaceId);
    }
    //--------------------------------------------------------------------------
    // Modifier

    modifier validAddress(address adr) {
        if (adr == address(0)) {
            revert Governor__InvalidAddress(adr);
        }
        _;
    }

    modifier validTimelockPeriod(uint amt) {
        if (amt < 48 hours) {
            revert Governor__InvalidTimelockPeriod(amt);
        }
        _;
    }

    modifier accessibleBeacon(address target) {
        if (!isBeaconAccessible(target)) {
            revert Governor__BeaconNotAccessible(target);
        }

        _;
    }

    modifier onlyCommunityOrTeamMultisig() {
        address sender = _msgSender();
        if (
            !hasRole(COMMUNITY_MULTISIG_ROLE, sender)
                && !hasRole(TEAM_MULTISIG_ROLE, sender)
        ) {
            revert Governor__OnlyCommunityOrTeamMultisig();
        }
        _;
    }

    modifier upgradeProcessAlreadyStarted(address beacon) {
        //if timelock not active
        if (!beaconTimelock[beacon].timelockActive) {
            revert Governor__UpgradeProcessNotStarted();
        }
        _;
    }

    modifier timelockPeriodExceeded(address beacon) {
        if (block.timestamp < beaconTimelock[beacon].timelockUntil) {
            revert Governor__TimelockPeriodNotExceeded();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    bytes32 public constant COMMUNITY_MULTISIG_ROLE = "0x01";
    bytes32 public constant TEAM_MULTISIG_ROLE = "0x02";

    address private taxMan;

    uint public timelockPeriod;

    mapping(address => IGovernor.Timelock) private beaconTimelock;

    //--------------------------------------------------------------------------
    // Initialization

    /// @notice The module's initializer function.
    /// @param newCommunityMultisig The address of the community multisig
    /// @param newTeamMultisig The address of the team multisig
    /// @param newTimelockPeriod The timelock period needed to upgrade a beacon
    function init(
        address newCommunityMultisig,
        address newTeamMultisig,
        uint newTimelockPeriod
    )
        external
        initializer
        validAddress(newCommunityMultisig)
        validAddress(newTeamMultisig)
        validTimelockPeriod(newTimelockPeriod)
    {
        __AccessControl_init();

        // -> set COMMUNITY_MULTISIG_ROLE as admin of itself
        _setRoleAdmin(COMMUNITY_MULTISIG_ROLE, COMMUNITY_MULTISIG_ROLE);
        // -> set COMMUNITY_MULTISIG_ROLE as admin of DEFAULT_ADMIN_ROLE
        _setRoleAdmin(DEFAULT_ADMIN_ROLE, COMMUNITY_MULTISIG_ROLE);

        // Set up TEAM_MULTISIG_ROLE role structure:
        // -> set COMMUNITY_MULTISIG_ROLE as admin of TEAM_MULTISIG_ROLE
        _setRoleAdmin(TEAM_MULTISIG_ROLE, COMMUNITY_MULTISIG_ROLE);

        // grant COMMUNITY_MULTISIG_ROLE to specified address
        _grantRole(COMMUNITY_MULTISIG_ROLE, newCommunityMultisig);
        // grant COMMUNITY_MULTISIG_ROLE to specified address
        _grantRole(TEAM_MULTISIG_ROLE, newTeamMultisig);

        timelockPeriod = newTimelockPeriod;
    }

    //--------------------------------------------------------------------------
    // Getter Functions

    /// @inheritdoc IGovernor
    function getBeaconTimelock(address beacon)
        external
        view
        returns (Timelock memory)
    {
        return beaconTimelock[beacon];
    }

    //--------------------------------------------------------------------------
    // TaxMan Functions

    /// @inheritdoc IGovernor
    function getTaxMan() external view returns (address) {
        return taxMan;
    }

    /// @inheritdoc IGovernor
    function setTaxMan(address newTaxMan)
        external
        onlyRole(COMMUNITY_MULTISIG_ROLE)
        validAddress(newTaxMan)
    {
        taxMan = newTaxMan;
    }

    //--------------------------------------------------------------------------
    // Beacon Functions
    //---------------------------
    // Upgrade

    /// @inheritdoc IGovernor
    function upgradeBeaconWithTimelock(
        address beacon,
        address newImplementation,
        uint newMinorVersion
    )
        external
        onlyCommunityOrTeamMultisig
        accessibleBeacon(beacon)
        validAddress(newImplementation)
    {
        beaconTimelock[beacon] = Timelock(
            true,
            block.timestamp + timelockPeriod,
            newImplementation,
            newMinorVersion
        );

        emit BeaconTimelockStarted(
            beacon,
            newImplementation,
            newMinorVersion,
            block.timestamp + timelockPeriod
        );
    }

    /// @inheritdoc IGovernor
    function triggerUpgradeBeaconWithTimelock(address beacon)
        external
        onlyCommunityOrTeamMultisig
        accessibleBeacon(beacon)
        upgradeProcessAlreadyStarted(beacon)
        timelockPeriodExceeded(beacon)
    {
        //set timelock to inactive
        beaconTimelock[beacon].timelockActive = false;

        //Upgrade beacon
        IInverterBeacon(beacon).upgradeTo(
            beaconTimelock[beacon].intendedImplementation,
            beaconTimelock[beacon].intendedMinorVersion,
            false //this is not intended to override a shutdown
        );

        emit BeaconUpgraded(
            beacon,
            beaconTimelock[beacon].intendedImplementation,
            beaconTimelock[beacon].intendedMinorVersion
        );
    }

    /// @inheritdoc IGovernor
    function cancelUpgrade(address beacon)
        external
        onlyCommunityOrTeamMultisig
        upgradeProcessAlreadyStarted(beacon)
    {
        beaconTimelock[beacon].timelockActive = false;
        emit BeaconUpgradedCanceled(beacon);
    }

    /// @inheritdoc IGovernor
    function setTimelockPeriod(uint newTimelockPeriod)
        external
        onlyRole(COMMUNITY_MULTISIG_ROLE)
        validTimelockPeriod(newTimelockPeriod)
    {
        timelockPeriod = newTimelockPeriod;
        emit TimelockPeriodSet(newTimelockPeriod);
    }

    //---------------------------
    //Emergency Shutdown

    /// @inheritdoc IGovernor
    function initiateBeaconShutdown(address beacon)
        external
        onlyCommunityOrTeamMultisig
        accessibleBeacon(beacon)
    {
        IInverterBeacon(beacon).shutDownImplementation();
        emit BeaconShutdownInitiated(beacon);
    }

    /// @inheritdoc IGovernor
    function forceUpgradeBeaconAndRestartImplementation(
        address beacon,
        address newImplementation,
        uint newMinorVersion
    )
        external
        onlyRole(COMMUNITY_MULTISIG_ROLE)
        accessibleBeacon(beacon)
        validAddress(newImplementation)
    {
        IInverterBeacon(beacon).upgradeTo(
            newImplementation, newMinorVersion, true
        );
        emit BeaconForcefullyUpgradedAndImplementationRestarted(
            beacon, newImplementation, newMinorVersion
        );
    }

    /// @inheritdoc IGovernor
    function restartBeaconImplementation(address beacon)
        external
        onlyRole(COMMUNITY_MULTISIG_ROLE)
        accessibleBeacon(beacon)
    {
        IInverterBeacon(beacon).restartImplementation();
        emit BeaconImplementationRestarted(beacon);
    }

    //---------------------------
    //Ownable2Step

    /// @inheritdoc IGovernor
    function acceptOwnership(address adr)
        external
        onlyCommunityOrTeamMultisig
    {
        if (adr.code.length == 0) {
            revert Governor__CallToTargetContractFailed();
        }

        (bool success,) =
            adr.call(abi.encodeCall(Ownable2Step.acceptOwnership, ()));

        //if the call is not a success
        if (!success) {
            revert Governor__CallToTargetContractFailed();
        }
        emit OwnershipAccepted(adr);
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    //@dev internal function that checks if target address is a beacon and this contract has the ownership of it
    function isBeaconAccessible(address target) internal returns (bool) {
        //check if target is a contract
        if (target.code.length == 0) {
            return false;
        }

        //Check if target address supports Inverter beacon interface
        (bool success, bytes memory result) = target.call(
            abi.encodeCall(
                InverterBeacon.supportsInterface,
                (type(IInverterBeacon).interfaceId)
            )
        );

        //if target does not support the beacon interface return false
        if (!(success && result.length != 0 && abi.decode(result, (bool)))) {
            return false;
        }

        //Check if target is ownable and who the owner is
        (success, result) = target.call(abi.encodeWithSignature("owner()"));

        //if not ownable or owner is not this contract return false
        if (
            !(
                success && result.length != 0
                    && address(this) == abi.decode(result, (address))
            )
        ) return false;

        //we are here, that means target is owned by this address and inverter beacon
        return true;
    }
}
