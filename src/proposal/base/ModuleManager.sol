// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {Types} from "src/common/Types.sol";

// Interfaces
import {IModuleManager} from "src/interfaces/IModuleManager.sol";

contract ModuleManager is IModuleManager {
    //--------------------------------------------------------------------------
    // Errors

    error Proposal__ModuleManager__OnlyCallableByModule();

    error Proposal__ModuleManager__ExecuteTxFromModuleFailed();

    //--------------------------------------------------------------------------
    // Events

    event ModuleDeactivated(address indexed module);

    //--------------------------------------------------------------------------
    // Modifiers

    /// @notice Modifier to guarantee function is only callable by activated
    ///         module.
    modifier onlyModule() {
        if (!isActiveModule(msg.sender)) {
            revert Proposal__ModuleManager__OnlyCallableByModule();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    /// @dev Mapping of activated modules.
    mapping(address => bool) private _modules;

    //--------------------------------------------------------------------------
    // Internal Functions

    function __ModuleManager_init(address[] memory modules) internal {
        address module;

        for (uint i; i < modules.length; i++) {
            module = modules[i];

            assert(module != address(0));
            assert(!_modules[module]);

            _modules[module] = true;

            // @todo mp: Call into module to "register this proposal" as using
            //           that module instance?
            // This would make it possible to have "multi-modules".
            // One module contract that is an active module for infinite many
            // proposals by saving it's state on a per-proposal basis.
        }
    }

    function __ModuleManager_deactivateModule(address module) internal {
        if (_modules[module]) {
            _modules[module] = false;
            emit ModuleDeactivated(module);
        }
    }

    //--------------------------------------------------------------------------
    // Public Functions

    function executeTxFromModule(
        address to,
        bytes memory data,
        Types.Operation operation
    )
        public
        override (IModuleManager)
        onlyModule
        returns (bytes memory)
    {
        bool ok;
        bytes memory returnData;

        if (operation == Types.Operation.Call) {
            (ok, returnData) = to.call(data);
        } else {
            (ok, returnData) = to.delegatecall(data);
        }

        if (!ok) {
            revert Proposal__ModuleManager__ExecuteTxFromModuleFailed();
        } else {
            return returnData;
        }
    }

    // @todo mp: Getter for modules.

    function isActiveModule(address module) public view returns (bool) {
        return _modules[module];
    }
}
