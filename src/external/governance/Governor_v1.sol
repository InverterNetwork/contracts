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
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";
import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from
    "@oz-up/access/AccessControlUpgradeable.sol";
import {Ownable2Step} from "@oz/access/Ownable2Step.sol";

/**
 * @title   Inverter Governor Contract
 *
 * @notice  This contract manages various administrative functions that can be executed only by
 *          specified multisig addresses. It supports upgrades to {IInverterBeacon_v1} contracts through
 *          role-based permissions, enabling a timelocked upgrade process and emergency procedures.
 *
 *  @dev    Inherits from {ERC165Upgradeable} for interface detection, {AccessControlUpgradeable} for role-based
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
contract Governor_v1 is
    ERC165Upgradeable,
    IGovernor_v1,
    AccessControlUpgradeable
{
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlUpgradeable, ERC165Upgradeable)
        returns (bool)
    {
        return interfaceId == type(IGovernor_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }
    //--------------------------------------------------------------------------
    // Modifier

    /// @dev	Modifier to guarantee function is only callable by the linked {ModuleFactory_v1}.
    modifier onlyLinkedModuleFactory() {
        if (_msgSender() != address(moduleFactory)) {
            revert Governor__OnlyLinkedModuleFactory();
        }
        _;
    }

    /// @dev	Modifier to guarantee linked {IInverterBeacon_v1}s are not empty.
    modifier linkedBeaconsEmpty() {
        if (linkedBeacons.length != 0) {
            revert Governor__LinkedBeaconsNotEmpty();
        }
        _;
    }

    /// @dev	Modifier to guarantee the given address is valid.
    modifier validAddress(address adr) {
        if (adr == address(0)) {
            revert Governor__InvalidAddress(adr);
        }
        _;
    }

    /// @dev	Modifier to guarantee the given timelock period is valid.
    modifier validTimelockPeriod(uint amt) {
        if (amt < 48 hours) {
            revert Governor__InvalidTimelockPeriod(amt);
        }
        _;
    }

    /// @dev	Modifier to guarantee the given {IInverterBeacon_v1} is accessible.
    modifier accessibleBeacon(address target) {
        if (!_isBeaconAccessible(target)) {
            revert Governor__BeaconNotAccessible(target);
        }

        _;
    }

    /// @dev	Modifier to guarantee only the community or team multisig can call the function.
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

    /// @dev	Modifier to check if the upgrade process for the given {IInverterBeacon_v1} is already started.
    modifier upgradeProcessAlreadyStarted(address beacon) {
        // if timelock not active
        if (!beaconTimelock[beacon].timelockActive) {
            revert Governor__UpgradeProcessNotStarted();
        }
        _;
    }

    /// @dev	Modifier to check if the timelock period for the given {IInverterBeacon_v1} is exceeded.
    modifier timelockPeriodExceeded(address beacon) {
        if (block.timestamp < beaconTimelock[beacon].timelockUntil) {
            revert Governor__TimelockPeriodNotExceeded();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    /// @dev	Role of the community multisig.
    bytes32 public constant COMMUNITY_MULTISIG_ROLE = "0x01";
    /// @dev	Role of the team multisig.
    bytes32 public constant TEAM_MULTISIG_ROLE = "0x02";

    /// @dev	{FeeManager_v1} contract.
    IFeeManager_v1 private feeManager;
    /// @dev	{ModuleFactory_v1} contract.
    IModuleFactory_v1 private moduleFactory;

    /// @dev	Array of {IInverterBeacon_v1}s that are linked to this {Governor_v1},
    ///         populated via `moduleFactoryInitCallback`.
    IInverterBeacon_v1[] private linkedBeacons;

    /// @dev    Length of each timelock.
    uint public timelockPeriod;
    /// @dev    Struct to store timelock information for each {IInverterBeacon_v1}.
    mapping(address beacon => IGovernor_v1.Timelock timelock) private
        beaconTimelock;

    /// @dev    Storage gap for future upgrades.
    uint[50] private __gap;

    //--------------------------------------------------------------------------
    // Constructor

    constructor() {
        _disableInitializers();
    }

    //--------------------------------------------------------------------------
    // Initialization

    /// @inheritdoc IGovernor_v1
    function init(
        address _communityMultisig,
        address _teamMultisig,
        uint _timelockPeriod,
        address _feeManager,
        address _moduleFactory
    )
        external
        initializer
        validAddress(_communityMultisig)
        validAddress(_teamMultisig)
        validTimelockPeriod(_timelockPeriod)
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
        _grantRole(COMMUNITY_MULTISIG_ROLE, _communityMultisig);
        // grant COMMUNITY_MULTISIG_ROLE to specified address
        _grantRole(TEAM_MULTISIG_ROLE, _teamMultisig);

        // set timelock period
        _setTimelockPeriod(_timelockPeriod);

        // set fee manager
        _setFeeManager(_feeManager);
        // set module factory
        _setModuleFactory(_moduleFactory);
    }

    /// @inheritdoc IGovernor_v1
    function moduleFactoryInitCallback(
        IInverterBeacon_v1[] calldata registeredBeacons
    ) external onlyLinkedModuleFactory linkedBeaconsEmpty {
        // Make sure Beacons are accessible for Governor
        uint length = registeredBeacons.length;
        for (uint i = 0; i < length; i++) {
            if (!_isBeaconAccessible(address(registeredBeacons[i]))) {
                revert Governor__BeaconNotAccessible(
                    address(registeredBeacons[i])
                );
            }
        }

        linkedBeacons = registeredBeacons;
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

    /// @inheritdoc IGovernor_v1
    function getLinkedBeacons()
        external
        view
        returns (IInverterBeacon_v1[] memory)
    {
        return linkedBeacons;
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
    function getModuleFactory() external view returns (address) {
        return address(moduleFactory);
    }

    /// @inheritdoc IGovernor_v1
    function setModuleFactory(address newModuleFactory)
        external
        onlyRole(COMMUNITY_MULTISIG_ROLE)
    {
        _setModuleFactory(newModuleFactory);
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
    // Register Beacons

    /// @inheritdoc IGovernor_v1
    function registerMetadataInModuleFactory(
        IModule_v1.Metadata memory metadata,
        IInverterBeacon_v1 beacon
    ) external onlyCommunityOrTeamMultisig {
        _addBeaconToLinkedBeacons(beacon);
        moduleFactory.registerMetadata(metadata, beacon);
    }

    /// @inheritdoc IGovernor_v1
    function registerNonModuleBeacon(IInverterBeacon_v1 beacon)
        external
        onlyCommunityOrTeamMultisig
    {
        _addBeaconToLinkedBeacons(beacon);
    }

    //--------------------------------------------------------------------------
    // Beacon Functions
    //---------------------------
    // Upgrade

    /// @inheritdoc IGovernor_v1
    function upgradeBeaconWithTimelock(
        address beacon,
        address newImplementation,
        uint newMinorVersion,
        uint newPatchVersion
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
            newMinorVersion,
            newPatchVersion
        );

        emit BeaconTimelockStarted(
            beacon,
            newImplementation,
            newMinorVersion,
            newPatchVersion,
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
            beaconTimelock[beacon].intendedPatchVersion,
            false // this is not intended to override a shutdown
        );

        emit BeaconUpgraded(
            beacon,
            beaconTimelock[beacon].intendedImplementation,
            beaconTimelock[beacon].intendedMinorVersion,
            beaconTimelock[beacon].intendedPatchVersion
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
    {
        _setTimelockPeriod(newTimelockPeriod);
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
    function initiateBeaconShutdownForAllLinkedBeacons()
        external
        onlyCommunityOrTeamMultisig
    {
        uint length = linkedBeacons.length;
        for (uint i = 0; i < length; i++) {
            linkedBeacons[i].shutDownImplementation();
            emit BeaconShutdownInitiated(address(linkedBeacons[i]));
        }
    }

    /// @inheritdoc IGovernor_v1
    function forceUpgradeBeaconAndRestartImplementation(
        address beacon,
        address newImplementation,
        uint newMinorVersion,
        uint newPatchVersion
    )
        external
        onlyRole(COMMUNITY_MULTISIG_ROLE)
        accessibleBeacon(beacon)
        validAddress(newImplementation)
    {
        IInverterBeacon_v1(beacon).upgradeTo(
            newImplementation, newMinorVersion, newPatchVersion, true
        );
        emit BeaconForcefullyUpgradedAndImplementationRestarted(
            beacon, newImplementation, newMinorVersion, newPatchVersion
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

    /// @dev	sets the internal {FeeManager_v1} address.
    /// @param  newFeeManager the address of the new {FeeManager_v1}.
    function _setFeeManager(address newFeeManager)
        internal
        validAddress(newFeeManager)
    {
        feeManager = IFeeManager_v1(newFeeManager);
        emit FeeManagerUpdated(newFeeManager);
    }

    /// @dev	sets the internal timelock period.
    /// @param  newTimelockPeriod the new timelock period.
    function _setTimelockPeriod(uint newTimelockPeriod)
        internal
        validTimelockPeriod(newTimelockPeriod)
    {
        timelockPeriod = newTimelockPeriod;
        emit TimelockPeriodSet(newTimelockPeriod);
    }

    /// @dev	sets the internal {ModuleFactory_v1} address.
    /// @param  newModuleFactory the address of the new {ModuleFactory_v1}.
    function _setModuleFactory(address newModuleFactory)
        internal
        validAddress(newModuleFactory)
    {
        moduleFactory = IModuleFactory_v1(newModuleFactory);
        emit ModuleFactoryUpdated(newModuleFactory);
    }

    /// @dev	Internal function that checks if target address is a {IInverterBeacon_v1}
    ///         and this contract has the ownership of it.
    function _isBeaconAccessible(address target) internal returns (bool) {
        // Check if target is a contract
        if (target.code.length == 0) {
            return false;
        }

        // Check if target address supports Inverter {IInverterBeacon_v1} interface
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

    /// @dev	Internal function that adds a beacon to the linked beacons array.
    /// @param  beacon The beacon to add.
    function _addBeaconToLinkedBeacons(IInverterBeacon_v1 beacon)
        internal
        accessibleBeacon(address(beacon))
    {
        linkedBeacons.push(beacon);
        emit BeaconAddedToLinkedBeacons(address(beacon));
    }
}
