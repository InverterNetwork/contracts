// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {Types} from "src/common/Types.sol";

// Interfaces
import {IModuleManager} from "src/interfaces/IModuleManager.sol";

/**
 * @title ModuleManager
 *
 * @dev A contract to manage modules that can execute transactions via this
 *      contract.
 *
 *      Note that modules can only be enabled during the initialization of the
 *      contract. It is, however, always possible to disable modules.
 *
 *      Copied and modified from Gnosis Safe.
 *
 * @author Stefan George - <stefan@gnosis.pm>
 * @author Richard Meissner - <richard@gnosis.pm>
 * @author byterocket
 */
contract ModuleManager is IModuleManager {
    //--------------------------------------------------------------------------
    // Modifiers

    /// @notice Modifier to guarantee function is only callable by enabled
    ///         module.
    modifier onlyModule() {
        if (!isEnabledModule(msg.sender)) {
            revert Proposal__ModuleManager__OnlyCallableByModule();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    /// @dev Mapping of modules.
    mapping(address => bool) private _modules;

    //--------------------------------------------------------------------------
    // Internal Functions

    function __ModuleManager_init(address[] memory modules) internal {
        address module;

        for (uint i; i < modules.length; i++) {
            module = modules[i];

            if (module == address(0)) {
                revert Proposal__ModuleManager__InvalidModuleAddress();
            }

            if (_modules[module]) {
                revert Proposal__ModuleManager__ModuleAlreadyEnabled(module);
            }

            _modules[module] = true;
            emit ModuleEnabled(module);

            // @todo mp: Call into module to "register this proposal" as using
            //           that module instance?
            // This would make it possible to have "multi-modules".
            // One module contract that is an active module for infinite many
            // proposals by saving it's state on a per-proposal basis.
        }
    }

    function __ModuleManager_disableModule(address module) internal {
        if (_modules[module]) {
            _modules[module] = false;
            emit ModuleDisabled(module);
        }
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @inheritdoc IModuleManager
    function executeTxFromModule(
        address to,
        bytes memory data,
        Types.Operation operation
    ) public override (IModuleManager) onlyModule returns (bytes memory) {
        bool ok;
        bytes memory returnData;

        if (operation == Types.Operation.Call) {
            (ok, returnData) = to.call(data);
        } else {
            (ok, returnData) = to.delegatecall(data);
        }

        if (ok) {
            return returnData;
        } else {
            revert Proposal__ModuleManager__ExecuteTxFromModuleFailed();
        }
    }

    // @todo mp: Getter for modules.

    /// @inheritdoc IModuleManager
    function isEnabledModule(address module)
        public
        view
        override (IModuleManager)
        returns (bool)
    {
        return _modules[module];
    }
}
