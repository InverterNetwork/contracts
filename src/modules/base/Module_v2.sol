// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IModule_v2, IOrchestrator_v1} from "src/modules/base/IModule_v2.sol";
import {IAuthorizer_v2} from "@aut/IAuthorizer_v2.sol";
import {IGovernor_v1} from "@ex/governance/interfaces/IGovernor_v1.sol";
import {IFeeManager_v1} from "@ex/fees/interfaces/IFeeManager_v1.sol";

// Internal Dependencies
import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";

// Internal Libraries
import {LibMetadata} from "src/modules/lib/LibMetadata.sol";

// External Dependencies
import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";
import {
    ERC2771ContextUpgradeable,
    ContextUpgradeable
} from "@oz-up/metatx/ERC2771ContextUpgradeable.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

/**
 * @title   Inverter Module
 *
 * @dev     This Contract is the basic building block for all Modules in the Inverter Network.
 *          It contains references to other contracts, modifier for access restriction,
 *          metadata to identify the module type as well as utility functions for general
 *          module interactions.
 *
 *          This contract provides a framework for triggering and receiving {Orchestrator_v1}
 *          callbacks (via `call`) and a modifier to authenticate
 *          callers via the module's {Orchestrator_v1}.
 *
 *          Each module is identified via a unique identifier based on its major
 *          version, title, and url given in the metadata.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @custom:version  v2.0.0
 *
 * @author  Inverter Network
 */
abstract contract Module_v2 is
    IModule_v2,
    Initializable,
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

    // ========================================================================
    // Storage
    //
    // Variables are prefixed with `__Module_`.

    /// @dev	The module's orchestrator instance.
    ///
    /// @custom:invariant Not mutated after initialization.
    IOrchestrator_v1 internal __Module_orchestrator;

    /// @dev	The module's metadata.
    ///
    /// @custom:invariant Not mutated after initialization.
    Metadata internal __Module_metadata;

    /// @dev	Storage gap for future upgrades.
    uint[50] private __gap;

    // ========================================================================
    // Modifiers
    //
    // Note that the modifiers declared here are available in dowstream
    // contracts too. To not make unnecessary modifiers available, this contract
    // inlines argument validations not needed in downstream contracts.

    modifier permissioned() {
        _checkAuthorization(_msgSender(), _msgData());
        _;
    }

    /// @dev    Modifier to guarantee function is only callable by a module registered within the
    ///         workflows's {Orchestrator_v1} and the module is implementing the {IERC20PaymentClientBase_v2} interface.
    modifier onlyPaymentClient() {
        _onlyPaymentClientModifier();
        _;
    }

    /// @dev	Checks if the given Address is valid.
    /// @param  to The address to check.
    modifier validAddress(address to) {
        _validAddressModifier(to);
        _;
    }

    // ========================================================================
    // Initialization

    constructor() ERC2771ContextUpgradeable(address(0)) {
        _disableInitializers();
    }

    /// @inheritdoc IModule_v2
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory /*configData*/
    ) external virtual initializer {
        __Module_init(orchestrator_, metadata);
    }

    /// @dev	The initialization function MUST be called by the upstream
    ///      contract in their overridden `init()` function.
    /// @param  orchestrator_ The module's {Orchestrator_v1}.
    function __Module_init(
        IOrchestrator_v1 orchestrator_,
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

    // ========================================================================
    // Public Getter Functions

    // ------------------------------------------------------------------------
    // Getter - Module State

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
    function orchestrator() public view returns (IOrchestrator_v1) {
        return __Module_orchestrator;
    }

    //--------------------------------------------------------------------------
    // Getter - ERC2771 Context Upgradeable Overrides

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

    // ========================================================================
    // Internal Functions

    // ------------------------------------------------------------------------
    // Internal - Fees

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

    // ------------------------------------------------------------------------
    // Internal - Authorization

    /// @notice Checks if the caller can call the function that implements the locked modifier.
    /// @param  caller_ The address of the caller.
    /// @param  data_ The data of the call.
    function _checkAuthorization(address caller_, bytes calldata data_)
        internal
        view
    {
        // If caller cannot call the function, revert.
        if (
            !__Module_orchestrator.authorizer().hasPermission(
                caller_, address(this), bytes4(data_[0:4])
            )
        ) {
            revert Module__CallerNotPermissioned();
        }
    }

    // ------------------------------------------------------------------------
    // Internal - Modifiers

    /// @dev	Checks if the given address is an valid address.
    /// @param  to The address to check.
    function _validAddressModifier(address to) internal view {
        if (to == address(0) || to == address(this)) {
            revert Module__InvalidAddress();
        }
    }

    /// @dev	Checks if the caller is an {ERC20PaymentClientBase_v2} module.
    function _onlyPaymentClientModifier() internal view {
        if (
            !__Module_orchestrator.isModule(_msgSender())
                || (
                    !ERC165Upgradeable(_msgSender()).supportsInterface(
                        type(IERC20PaymentClientBase_v1).interfaceId
                    )
                        && !ERC165Upgradeable(_msgSender()).supportsInterface(
                            type(IERC20PaymentClientBase_v2).interfaceId
                        )
                )
        ) revert Module__OnlyCallableByPaymentClient();
    }
}
