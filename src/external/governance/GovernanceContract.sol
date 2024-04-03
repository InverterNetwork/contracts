// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IGovernanceContract} from
    "src/external/governance/IGovernanceContract.sol";
import {
    InverterBeacon,
    IInverterBeacon
} from "src/factories/beacon/InverterBeacon.sol";

// External Dependencies
import {ERC165} from "@oz/utils/introspection/ERC165.sol";
import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";
import {AccessControl} from "@oz/access/AccessControl.sol";
import {Ownable} from "@oz/access/Ownable.sol";
import {Ownable2Step} from "@oz/access/Ownable2Step.sol";

contract GovernanceContract is
    ERC165,
    IGovernanceContract,
    Initializable,
    AccessControl
{
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControl, ERC165)
        returns (bool)
    {
        return interfaceId == type(IGovernanceContract).interfaceId
            || super.supportsInterface(interfaceId);
    }
    //--------------------------------------------------------------------------
    // Modifier

    modifier validAddress(address adr) {
        if (adr == address(0)) {
            revert IGovernanceContract.InvalidAddress(adr);
        }
        _;
    }

    modifier validAmount(uint amt) {
        if (amt == 0) {
            revert IGovernanceContract.InvalidAmount(amt);
        }
        _;
    }

    modifier accessableBeacon(address beacon) {
        if (
            !supportsInterface(type(IInverterBeacon).interfaceId)
                && Ownable(beacon).owner() != address(this)
        ) {
            revert IGovernanceContract.BeaconNotAccessible(beacon);
        }
        _;
    }

    modifier onlyCommunityOrTeamMultisig() {
        address sender = _msgSender();
        if (
            !hasRole(COMMUNITY_MULTISIG_ROLE, sender)
                && !hasRole(COMMUNITY_MULTISIG_ROLE, sender)
        ) {
            revert IGovernanceContract.OnlyCommunityOrTeamMultisig();
        }
        _;
    }

    modifier timelockPeriodExceeded(address beacon) {
        if (block.timestamp < beaconTimelock[beacon].timelockUntil) {
            revert IGovernanceContract.timelockPeriodNotExceeded();
        }
        _;
    }

    modifier upgradeProcessAlreadyStarted(address beacon) {
        //if timelock not active
        if (!beaconTimelock[beacon].timelockActive) {
            revert IGovernanceContract.upgradeProcessNotStarted();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    bytes32 public constant COMMUNITY_MULTISIG_ROLE = "0x01";
    bytes32 public constant TEAM_MULTISIG_ROLE = "0x02";

    address private feeManager;

    uint public timelockPeriod;

    mapping(address => IGovernanceContract.Timelock) public beaconTimelock;

    //--------------------------------------------------------------------------
    // Initialization

    /// @notice The module's initializer function.
    /// @param newCommunityMultisig The address of the community multisig
    /// @param newTeamMultisig The address of the team multisig
    /// @param newTimelockPeriod The timelock period needed to upgrade a beacon
    function init(
        address newCommunityMultisig,
        address newTeamMultisig,
        uint newTimelockPeriod //@note should we add feeManager here?
    ) external onlyInitializing {
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
    // Functions

    //--------------------------------------------------------------------------
    // FeeManager

    /// @inheritdoc IGovernanceContract
    function getFeeManager() external returns (address) {
        return feeManager;
    }

    /// @inheritdoc IGovernanceContract
    function setFeeManager(address newFeeManager)
        external
        validAddress(newFeeManager)
        onlyRole(COMMUNITY_MULTISIG_ROLE)
    {
        feeManager = newFeeManager;
    }

    //--------------------------------------------------------------------------
    // Beacon Functions
    //---------------------------
    // Upgrade

    /// @inheritdoc IGovernanceContract
    function upgradeBeaconWithTimelock(
        address beacon,
        address newImplementation,
        uint newMinorVersion
    )
        external
        onlyCommunityOrTeamMultisig
        accessableBeacon(beacon)
        validAddress(newImplementation)
    {
        beaconTimelock[beacon] = Timelock(
            true,
            block.timestamp + timelockPeriod,
            newImplementation,
            newMinorVersion
        );

        emit BeaconTimelockStarted(beacon, newImplementation, newMinorVersion);
    }

    /// @inheritdoc IGovernanceContract
    function triggerUpgradeBeaconWithTimelock(address beacon)
        external
        onlyCommunityOrTeamMultisig
        accessableBeacon(beacon)
        upgradeProcessAlreadyStarted(beacon)
        timelockPeriodExceeded(beacon)
    {
        IInverterBeacon(beacon).upgradeTo(
            beaconTimelock[beacon].intendedImplementation,
            beaconTimelock[beacon].intendedMinorVersion,
            false //this is not intended to override a shutdown
        );
        emit BeaconUpgraded(
            beacon,
            beaconTimelock[beacon].intendedImplementation, //@todo optimise
            beaconTimelock[beacon].intendedMinorVersion
        );
    }

    /// @inheritdoc IGovernanceContract
    function cancelUpgrade(address beacon)
        external
        onlyCommunityOrTeamMultisig
        upgradeProcessAlreadyStarted(beacon)
    {
        beaconTimelock[beacon].timelockActive = false;
        emit BeaconUpgradedCanceled(beacon);
    }

    /// @inheritdoc IGovernanceContract
    function setTimelockPeriod(uint newTimelockPeriod)
        external
        onlyRole(COMMUNITY_MULTISIG_ROLE)
        validAmount(newTimelockPeriod)
    {
        timelockPeriod = newTimelockPeriod;
        emit TimelockPeriodSet(newTimelockPeriod);
    }

    //---------------------------
    //Emergency Shutdown

    /// @inheritdoc IGovernanceContract
    function initiateBeaconShutdown(address beacon)
        external
        onlyCommunityOrTeamMultisig
        accessableBeacon(beacon)
    {
        IInverterBeacon(beacon).shutDownImplementation();
        emit BeaconShutdownInitiated(beacon);
    }

    /// @inheritdoc IGovernanceContract
    function forceUpgradeBeaconAndRestartImplementation(
        address beacon,
        address newImplementation,
        uint newMinorVersion
    ) external onlyRole(COMMUNITY_MULTISIG_ROLE) accessableBeacon(beacon) {
        IInverterBeacon(beacon).upgradeTo(
            newImplementation, newMinorVersion, true
        );
        emit BeaconForcefullyUpgradedAndImplementationRestarted(
            beacon, newImplementation, newMinorVersion
        );
    }

    /// @inheritdoc IGovernanceContract
    function restartBeaconImplementation(address beacon)
        external
        onlyRole(COMMUNITY_MULTISIG_ROLE)
        accessableBeacon(beacon)
    {
        IInverterBeacon(beacon).restartImplementation();
        emit BeaconImplementationRestarted(beacon);
    }

    //---------------------------
    //Ownable2Step

    /// @inheritdoc IGovernanceContract
    function acceptOwnership(address adr)
        external
        onlyCommunityOrTeamMultisig //@note correct Role?
    {
        (bool success,) =
            adr.call(abi.encodeCall(Ownable2Step.acceptOwnership, ()));
        if (!success) {
            revert IGovernanceContract.CallToTargetContractFailed();
        }
        emit OwnershipAccepted(adr);
    }
}
