// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {
    ModuleFactory_v1,
    IModuleFactory_v1,
    IInverterBeacon_v1,
    IModule_v2
} from "src/factories/ModuleFactory_v1.sol";

/**
 * @title   Inverter Testnet Module Factory
 *
 * @notice  Enables the creation and registration of Inverter Modules,
 *          facilitating the deployment of module instances linked to specific beacons.
 *          Allows for configuration of modules starting state via provided deployment data.
 *
 * @dev     An owned factory for deploying modules. This is a testnet version
 *          of the module factory, which enables the deployment of testnet
 *          modules by anyone.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 */
contract Testnet_ModuleFactory_v1 is ModuleFactory_v1 {
    //--------------------------------------------------------------------------
    // Constructor & Initializer

    /// @notice The factories initializer function.
    /// @param  _reverter The address of the {InverterReverter_v1} contract.
    /// @param  _trustedForwarder The address of the trusted forwarder contract.
    constructor(address _reverter, address _trustedForwarder)
        ModuleFactory_v1(_reverter, _trustedForwarder)
    {}

    /// @inheritdoc IModuleFactory_v1
    function registerMetadata(
        IModule_v2.Metadata memory metadata,
        IInverterBeacon_v1 beacon
    ) external override(ModuleFactory_v1) {
        _registerMetadata(metadata, beacon);
    }
}
