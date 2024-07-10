// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IGovernor_v1} from "@ex/governance/interfaces/IGovernor_v1.sol";
import {IFeeManager_v1} from "@ex/fees/interfaces/IFeeManager_v1.sol";
import {IInverterBeacon_v1} from "src/proxies/interfaces/IInverterBeacon_v1.sol";
import {
    IModuleFactory_v1,
    IModule_v1
} from "src/factories/interfaces/IModuleFactory_v1.sol";

// Internal Dependencies
import {InverterBeacon_v1} from "src/proxies/InverterBeacon_v1.sol";

// External Dependencies
import {ERC165} from "@oz/utils/introspection/ERC165.sol";
import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from
    "@oz-up/access/AccessControlUpgradeable.sol";
import {Ownable2Step} from "@oz/access/Ownable2Step.sol";

/**
 * @title   Governor Contract
 *
 * @notice  This contract manages various administrative functions that can be executed only by
 *          specified multisig addresses. It supports upgrades to beacon contracts through
 *          role-based permissions, enabling a timelocked upgrade process and emergency procedures.
 *
 *  @dev    Inherits from {ERC165} for interface detection, {AccessControlUpgradeable} for role-based
 *          access control, and implements the {IGovernor_v1} interface for governance
 *          functionalities, i.e. setting the fee manager, setting the timelock, upgrading the
 *          beacons and exposing the emergency shutdown.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 */
contract Governor_v1 is ERC165, IGovernor_v1, AccessControlUpgradeable {
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlUpgradeable, ERC165)
        returns (bool)
    {
        return interfaceId == type(IGovernor_v1).interfaceId
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
        // if timelock not active
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

    IFeeManager_v1 private feeManager;

    uint public timelockPeriod;

    mapping(address => IGovernor_v1.Timelock) private beaconTimelock;

    // Storage gap for future upgrades
    uint[50] private __gap;

    //--------------------------------------------------------------------------
    // Constructor

    constructor() {
        _disableInitializers();
    }

    //--------------------------------------------------------------------------
    // Initialization

    /// @notice The module's initializer function.
    /// @param newCommunityMultisig The address of the community multisig
    /// @param newTeamMultisig The address of the team multisig
    /// @param newTimelockPeriod The timelock period needed to upgrade a beacon
    function init(
        address newCommunityMultisig,
        address newTeamMultisig,
        uint newTimelockPeriod,
        address initialFeeManager
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

        _setFeeManager(initialFeeManager);
    }

    //--------------------------------------------------------------------------
    // Getter Functions

    /// @inheritdoc IGovernor_v1
    function getBeaconTimelock(address beacon)
        external
        view
        returns (Timelock memory)
    {
        return beaconTimelock[beacon];
    }

    //--------------------------------------------------------------------------
    // FeeManager Functions

    /// @inheritdoc IGovernor_v1
    function getFeeManager() external view returns (address) {
        return address(feeManager);
    }

    /// @inheritdoc IGovernor_v1
    function setFeeManager(address newFeeManager)
        external
        onlyRole(COMMUNITY_MULTISIG_ROLE)
    {
        _setFeeManager(newFeeManager);
    }

    /// @inheritdoc IGovernor_v1
    function setFeeManagerMaxFee(uint maxFee)
        external
        onlyRole(COMMUNITY_MULTISIG_ROLE)
    {
        feeManager.setMaxFee(maxFee);
    }

    /// @inheritdoc IGovernor_v1
    function setFeeManagerDefaultProtocolTreasury(
        address _defaultProtocolTreasury
    ) external onlyRole(COMMUNITY_MULTISIG_ROLE) {
        feeManager.setDefaultProtocolTreasury(_defaultProtocolTreasury);
    }

    /// @inheritdoc IGovernor_v1
    function setFeeManagerWorkflowTreasuries(address workflow, address treasury)
        external
        onlyRole(COMMUNITY_MULTISIG_ROLE)
    {
        feeManager.setWorkflowTreasury(workflow, treasury);
    }

    /// @inheritdoc IGovernor_v1
    function setFeeManagerDefaultCollateralFee(uint _defaultCollateralFee)
        external
        onlyRole(COMMUNITY_MULTISIG_ROLE)
    {
        feeManager.setDefaultCollateralFee(_defaultCollateralFee);
    }

    /// @inheritdoc IGovernor_v1
    function setFeeManagerDefaultIssuanceFee(uint _defaultIssuanceFee)
        external
        onlyRole(COMMUNITY_MULTISIG_ROLE)
    {
        feeManager.setDefaultIssuanceFee(_defaultIssuanceFee);
    }

    /// @inheritdoc IGovernor_v1
    function setFeeManagerCollateralWorkflowFee(
        address workflow,
        address module,
        bytes4 functionSelector,
        bool set,
        uint fee
    ) external onlyCommunityOrTeamMultisig {
        feeManager.setCollateralWorkflowFee(
            workflow, module, functionSelector, set, fee
        );
    }

    /// @inheritdoc IGovernor_v1
    function setFeeManagerIssuanceWorkflowFee(
        address workflow,
        address module,
        bytes4 functionSelector,
        bool set,
        uint fee
    ) external onlyCommunityOrTeamMultisig {
        feeManager.setIssuanceWorkflowFee(
            workflow, module, functionSelector, set, fee
        );
    }

    //--------------------------------------------------------------------------
    // Factory Functions

    /// @inheritdoc IGovernor_v1
    function registerMetadataInModuleFactory(
        IModuleFactory_v1 moduleFactory,
        IModule_v1.Metadata memory metadata,
        IInverterBeacon_v1 beacon
    ) external onlyCommunityOrTeamMultisig {
        moduleFactory.registerMetadata(metadata, beacon);
    }

    //--------------------------------------------------------------------------
    // Beacon Functions
    //---------------------------
    // Upgrade

    /// @inheritdoc IGovernor_v1
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

    /// @inheritdoc IGovernor_v1
    function triggerUpgradeBeaconWithTimelock(address beacon)
        external
        onlyCommunityOrTeamMultisig
        accessibleBeacon(beacon)
        upgradeProcessAlreadyStarted(beacon)
        timelockPeriodExceeded(beacon)
    {
        // set timelock to inactive
        beaconTimelock[beacon].timelockActive = false;

        // Upgrade beacon
        IInverterBeacon_v1(beacon).upgradeTo(
            beaconTimelock[beacon].intendedImplementation,
            beaconTimelock[beacon].intendedMinorVersion,
            false // this is not intended to override a shutdown
        );

        emit BeaconUpgraded(
            beacon,
            beaconTimelock[beacon].intendedImplementation,
            beaconTimelock[beacon].intendedMinorVersion
        );
    }

    /// @inheritdoc IGovernor_v1
    function cancelUpgrade(address beacon)
        external
        onlyCommunityOrTeamMultisig
        upgradeProcessAlreadyStarted(beacon)
    {
        beaconTimelock[beacon].timelockActive = false;
        emit BeaconUpgradedCanceled(beacon);
    }

    /// @inheritdoc IGovernor_v1
    function setTimelockPeriod(uint newTimelockPeriod)
        external
        onlyRole(COMMUNITY_MULTISIG_ROLE)
        validTimelockPeriod(newTimelockPeriod)
    {
        timelockPeriod = newTimelockPeriod;
        emit TimelockPeriodSet(newTimelockPeriod);
    }

    //---------------------------
    // Emergency Shutdown

    /// @inheritdoc IGovernor_v1
    function initiateBeaconShutdown(address beacon)
        external
        onlyCommunityOrTeamMultisig
        accessibleBeacon(beacon)
    {
        IInverterBeacon_v1(beacon).shutDownImplementation();
        emit BeaconShutdownInitiated(beacon);
    }

    /// @inheritdoc IGovernor_v1
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
        IInverterBeacon_v1(beacon).upgradeTo(
            newImplementation, newMinorVersion, true
        );
        emit BeaconForcefullyUpgradedAndImplementationRestarted(
            beacon, newImplementation, newMinorVersion
        );
    }

    /// @inheritdoc IGovernor_v1
    function restartBeaconImplementation(address beacon)
        external
        onlyRole(COMMUNITY_MULTISIG_ROLE)
        accessibleBeacon(beacon)
    {
        IInverterBeacon_v1(beacon).restartImplementation();
        emit BeaconImplementationRestarted(beacon);
    }

    //---------------------------
    // Ownable2Step

    /// @inheritdoc IGovernor_v1
    function acceptOwnership(address adr)
        external
        onlyCommunityOrTeamMultisig
    {
        if (adr.code.length == 0) {
            revert Governor__CallToTargetContractFailed();
        }

        (bool success,) =
            adr.call(abi.encodeCall(Ownable2Step.acceptOwnership, ()));

        // if the call is not a success
        if (!success) {
            revert Governor__CallToTargetContractFailed();
        }
        emit OwnershipAccepted(adr);
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @dev sets the internal FeeManager address
    /// @param newFeeManager the address of the new feeManager
    function _setFeeManager(address newFeeManager)
        internal
        validAddress(newFeeManager)
    {
        feeManager = IFeeManager_v1(newFeeManager);
    }

    //@dev internal function that checks if target address is a beacon and this contract has the ownership of it
    function isBeaconAccessible(address target) internal returns (bool) {
        // check if target is a contract
        if (target.code.length == 0) {
            return false;
        }

        // Check if target address supports Inverter beacon interface
        (bool success, bytes memory result) = target.call(
            abi.encodeCall(
                InverterBeacon_v1.supportsInterface,
                (type(IInverterBeacon_v1).interfaceId)
            )
        );

        // if target does not support the beacon interface return false
        if (!(success && result.length != 0 && abi.decode(result, (bool)))) {
            return false;
        }

        // Check if target is ownable and who the owner is
        (success, result) = target.call(abi.encodeWithSignature("owner()"));

        // if not ownable or owner is not this contract return false
        if (
            !(
                success && result.length != 0
                    && address(this) == abi.decode(result, (address))
            )
        ) return false;

        // we are here, that means target is owned by this address and inverter beacon
        return true;
    }
}
