// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IModule_v1, IOrchestrator_v1} from "src/modules/base/IModule_v1.sol";
import {IInverterBeacon_v1} from "src/proxies/interfaces/IInverterBeacon_v1.sol";

interface IModuleImplementationMock {
    /// @dev    Returns the Version of the Implementation
    function getMockVersion() external pure returns (uint);
}
