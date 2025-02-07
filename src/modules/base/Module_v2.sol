// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IModule_v2, IOrchestrator_v2} from "src/modules/base/IModule_v2.sol";
import {IAuthorizer_v2} from "@aut/IAuthorizer_v2.sol";
import {IGovernor_v1} from "@ex/governance/interfaces/IGovernor_v1.sol";
import {IFeeManager_v1} from "@ex/fees/interfaces/IFeeManager_v1.sol";

// Internal Dependencies
import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";

// External Dependencies
import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";
import {
    ERC2771ContextUpgradeable,
    ContextUpgradeable
} from "@oz-up/metatx/ERC2771ContextUpgradeable.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";
import {AccessManagedUpgradeable} from
    "@oz-up/access/manager/AccessManagedUpgradeable.sol";

library LibMetadata {
    /// @dev    Returns the identifier for given metadata.
    /// @param  metadata The metadata.
    /// @return The metadata's identifier.
    function identifier(IModule_v2.Metadata memory metadata)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(metadata.majorVersion, metadata.url, metadata.title)
        );
    }

    /// @dev	Returns whether the given metadata is valid.
    /// @param  metadata The metadata.
    /// @return True if metadata valid, false otherwise.
    function isValid(IModule_v2.Metadata memory metadata)
        internal
        pure
        returns (bool)
    {
        // Invalid if url empty.
        if (bytes(metadata.url).length == 0) {
            return false;
        }

        // Invalid if title empty.
        if (bytes(metadata.title).length == 0) {
            return false;
        }

        // Invalid if version is v0.0.0.
        if (
            metadata.majorVersion == 0 && metadata.minorVersion == 0
                && metadata.patchVersion == 0
        ) {
            return false;
        }

        return true;
    }
}

/**
 * @title   Inverter Module
 *
 * @dev
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 */
abstract contract Module_v2 is
    IModule_v2,
    Initializable,
    AccessManagedUpgradeable,
    ERC2771ContextUpgradeable,
    ERC165Upgradeable
{
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165Upgradeable)
        returns (bool)
    {
        return interfaceId == type(IModule_v2).interfaceId
            || super.supportsInterface(interfaceId);
    }

    //--------------------------------------------------------------------------
    // Storage
    //
    // Variables are prefixed with `__Module_`.

    /// @dev	The module's orchestrator instance.
    ///
    /// @custom:invariant Not mutated after initialization.
    IOrchestrator_v2 internal __Module_orchestrator;

    /// @dev	The module's metadata.
    ///
    /// @custom:invariant Not mutated after initialization.
    Metadata internal __Module_metadata;

    /// @dev	Storage gap for future upgrades.
    uint[50] private __gap;

    //--------------------------------------------------------------------------
    // Modifiers
    //
    // Note that the modifiers declared here are available in dowstream
    // contracts too. To not make unnecessary modifiers available, this contract
    // inlines argument validations not needed in downstream contracts.

    /// @dev    Modifier to guarantee function is only callable by a module registered within the
    ///         workflows's {Orchestrator_v1} and the module is implementing the {IERC20PaymentClientBase_v1} interface.
    modifier onlyPaymentClient() {
        _onlyPaymentClientModifier();
        _;
    }

    /// @dev    Modifier to guarantee function is only callable by the {Orchestrator_v1}.
    /// @dev	onlyOrchestrator functions MUST only access the module's storage, i.e.
    ///         `__Module_` variables.
    /// @dev	Note to use function prefix `__Module_`.
    modifier onlyOrchestrator() {
        _onlyOrchestratorModifier();
        _;
    }

    /// @dev	Checks if the given Address is valid.
    /// @param  to The address to check.
    modifier validAddress(address to) {
        _validAddressModifier(to);
        _;
    }

    //--------------------------------------------------------------------------
    // Initialization

    constructor() ERC2771ContextUpgradeable(address(0)) {
        _disableInitializers();
    }

    /// @inheritdoc IModule_v2
    function init(
        IOrchestrator_v2 orchestrator_,
        Metadata memory metadata,
        bytes memory /*configData*/
    ) external virtual initializer {
        __Module_init(orchestrator_, metadata);
        __AccessManaged_init(address(orchestrator_.authorizer()));
    }

    /// @dev	The initialization function MUST be called by the upstream
    ///      contract in their overridden `init()` function.
    /// @param  orchestrator_ The module's {Orchestrator_v1}.
    function __Module_init(
        IOrchestrator_v2 orchestrator_,
        Metadata memory metadata
    ) internal onlyInitializing {
        // Write orchestrator to storage.
        if (address(orchestrator_) == address(0)) {
            revert Module__InvalidOrchestratorAddress();
        }
        __Module_orchestrator = orchestrator_;

        // Write metadata to storage.
        if (!LibMetadata.isValid(metadata)) {
            revert Module__InvalidMetadata();
        }
        __Module_metadata = metadata;

        emit ModuleInitialized(address(orchestrator_), metadata);
    }

    //--------------------------------------------------------------------------
    // Public View Functions

    /// @inheritdoc IModule_v2
    function identifier() public view returns (bytes32) {
        return LibMetadata.identifier(__Module_metadata);
    }

    /// @inheritdoc IModule_v2
    function version() public view returns (uint, uint, uint) {
        return (
            __Module_metadata.majorVersion,
            __Module_metadata.minorVersion,
            __Module_metadata.patchVersion
        );
    }

    /// @inheritdoc IModule_v2
    function url() public view returns (string memory) {
        return __Module_metadata.url;
    }

    /// @inheritdoc IModule_v2
    function title() public view returns (string memory) {
        return __Module_metadata.title;
    }

    /// @inheritdoc IModule_v2
    function orchestrator() public view returns (IOrchestrator_v2) {
        return __Module_orchestrator;
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @notice Returns the collateral fee for the specified workflow module function and the according treasury
    ///         address of this workflow.
    /// @param  functionSelector The function selector of the target function.
    /// @dev	FunctionSelector is always passed as selector of this module / address.
    /// @return fee The collateral fee amount in relation to the BPS of the {FeeManager_v1}.
    /// @return treasury The address of the treasury.
    function _getFeeManagerCollateralFeeData(bytes4 functionSelector)
        internal
        view
        returns (uint fee, address treasury)
    {
        // Fetch fee manager address from orchestrator
        return IFeeManager_v1(__Module_orchestrator.governor().getFeeManager())
            .getCollateralWorkflowFeeAndTreasury(
            address(__Module_orchestrator), // Always take this modules orchestrator as the workflow address
            address(this), // always take this as the module address
            functionSelector
        );
    }

    /// @notice Returns the issuance fee for the specified workflow module function and the according treasury address
    ///         of this workflow.
    /// @param  functionSelector The function selector of the target function.
    /// @dev	FunctionSelector is always passed as selector of this module / address.
    /// @return fee The issuance fee amount in relation to the BPS of the {FeeManager_v1}.
    /// @return treasury The address of the treasury.
    function _getFeeManagerIssuanceFeeData(bytes4 functionSelector)
        internal
        view
        returns (uint fee, address treasury)
    {
        // Fetch fee manager address from orchestrator
        return IFeeManager_v1(__Module_orchestrator.governor().getFeeManager())
            .getIssuanceWorkflowFeeAndTreasury(
            address(__Module_orchestrator), // Always take this modules orchestrator as the workflow address
            address(this), // always take this as the module address
            functionSelector
        );
    }

    /// @dev	Checks if the caller is the orchestrator.
    function _onlyOrchestratorModifier() internal view {
        if (_msgSender() != address(__Module_orchestrator)) {
            revert Module__OnlyCallableByOrchestrator();
        }
    }

    /// @dev	Checks if the given address is an valid address.
    /// @param  to The address to check.
    function _validAddressModifier(address to) internal view {
        if (to == address(0) || to == address(this)) {
            revert Module__InvalidAddress();
        }
    }

    /// @dev	Checks if the caller is an {ERC20PaymentClientBase_v1} module.
    function _onlyPaymentClientModifier() internal view {
        if (
            !__Module_orchestrator.isModule(_msgSender())
                || !ERC165Upgradeable(_msgSender()).supportsInterface(
                    type(IERC20PaymentClientBase_v1).interfaceId
                )
        ) revert Module__OnlyCallableByPaymentClient();
    }

    //--------------------------------------------------------------------------
    // ERC2771 Context Upgradeable

    /// Needs to be overridden, because they are imported via the AccessControlEnumerableUpgradeable as well.
    function _msgSender()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (address sender)
    {
        return ERC2771ContextUpgradeable._msgSender();
    }

    /// Needs to be overridden, because they are imported via the AccessControlEnumerableUpgradeable as well.
    function _msgData()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (bytes calldata)
    {
        return ERC2771ContextUpgradeable._msgData();
    }

    function _contextSuffixLength()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (uint)
    {
        return ERC2771ContextUpgradeable._contextSuffixLength();
    }

    /// @notice Checks if the provided address is the trusted forwarder.
    /// @param  forwarder The contract address to be verified.
    /// @return bool Is the given address the trusted forwarder.
    /// @dev	We imitate here the EIP2771 Standard to enable metatransactions
    ///         As it currently stands we dont want to feed the forwarder address to each module individually and we decided to
    ///         move this to the orchestrator.
    function isTrustedForwarder(address forwarder)
        public
        view
        virtual
        override(ERC2771ContextUpgradeable)
        returns (bool)
    {
        return __Module_orchestrator.isTrustedForwarder(forwarder);
    }

    /// @notice Returns the trusted forwarder.
    /// @return address The trusted forwarder.
    /// @dev	We imitate here the EIP2771 Standard to enable metatransactions.
    ///         As it currently stands we dont want to feed the forwarder address to each module individually and we decided to
    ///         move this to the orchestrator.
    function trustedForwarder()
        public
        view
        virtual
        override(ERC2771ContextUpgradeable)
        returns (address)
    {
        return __Module_orchestrator.trustedForwarder();
    }
}
