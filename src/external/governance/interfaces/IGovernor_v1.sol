// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {IModuleFactory_v1} from "src/factories/interfaces/IModuleFactory_v1.sol";

import {IInverterBeacon_v1} from "src/proxies/interfaces/IInverterBeacon_v1.sol";

interface IGovernor_v1 {
    //--------------------------------------------------------------------------
    // Structs

    /// @notice Struct used to store information about a timelock for a beacon upgrade.
    /// @dev The timelock is needed to upgrade a beacon to new implementation.
    /// @param timelockActive Is the timelock currently active.
    /// @param timelockUntil Timestamp that represents from when the upgrade can be carried out.
    /// @param intendedImplementation The new inteded Implementation address of the beacon.
    /// @param intendedMinorVersion The new intended minor Version of the beacon.
    /// @param intendedPatchVersion The new intended patch Version of the beacon.
    struct Timelock {
        bool timelockActive;
        uint timelockUntil;
        address intendedImplementation;
        uint intendedMinorVersion;
        uint intendedPatchVersion;
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice This function can only be accessed by the linked ModuleFactory.
    error Governor__OnlyLinkedModuleFactory();

    /// @notice This function can only be called when the linked beacon array is empty.
    error Governor__LinkedBeaconsNotEmpty();

    /// @notice The given address is invalid.
    error Governor__InvalidAddress(address adr);

    /// @notice The given amount is invalid.
    error Governor__InvalidTimelockPeriod(uint amt);

    /// @notice The given target address is not accessible.
    error Governor__BeaconNotAccessible(address target);

    /// @notice This function can only be accessed by the CommunityMultisig or TeamMultisig.
    error Governor__OnlyCommunityOrTeamMultisig();

    /// @notice The timelock period needed for the beacon to be upgraded has not been exceeded yet.
    error Governor__TimelockPeriodNotExceeded();

    /// @notice This Upgrade process for this beacon has not yet been started.
    error Governor__UpgradeProcessNotStarted();

    /// @notice The call to the target contract has failed.
    error Governor__CallToTargetContractFailed();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new timelock period for a upgrade of a beacon is started.
    /// @param beacon The address of the beacon.
    /// @param newImplementation The address of the new Implementation.
    /// @param newMinorVersion The new minor version.
    /// @param newPatchVersion The new patch version.
    /// @param timelockExceeded Timestamp of when the timelock is exceeded.
    event BeaconTimelockStarted(
        address beacon,
        address newImplementation,
        uint newMinorVersion,
        uint newPatchVersion,
        uint timelockExceeded
    );

    /// @notice Event emitted when a beacon is upgraded.
    /// @param beacon The address of the beacon.
    /// @param newImplementation The address of the new Implementation.
    /// @param newMinorVersion The new minor version.
    /// @param newPatchVersion The new patch version.
    event BeaconUpgraded(
        address beacon,
        address newImplementation,
        uint newMinorVersion,
        uint newPatchVersion
    );

    /// @notice Event emitted when a beacon upgraded is canceled.
    /// @param beacon The address of the beacon.
    event BeaconUpgradedCanceled(address beacon);

    /// @notice Event emitted when the fee manager is updated.
    /// @param feeManager The address of the fee manager.
    event FeeManagerUpdated(address feeManager);

    /// @notice Event emitted when the module factory is updated.
    /// @param moduleFactory The address of the module factory.
    event ModuleFactoryUpdated(address moduleFactory);

    /// @notice Event emitted when a timelock period is set.
    /// @param newTimelockPeriod The new timelock period.
    event TimelockPeriodSet(uint newTimelockPeriod);

    /// @notice Event emitted when a beacon shutdown is initiated.
    /// @param beacon The address of the beacon.
    event BeaconShutdownInitiated(address beacon);

    /// @notice Event emitted when a beacon is forcefully upgraded and the implementation gets restarted immediatly.
    /// @param beacon The address of the beacon.
    /// @param newImplementation The address of the new Implementation.
    /// @param newMinorVersion The new minor version.
    /// @param newPatchVersion The new patch version.
    event BeaconForcefullyUpgradedAndImplementationRestarted(
        address beacon,
        address newImplementation,
        uint newMinorVersion,
        uint newPatchVersion
    );

    /// @notice Event emitted when a beacon implementation is restarted.
    /// @param beacon The address of the beacon.
    event BeaconImplementationRestarted(address beacon);

    /// @notice Event emitted when a the governor contract accepts the ownership over another contract.
    /// @param adr The address of the contract that distributed the ownership.
    event OwnershipAccepted(address adr);

    //--------------------------------------------------------------------------
    // Initialization

    /// @notice The module's initializer function.
    /// @param _communityMultisig The address of the community multisig.
    /// @param _teamMultisig The address of the team multisig.
    /// @param _timelockPeriod The timelock period needed to upgrade a beacon.
    /// @param _feeManager The address of the initial fee manager.
    /// @param _moduleFactory The address of the initial module factory.
    function init(
        address _communityMultisig,
        address _teamMultisig,
        uint _timelockPeriod,
        address _feeManager,
        address _moduleFactory
    ) external;

    function moduleFactoryInitCallback(
        IInverterBeacon_v1[] calldata registeredBeacons
    ) external;

    //--------------------------------------------------------------------------
    // Getter Functions

    /// @notice Returns the current timelock of a beacon address.
    /// @param beacon The address of the beacon.
    /// @return The timelock of the beacon address.
    function getBeaconTimelock(address beacon)
        external
        view
        returns (Timelock memory);

    /// @notice Returns the list of currently linked beacons.
    /// @return LinkedBeacons The array of InverterBeacons that are currently linked to the governor.
    function getLinkedBeacons()
        external
        view
        returns (IInverterBeacon_v1[] memory);

    //--------------------------------------------------------------------------
    // FeeManager

    /// @notice Returns the FeeManager address.
    /// @return Address of the FeeManager.
    function getFeeManager() external view returns (address);

    /// @notice Returns the ModuleFactory address.
    /// @return Address of the ModuleFactory.
    function getModuleFactory() external view returns (address);

    /// @notice Sets the address of the FeeManager.
    /// @dev can only be accessed by the COMMUNITY_MULTISIG_ROLE.
    /// @param newFeeManager The address of the new FeeManager.
    function setFeeManager(address newFeeManager) external;

    /// @notice Sets the address of the ModuleFactory.
    /// @dev can only be accessed by the COMMUNITY_MULTISIG_ROLE.
    /// @param newModuleFactory The address of the new ModuleFactory.
    function setModuleFactory(address newModuleFactory) external;

    /// @notice Sets the maximum fee percentage that can be assigned in the linked FeeManager.
    /// @dev can only be accessed by the COMMUNITY_MULTISIG_ROLE.
    /// @dev The given max fee can not be higher than the BPS.
    /// @param maxFee The max Fee in relation to the BPS.
    function setFeeManagerMaxFee(uint maxFee) external;

    /// @notice Sets the default protocol treasury address in the linked FeeManager.
    /// @dev can only be accessed by the COMMUNITY_MULTISIG_ROLE.
    /// @dev The given treasury address can not be address(0).
    /// @param _defaultProtocolTreasury The address of the default protocol treasury.
    function setFeeManagerDefaultProtocolTreasury(
        address _defaultProtocolTreasury
    ) external;

    /// @notice Sets the protocol treasury address for a specific workflow in the linked FeeManager.
    /// @dev can only be accessed by the COMMUNITY_MULTISIG_ROLE.
    /// @dev The given treasury address can not be address(0).
    /// @param workflow The address of the workflow.
    /// @param treasury The address of the protocol treasury for that specific workflow.
    function setFeeManagerWorkflowTreasuries(address workflow, address treasury)
        external;

    /// @notice Sets the default collateral fee of the protocol in the linked FeeManager.
    /// @dev can only be accessed by the COMMUNITY_MULTISIG_ROLE.
    /// @dev The given fee needs to be less than the BPS.
    /// @param _defaultCollateralFee The default collateral fee of the protocol in relation to the BPS.
    function setFeeManagerDefaultCollateralFee(uint _defaultCollateralFee)
        external;

    /// @notice Sets the default issuance fee of the protocol in the linked FeeManager.
    /// @dev can only be accessed by the COMMUNITY_MULTISIG_ROLE.
    /// @dev The given fee needs to be less than the BPS.
    /// @param _defaultIssuanceFee The default issuance fee of the protocol in relation to the BPS.
    function setFeeManagerDefaultIssuanceFee(uint _defaultIssuanceFee)
        external;

    /// @notice Sets the collateral fee for a specific workflow module function in the linked FeeManager.
    /// @dev can only be accessed by either the COMMUNITY_MULTISIG_ROLE or the TEAM_MULTISIG_ROLE.
    /// @dev The given fee needs to be less than the BPS.
    /// @param workflow The address of the workflow that contains the module function.
    /// @param module The address of the module that contains the function.
    /// @param functionSelector The function selector of the target function.
    /// @param set Boolean that determines if the fee is actually used or not.
    /// @param fee The collateral fee in relation to the BPS.
    function setFeeManagerCollateralWorkflowFee(
        address workflow,
        address module,
        bytes4 functionSelector,
        bool set,
        uint fee
    ) external;

    /// @notice Sets the issuance fee for a specific workflow module function in the linked FeeManager.
    /// @dev can only be accessed by either the COMMUNITY_MULTISIG_ROLE or the TEAM_MULTISIG_ROLE.
    /// @dev The given fee needs to be less than the BPS.
    /// @param workflow The address of the workflow that contains the module function.
    /// @param module The address of the module that contains the function.
    /// @param functionSelector The function selector of the target function.
    /// @param set Boolean that determines if the fee is actually used or not.
    /// @param fee The issuance fee in relation to the BPS.
    function setFeeManagerIssuanceWorkflowFee(
        address workflow,
        address module,
        bytes4 functionSelector,
        bool set,
        uint fee
    ) external;

    //--------------------------------------------------------------------------
    // Factory Functions

    /// @notice Registers a beacon with the provided metadata in the target moduleFactory.
    /// @dev can only be accessed by either the COMMUNITY_MULTISIG_ROLE or the TEAM_MULTISIG_ROLE.
    /// @param moduleFactory The module factory what will should register the new beacon and its metadata.
    /// @param metadata The metadata that will be registered.
    /// @param beacon The beacon that will be registered.
    function registerMetadataInModuleFactory(
        IModuleFactory_v1 moduleFactory,
        IModule_v1.Metadata memory metadata,
        IInverterBeacon_v1 beacon
    ) external;

    //--------------------------------------------------------------------------
    // Beacon Functions

    //---------------------------
    // Upgrade

    /// @notice Starts the upgrade process of a beacon by creating a timelock period after
    ///         which the beacon can be upgraded via triggerUpgradeBeaconWithTimelock().
    /// @dev This function will override previous timelocks even if they are active.
    /// @dev can only be accessed by either the COMMUNITY_MULTISIG_ROLE or the TEAM_MULTISIG_ROLE.
    /// @param beacon The address of the beacon that is intended to be upgraded.
    /// @param newImplementation The address of the intended new Implementation of the beacon.
    /// @param newMinorVersion The intended new minor version of the beacon.
    /// @param newPatchVersion The intended new patch version of the beacon.
    function upgradeBeaconWithTimelock(
        address beacon,
        address newImplementation,
        uint newMinorVersion,
        uint newPatchVersion
    ) external;

    /// @notice Upgrades a beacon with the data provided by the active timelock.
    /// @dev can only be accessed by either the COMMUNITY_MULTISIG_ROLE or the TEAM_MULTISIG_ROLE.
    /// @param beacon The address of the beacon that is intended to be upgraded.
    function triggerUpgradeBeaconWithTimelock(address beacon) external;

    /// @notice Cancels a Upgrade of beacon by setting the active timelock to inactive.
    /// @dev can only be accessed by either the COMMUNITY_MULTISIG_ROLE or the TEAM_MULTISIG_ROLE.
    /// @param beacon The address of the beacon for which the timelock should be canceled.
    function cancelUpgrade(address beacon) external;

    /// @notice Sets the timelock period of a beacon upgrade process.
    /// @dev can only be accessed by the COMMUNITY_MULTISIG_ROLE.
    /// @param newtimelockPeriod The new timelock period.
    function setTimelockPeriod(uint newtimelockPeriod) external;

    //---------------------------
    // Emergency Shutdown

    /// @notice Initiates the shutdown of a beacon.
    /// @dev can only be accessed by either the COMMUNITY_MULTISIG_ROLE or the TEAM_MULTISIG_ROLE.
    /// @param beacon The address of the beacon that should be shut down.
    function initiateBeaconShutdown(address beacon) external;

    /// @notice Initiates the shutdown of all linked beacons.
    /// @dev can only be accessed by either the COMMUNITY_MULTISIG_ROLE or the TEAM_MULTISIG_ROLE.
    function initiateBeaconShutdownForAllLinkedBeacons() external;

    /// @notice This function forces the upgrade of a beacon and restarts the implementation afterwards.
    /// @dev can only be accessed by the COMMUNITY_MULTISIG_ROLE.
    /// @param beacon The address of the beacon that is intended to be upgraded and restarted.
    /// @param newImplementation The address of the intended new Implementation of the beacon.
    /// @param newMinorVersion The intended new minor version of the beacon.
    /// @param newPatchVersion The intended new patch version of the beacon.
    function forceUpgradeBeaconAndRestartImplementation(
        address beacon,
        address newImplementation,
        uint newMinorVersion,
        uint newPatchVersion
    ) external;

    /// @notice Restarts the beacon implementation.
    /// @dev can only be accessed by the COMMUNITY_MULTISIG_ROLE.
    /// @param beacon The address of the beacon that should restarted.
    function restartBeaconImplementation(address beacon) external;

    //---------------------------
    // Ownable2Step

    /// @notice Accepts the ownership over the target address.
    /// @dev can only be accessed by the COMMUNITY_MULTISIG_ROLE or TEAM_MULTISIG_ROLE.
    /// @param adr The address of target that wants to hand over the ownership.
    function acceptOwnership(address adr) external;
}
