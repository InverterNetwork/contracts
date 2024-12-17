// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {IModuleFactory_v1} from "src/factories/interfaces/IModuleFactory_v1.sol";

import {IInverterBeacon_v1} from "src/proxies/interfaces/IInverterBeacon_v1.sol";

interface IGovernor_v1 {
    //--------------------------------------------------------------------------
    // Structs

    /// @notice Struct used to store information about a timelock for a {IInverterBeacon_v1} upgrade.
    /// @dev	The timelock is needed to upgrade a {IInverterBeacon_v1} to new implementation.
    /// @param  timelockActive Is the timelock currently active.
    /// @param  timelockUntilTimestamp that represents from when the upgrade can be carried out.
    /// @param  intendedImplementation The new inteded Implementation address of the {IInverterBeacon_v1}.
    /// @param  intendedMinorVersion The new intended minor version of the {IInverterBeacon_v1}.
    /// @param  intendedPatchVersion The new intended patch version of the {IInverterBeacon_v1}.
    struct Timelock {
        bool timelockActive;
        uint timelockUntil;
        address intendedImplementation;
        uint intendedMinorVersion;
        uint intendedPatchVersion;
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice This function can only be accessed by the linked {ModuleFactory_v1}.
    error Governor__OnlyLinkedModuleFactory();

    /// @notice This function can only be called when the linked {IInverterBeacon_v1} array is empty.
    error Governor__LinkedBeaconsNotEmpty();

    /// @notice The given address is invalid.
    error Governor__InvalidAddress(address adr);

    /// @notice The given amount is invalid.
    error Governor__InvalidTimelockPeriod(uint amt);

    /// @notice The given target address is not accessible.
    error Governor__BeaconNotAccessible(address target);

    /// @notice This function can only be accessed by the CommunityMultisig or TeamMultisig.
    error Governor__OnlyCommunityOrTeamMultisig();

    /// @notice The timelock period needed for the {IInverterBeacon_v1} to be upgraded has not been exceeded yet.
    error Governor__TimelockPeriodNotExceeded();

    /// @notice This upgrade process for this {IInverterBeacon_v1} has not yet been started.
    error Governor__UpgradeProcessNotStarted();

    /// @notice The call to the target contract has failed.
    error Governor__CallToTargetContractFailed();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new beacon is added to the linked beacons.
    /// @param  beacon The address of the new beacon.
    event BeaconAddedToLinkedBeacons(address beacon);

    /// @notice Event emitted when a new timelock period for a upgrade of a {IInverterBeacon_v1} is started.
    /// @param  beacon The address of the {IInverterBeacon_v1}.
    /// @param  newImplementation The address of the new Implementation.
    /// @param  newMinorVersion The new minor version.
    /// @param  newPatchVersion The new patch version.
    /// @param  timelockExceeded Timestamp of when the timelock is exceeded.
    event BeaconTimelockStarted(
        address beacon,
        address newImplementation,
        uint newMinorVersion,
        uint newPatchVersion,
        uint timelockExceeded
    );

    /// @notice Event emitted when a {IInverterBeacon_v1} is upgraded.
    /// @param  beacon The address of the {IInverterBeacon_v1}.
    /// @param  newImplementation The address of the new Implementation.
    /// @param  newMinorVersion The new minor version.
    /// @param  newPatchVersion The new patch version.
    event BeaconUpgraded(
        address beacon,
        address newImplementation,
        uint newMinorVersion,
        uint newPatchVersion
    );

    /// @notice Event emitted when a {IInverterBeacon_v1} upgraded is canceled.
    /// @param  beacon The address of the {IInverterBeacon_v1}.
    event BeaconUpgradedCanceled(address beacon);

    /// @notice Event emitted when the fee manager is updated.
    /// @param  feeManager The address of the fee manager.
    event FeeManagerUpdated(address feeManager);

    /// @notice Event emitted when the module factory is updated.
    /// @param  moduleFactory The address of the module factory.
    event ModuleFactoryUpdated(address moduleFactory);

    /// @notice Event emitted when a timelock period is set.
    /// @param  newTimelockPeriod The new timelock period.
    event TimelockPeriodSet(uint newTimelockPeriod);

    /// @notice Event emitted when a {IInverterBeacon_v1} shutdown is initiated.
    /// @param  beacon The address of the {IInverterBeacon_v1}.
    event BeaconShutdownInitiated(address beacon);

    /// @notice Event emitted when a {IInverterBeacon_v1} is forcefully upgraded and the implementation gets restarted immediatly.
    /// @param  beacon The address of the {IInverterBeacon_v1}.
    /// @param  newImplementation The address of the new Implementation.
    /// @param  newMinorVersion The new minor version.
    /// @param  newPatchVersion The new patch version.
    event BeaconForcefullyUpgradedAndImplementationRestarted(
        address beacon,
        address newImplementation,
        uint newMinorVersion,
        uint newPatchVersion
    );

    /// @notice Event emitted when a {IInverterBeacon_v1} implementation is restarted.
    /// @param  beacon The address of the {IInverterBeacon_v1}.
    event BeaconImplementationRestarted(address beacon);

    /// @notice Event emitted when a the governor contract accepts the ownership over another contract.
    /// @param  adr The address of the contract that distributed the ownership.
    event OwnershipAccepted(address adr);

    //--------------------------------------------------------------------------
    // Initialization

    /// @notice The module's initializer function.
    /// @param  _communityMultisig The address of the community multisig.
    /// @param  _teamMultisig The address of the team multisig.
    /// @param  _timelockPeriod The timelock period needed to upgrade a {IInverterBeacon_v1}.
    /// @param  _feeManager The address of the initial {FeeManager_v1}.
    /// @param  _moduleFactory The address of the initial {ModuleFactory_v1}.
    function init(
        address _communityMultisig,
        address _teamMultisig,
        uint _timelockPeriod,
        address _feeManager,
        address _moduleFactory
    ) external;

    /// @notice Callback function that is called by {ModuleFactory_v1} during initialization.
    /// @param  registeredBeacons The array of {IInverterBeacon_v1}s that will be registered.
    function moduleFactoryInitCallback(
        IInverterBeacon_v1[] calldata registeredBeacons
    ) external;

    //--------------------------------------------------------------------------
    // Getter Functions

    /// @notice Returns the current timelock of a {IInverterBeacon_v1} address.
    /// @param  beacon The address of the {IInverterBeacon_v1}.
    /// @return The timelock of the {IInverterBeacon_v1} address.
    function getBeaconTimelock(address beacon)
        external
        view
        returns (Timelock memory);

    /// @notice Returns the list of currently linked {IInverterBeacon_v1}s.
    /// @return LinkedBeacons The array of {IInverterBeacon_v1}s that are currently linked to the {Governor_v1}.
    function getLinkedBeacons()
        external
        view
        returns (IInverterBeacon_v1[] memory);

    //--------------------------------------------------------------------------
    // FeeManager

    /// @notice Returns the {FeeManager_v1} address.
    /// @return Address of the {FeeManager_v1}.
    function getFeeManager() external view returns (address);

    /// @notice Returns the {ModuleFactory_v1} address.
    /// @return Address of the {ModuleFactory_v1}.
    function getModuleFactory() external view returns (address);

    /// @notice Sets the address of the {FeeManager_v1}.
    /// @dev	Can only be accessed by the `COMMUNITY_MULTISIG_ROLE`.
    /// @param  newFeeManager The address of the new {FeeManager_v1}.
    function setFeeManager(address newFeeManager) external;

    /// @notice Sets the address of the {ModuleFactory_v1}.
    /// @dev	Can only be accessed by the `COMMUNITY_MULTISIG_ROLE`.
    /// @param  newModuleFactory The address of the new {ModuleFactory_v1}.
    function setModuleFactory(address newModuleFactory) external;

    /// @notice Sets the maximum fee percentage that can be assigned in the linked {FeeManager_v1}.
    /// @dev	Can only be accessed by the `COMMUNITY_MULTISIG_ROLE`.
    /// @dev	The given max fee can not be higher than the BPS.
    /// @param  maxFee The max Fee in relation to the BPS.
    function setFeeManagerMaxFee(uint maxFee) external;

    /// @notice Sets the default protocol treasury address in the linked {FeeManager_v1}.
    /// @dev	Can only be accessed by the `COMMUNITY_MULTISIG_ROLE`.
    /// @dev	The given treasury address can not be address(0).
    /// @param  _defaultProtocolTreasury The address of the default protocol treasury.
    function setFeeManagerDefaultProtocolTreasury(
        address _defaultProtocolTreasury
    ) external;

    /// @notice Sets the protocol treasury address for a specific workflow in the linked {FeeManager_v1}.
    /// @dev	Can only be accessed by the `COMMUNITY_MULTISIG_ROLE`.
    /// @dev	The given treasury address can not be address(0).
    /// @param  workflow The address of the workflow.
    /// @param  treasury The address of the protocol treasury for that specific workflow.
    function setFeeManagerWorkflowTreasuries(address workflow, address treasury)
        external;

    /// @notice Sets the default collateral fee of the protocol in the linked {FeeManager_v1}.
    /// @dev	Can only be accessed by the `COMMUNITY_MULTISIG_ROLE`.
    /// @dev	The given fee needs to be less than the BPS.
    /// @param  _defaultCollateralFee The default collateral fee of the protocol in relation to the BPS.
    function setFeeManagerDefaultCollateralFee(uint _defaultCollateralFee)
        external;

    /// @notice Sets the default issuance fee of the protocol in the linked {FeeManager_v1}.
    /// @dev	Can only be accessed by the `COMMUNITY_MULTISIG_ROLE`.
    /// @dev	The given fee needs to be less than the BPS.
    /// @param  _defaultIssuanceFee The default issuance fee of the protocol in relation to the BPS.
    function setFeeManagerDefaultIssuanceFee(uint _defaultIssuanceFee)
        external;

    /// @notice Sets the collateral fee for a specific workflow module function in the linked {FeeManager_v1}.
    /// @dev	Can only be accessed by either the `COMMUNITY_MULTISIG_ROLE` or the `TEAM_MULTISIG_ROLE`.
    /// @dev	The given fee needs to be less than the BPS.
    /// @param  workflow The address of the workflow that contains the module function.
    /// @param  module The address of the module that contains the function.
    /// @param  functionSelector The function selector of the target function.
    /// @param  set Boolean that determines if the fee is actually used or not.
    /// @param  fee The collateral fee in relation to the BPS.
    function setFeeManagerCollateralWorkflowFee(
        address workflow,
        address module,
        bytes4 functionSelector,
        bool set,
        uint fee
    ) external;

    /// @notice Sets the issuance fee for a specific workflow module function in the linked {FeeManager_v1}.
    /// @dev	Can only be accessed by either the `COMMUNITY_MULTISIG_ROLE` or the `TEAM_MULTISIG_ROLE`.
    /// @dev	The given fee needs to be less than the BPS.
    /// @param  workflow The address of the workflow that contains the module function.
    /// @param  module The address of the module that contains the function.
    /// @param  functionSelector The function selector of the target function.
    /// @param  set Boolean that determines if the fee is actually used or not.
    /// @param  fee The issuance fee in relation to the BPS.
    function setFeeManagerIssuanceWorkflowFee(
        address workflow,
        address module,
        bytes4 functionSelector,
        bool set,
        uint fee
    ) external;

    //--------------------------------------------------------------------------
    // Register Beacons

    /// @notice Registers a {IInverterBeacon_v1} with the provided `metadata` in the target {ModuleFactory_v1}.
    /// @dev	Can only be accessed by either the `COMMUNITY_MULTISIG_ROLE` or the `TEAM_MULTISIG_ROLE`.
    /// @param  metadata The metadata that will be registered.
    /// @param  beacon The {IInverterBeacon_v1} that will be registered.
    function registerMetadataInModuleFactory(
        IModule_v1.Metadata memory metadata,
        IInverterBeacon_v1 beacon
    ) external;

    /// @notice Registers an {IInverterBeacon_v1} as a linked beacon that is not a module.
    /// @dev	Can only be accessed by either the `COMMUNITY_MULTISIG_ROLE` or the `TEAM_MULTISIG_ROLE`.
    /// @param  beacon The {IInverterBeacon_v1} that will be registered.
    function registerNonModuleBeacon(IInverterBeacon_v1 beacon) external;

    //--------------------------------------------------------------------------
    // Beacon Functions

    //---------------------------
    // Upgrade

    /// @notice Starts the upgrade process of a {IInverterBeacon_v1} by creating a timelock period after
    ///         which the {IInverterBeacon_v1} can be upgraded via `triggerUpgradeBeaconWithTimelock()`.
    /// @dev	This function will override previous timelocks even if they are active.
    /// @dev	Can only be accessed by either the `COMMUNITY_MULTISIG_ROLE` or the `TEAM_MULTISIG_ROLE`.
    /// @param  beacon The address of the {IInverterBeacon_v1} that is intended to be upgraded.
    /// @param  newImplementation The address of the intended new Implementation of the {IInverterBeacon_v1}.
    /// @param  newMinorVersion The intended new minor version of the {IInverterBeacon_v1}.
    /// @param  newPatchVersion The intended new patch version of the {IInverterBeacon_v1}.
    function upgradeBeaconWithTimelock(
        address beacon,
        address newImplementation,
        uint newMinorVersion,
        uint newPatchVersion
    ) external;

    /// @notice Upgrades a {IInverterBeacon_v1} with the data provided by the active timelock.
    /// @dev	Can only be accessed by either the `COMMUNITY_MULTISIG_ROLE` or the `TEAM_MULTISIG_ROLE`.
    /// @param  beacon The address of the {IInverterBeacon_v1} that is intended to be upgraded.
    function triggerUpgradeBeaconWithTimelock(address beacon) external;

    /// @notice Cancels an upgrade of {IInverterBeacon_v1} by setting the active timelock to inactive.
    /// @dev	Can only be accessed by either the `COMMUNITY_MULTISIG_ROLE` or the `TEAM_MULTISIG_ROLE`.
    /// @param  beacon The address of the {IInverterBeacon_v1} for which the timelock should be canceled.
    function cancelUpgrade(address beacon) external;

    /// @notice Sets the timelock period of a {IInverterBeacon_v1} upgrade process.
    /// @dev	Can only be accessed by the `COMMUNITY_MULTISIG_ROLE`.
    /// @param  newtimelockPeriod The new timelock period.
    function setTimelockPeriod(uint newtimelockPeriod) external;

    //---------------------------
    // Emergency Shutdown

    /// @notice Initiates the shutdown of a {IInverterBeacon_v1}.
    /// @dev	Can only be accessed by either the `COMMUNITY_MULTISIG_ROLE` or the `TEAM_MULTISIG_ROLE`.
    /// @param  beacon The address of the {IInverterBeacon_v1} that should be shut down.
    function initiateBeaconShutdown(address beacon) external;

    /// @notice Initiates the shutdown of all linked {IInverterBeacon_v1}s.
    /// @dev	Can only be accessed by either the `COMMUNITY_MULTISIG_ROLE` or the `TEAM_MULTISIG_ROLE`.
    function initiateBeaconShutdownForAllLinkedBeacons() external;

    /// @notice This function forces the upgrade of a beacon and restarts the implementation afterwards.
    /// @dev	Can only be accessed by the `COMMUNITY_MULTISIG_ROLE`.
    /// @param  beacon The address of the {IInverterBeacon_v1} that is intended to be upgraded and restarted.
    /// @param  newImplementation The address of the intended new Implementation of the {IInverterBeacon_v1}.
    /// @param  newMinorVersion The intended new minor version of the {IInverterBeacon_v1}.
    /// @param  newPatchVersion The intended new patch version of the {IInverterBeacon_v1}.
    function forceUpgradeBeaconAndRestartImplementation(
        address beacon,
        address newImplementation,
        uint newMinorVersion,
        uint newPatchVersion
    ) external;

    /// @notice Restarts the {IInverterBeacon_v1} implementation.
    /// @dev	Can only be accessed by the `COMMUNITY_MULTISIG_ROLE`.
    /// @param  beacon The address of the {IInverterBeacon_v1} that should restarted.
    function restartBeaconImplementation(address beacon) external;

    //---------------------------
    // Ownable2Step

    /// @notice Accepts the ownership over the target address.
    /// @dev	Can only be accessed by the `COMMUNITY_MULTISIG_ROLE` or `TEAM_MULTISIG_ROLE`.
    /// @param  adr The address of target that wants to hand over the ownership.
    function acceptOwnership(address adr) external;
}
