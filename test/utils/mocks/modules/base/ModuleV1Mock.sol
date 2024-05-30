// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {
    Module_v1,
    IModule_v1,
    IOrchestrator_v1
} from "src/modules/base/Module_v1.sol";

contract ModuleV1Mock is Module_v1 {
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory
    ) public virtual override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata);
    }

    // Note that the `initializer` modifier is missing.
    function initNoInitializer(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory
    ) external {
        __Module_init(orchestrator_, metadata);
    }

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

    function original_getFeeManagerCollateralFeeData(bytes4 functionSelector)
        external
        view
        returns (uint, address)
    {
        return _getFeeManagerCollateralFeeData(functionSelector);
    }

    function original_getFeeManagerIssuanceFeeData(bytes4 functionSelector)
        external
        view
        returns (uint, address)
    {
        return _getFeeManagerIssuanceFeeData(functionSelector);
    }
}
