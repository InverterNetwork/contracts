// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IOrchestrator_v2} from
    "src/orchestrator/interfaces/IOrchestrator_v2.sol";

interface IModule_v2 {
    //--------------------------------------------------------------------------
    // Structs

    /// @notice The module's metadata.
    /// @param  majorVersion The module's major version.
    /// @param  minorVersion The module's minor version.
    /// @param  patchVersion The module's patch version.
    /// @param  url The module's URL.
    /// @param  title The module's title.
    struct Metadata {
        uint majorVersion;
        uint minorVersion;
        uint patchVersion;
        string url;
        string title;
    }

    /// @notice A struct contains the data to set up a role with function selectors and role holders.
    /// @param roleName The name of the role.
    /// @param functionSelectors The function selectors of the role.
    /// @param intendedHolders The intended holders of the role.
    struct RoleSpecification {
        string roleName;
        bytes4[] functionSelectors;
        address[] intendedHolders;
    }

    //--------------------------------------------------------------------------
    // Events

    /// @notice Module has been initialized.
    /// @param  parentOrchestrator The address of the {Orchestrator_v2} the module is linked to.
    /// @param  metadata The metadata of the module.
    event ModuleInitialized(
        address indexed parentOrchestrator, Metadata metadata
    );

    /// @notice Event emitted when protocol fee has been transferred to the treasury.
    /// @param  token The token received as protocol fee.
    /// @param  treasury The protocol treasury address receiving the token fee amount.
    /// @param  feeAmount The fee amount transferred to the treasury.
    event ProtocolFeeTransferred(
        address indexed token, address indexed treasury, uint feeAmount
    );

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by authorized caller.
    /// @param  role The role that is required.
    /// @param  caller The address that is required to have the role.
    error Module__CallerNotAuthorized(bytes32 role, address caller);

    /// @notice Function is only callable by the {Orchestrator_v1}.
    error Module__OnlyCallableByOrchestrator();

    /// @notice Function is only callable by a {IERC20PaymentClientBase_v1}.
    error Module__OnlyCallableByPaymentClient();

    /// @notice Given {Orchestrator_v1} address invalid.
    error Module__InvalidOrchestratorAddress();

    /// @notice Given metadata invalid.
    error Module__InvalidMetadata();

    /// @notice {Orchestrator_v1} callback triggered failed.
    /// @param  funcSig The signature of the function called.
    error Module_OrchestratorCallbackFailed(string funcSig);

    /// @dev	Invalid Address.
    error Module__InvalidAddress();

    //--------------------------------------------------------------------------
    // Functions

    /// @notice The module's initializer function.
    /// @dev	CAN be overridden by downstream contract.
    /// @dev	MUST call `__Module_init()`.
    /// @param  orchestrator The module's {Orchestrator_v1} instance.
    /// @param  metadata The module's metadata.
    /// @param  configData Variable config data for specific module
    ///                   implementations.
    function init(
        IOrchestrator_v2 orchestrator,
        Metadata memory metadata,
        RoleSpecification[] memory roleSpecs,
        bytes memory configData
    ) external;

    /// @notice Returns the module's identifier.
    /// @dev	The identifier is defined as the keccak256 hash of the module's
    ///         abi packed encoded major version, url and title.
    /// @return The module's identifier.
    function identifier() external view returns (bytes32);

    /// @notice Returns the module's version.
    /// @return The module's major version.
    /// @return The module's minor version.
    /// @return The module's patch version.
    function version() external view returns (uint, uint, uint);

    /// @notice Returns the module's URL.
    /// @return The module's URL.
    function url() external view returns (string memory);

    /// @notice Returns the module's title.
    /// @return The module's title.
    function title() external view returns (string memory);

    /// @notice Returns the module's {Orchestrator_v1} interface, {IOrchestrator_v2}.
    /// @return The module's {Orchestrator_1}.
    function orchestrator() external view returns (IOrchestrator_v2);
}
