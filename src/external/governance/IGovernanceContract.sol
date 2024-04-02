// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IGovernanceContract {
    //@todo In factory check if beacon owner is governance contract

    //@todo Transparent upgradeable proxy?

    //--------------------------------------------------------------------------
    // Structs

    struct Timelock {
        bool timelockActive;
        uint timelockUntil;
        address intendedImplementation;
        uint intendedMinorVersion;
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice The given address is invalid
    error InvalidAddress(address adr);

    /// @notice The given amount is invalid
    error InvalidAmount(uint amt);

    /// @notice The given beacon address is not accessible
    error BeaconNotAccessible(address beacon);

    /// @notice This function can only be accessed by the CommunityMultisig or TeamMultisig
    error OnlyCommunityOrTeamMultisig();

    /// @notice The timelock period needed for the beacon to be upgraded has not been exceeded yet
    error timelockPeriodNotExceeded();

    /// @notice This Upgrade process for this beacon has not yet been started
    error upgradeProcessNotStarted();

    /// @notice The call to the target contract has failed
    error CallToTargetContractFailed();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new timelock period for a upgrade of a beacon is started
    /// @param beacon The address of the beacon
    /// @param newImplementation The address of the new Implementation.
    /// @param newMinorVersion The new minor version.
    event BeaconTimelockStarted(
        address beacon, address newImplementation, uint newMinorVersion
    );

    /// @notice Event emitted when a beacon is upgraded
    /// @param beacon The address of the beacon
    /// @param newImplementation The address of the new Implementation.
    /// @param newMinorVersion The new minor version.
    event BeaconUpgraded(
        address beacon, address newImplementation, uint newMinorVersion
    );

    /// @notice Event emitted when a beacon upgraded is canceled
    /// @param beacon The address of the beacon
    event BeaconUpgradedCanceled(address beacon);

    /// @notice Event emitted when a timelock period is set
    /// @param newTimelockPeriod The new timelock period
    event TimelockPeriodSet(uint newTimelockPeriod);

    /// @notice Event emitted when a beacon shutdown is initiated
    /// @param beacon The address of the beacon
    event BeaconShutdownInitiated(address beacon);

    /// @notice Event emitted when a beacon is forcefully upgraded and the implementation gets restarted immediatly
    /// @param beacon The address of the beacon
    /// @param newImplementation The address of the new Implementation.
    /// @param newMinorVersion The new minor version.
    event BeaconForcefullyUpgradedAndImplementationRestarted(
        address beacon, address newImplementation, uint newMinorVersion
    );

    /// @notice Event emitted when a beacon implementation is restarted
    /// @param beacon The address of the beacon
    event BeaconImplementationRestarted(address beacon);

    /// @notice Event emitted when a the governance contract accepts the ownership over another contract
    /// @param adr The address of the contract that distributed the ownership
    event OwnershipAccepted(address adr);

    //--------------------------------------------------------------------------
    // Initialization

    function init(
        address communityMultisig,
        address teamMultisig,
        uint timelockPeriod //@note should we add feeManager here?
    ) external;

    //--------------------------------------------------------------------------
    // FeeManager
    function getFeeManager() external returns (address);

    function setFeeManager(address newFeeManager) external;

    //--------------------------------------------------------------------------
    // Beacon Functions

    //---------------------------
    //Upgrade

    function upgradeBeaconWithTimelock(
    address beacon, address newImplementation, uint newMinorVersion)
        external; 

    function triggerUpgradeBeaconWithTimelock(address beacon) external; 

    function cancelUpgrade(address beacon) external;

    function setTimelockPeriod(uint newtimelockPeriod) external;

    //---------------------------
    //Emergency Shutdown

    function initiateBeaconShutdown(address beacon) external;

    function forceUpgradeBeaconAndRestartImplementation(
        address beacon,
        address newImplementation,
        uint newMinorVersion
    ) external;

    function restartBeaconImplementation(address beacon) external;

    //---------------------------
    //Ownable2Step

    function acceptOwnership(address adr) external; 
