// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {
    Module_v2,
    IModule_v2,
    IOrchestrator_v2
} from "src/modules/base/Module_v2.sol";

contract Module_v2_Mock is Module_v2 {
    // ========================================================================
    // Modifier Access

    function modifierPermissionedCheck() external view permissioned {}

    // Empty function used to test the modifier `onlyPaymentClient`
    function modifierOnlyPaymentClientCheck() external view onlyPaymentClient {}

    function modifierOnlyValidAddressCheck(address to)
        external
        view
        validAddress(to)
    {}

    // ========================================================================
    // Initialization

    function init(
        IOrchestrator_v2 orchestrator_,
        Metadata memory metadata,
        bytes memory
    ) public virtual override(Module_v2) initializer {
        __Module_init(orchestrator_, metadata);
    }

    // Note that the `initializer` modifier is missing.
    function initNoInitializer(
        IOrchestrator_v2 orchestrator_,
        Metadata memory metadata,
        bytes memory
    ) external {
        __Module_init(orchestrator_, metadata);
    }

    // ========================================================================
    // Internal Function Access
    function original_msgSender()
        external
        view
        virtual
        returns (address sender)
    {
        return _msgSender();
    }

    function original_msgData()
        external
        view
        virtual
        returns (bytes calldata)
    {
        return _msgData();
    }

    function _getFeeManagerCollateralFeeData_exposed(bytes4 functionSelector)
        external
        view
        returns (uint, address)
    {
        return _getFeeManagerCollateralFeeData(functionSelector);
    }

    function _getFeeManagerIssuanceFeeData_exposed(bytes4 functionSelector)
        external
        view
        returns (uint, address)
    {
        return _getFeeManagerIssuanceFeeData(functionSelector);
    }

    function _checkAuthorization_exposed(address caller_, bytes calldata data_)
        external
        view
    {
        _checkAuthorization(caller_, data_);
    }
}
