// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Interfaces
import {IERC2771Context} from "src/external/interfaces/IERC2771Context.sol";

interface IModuleManagerBase_v1 is IERC2771Context {
    //--------------------------------------------------------------------------
    // Structs

    /// @dev The timelock struct to keep track of updating the registerd modules
    struct ModuleUpdateTimelock {
        /// @dev Is the timelock currently active
        bool timelockActive;
        /// @dev Timestamp that represents from when the update can be carried out
        uint timelockUntil;
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by authorized address.
    error ModuleManagerBase__CallerNotAuthorized();

    /// @notice Function is only callable by modules.
    error ModuleManagerBase__OnlyCallableByModule();

    /// @notice Given module address invalid.
    error ModuleManagerBase__InvalidModuleAddress();

    /// @notice Given address is a module.
    error ModuleManagerBase__IsModule();

    /// @notice Given address is not a module.
    error ModuleManagerBase__IsNotModule();

    /// @notice The Manager has reached the maximum amount of modules.
    error ModuleManagerBase__ModuleAmountOverLimits();

    /// @notice Timelock still active for the given module address.
    error ModuleManagerBase__ModuleUpdateTimelockStillActive(
        address _module, uint _timelockUntil
    );

    /// @notice Module update is already in progress.
    error ModuleManagerBase__ModuleUpdateAlreadyStarted();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when module added.
    /// @param module The module's address.
    event ModuleAdded(address indexed module);

    /// @notice Event emitted when module removed.
    /// @param module The module's address.
    event ModuleRemoved(address indexed module);

    /// @notice Event emitted when updating a module is initiated, and the timelock starts;
    /// @param module The module's address.
    /// @param timelockUntil The unix timestamp until the timelock is active.
    event ModuleTimelockStarted(address module, uint timelockUntil);

    /// @notice Event emitted when a module update is canceled
    /// @param module The module's address.
    event ModuleUpdateCanceled(address module);

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Executes a call to `to` with call data `data` either via call
    /// @dev Only callable by enabled modules.
    /// @param to The address to call.
    /// @param data The call data.
    /// @return Whether the call succeeded.
    /// @return The return data of the call.
    function executeTxFromModule(address to, bytes memory data)
        external
        returns (bool, bytes memory);

    /// @notice Returns whether the address `module` is added as module.
    /// @param module The module to check.
    /// @return True if module added, false otherwise.
    function isModule(address module) external view returns (bool);

    /// @notice Returns the list of all modules.
    /// @return List of all modules.
    function listModules() external view returns (address[] memory);

    /// @notice Returns the number of modules.
    function modulesSize() external view returns (uint8);

    //--------------------------------------------------------------------------
    // ERC2771 Context Upgradeable
    // @dev We imitate here the EIP2771 Standard to enable metatransactions

    // @notice Returns wether the given address is the trusted forwarder or not
    // @dev Exposes the ERC2771 isTrusted Forwarder
    function isTrustedForwarder(address forwarder)
        external
        view
        returns (bool);

    // @notice Returns the trusted forwarder for metatransactions
    // @dev Exposes the ERC2771 isTrusted Forwarder
    function trustedForwarder() external view returns (address);
}
