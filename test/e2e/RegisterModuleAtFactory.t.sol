// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {E2eTest} from "test/e2e/E2eTest.sol";

import {IModule} from "src/modules/base/IModule.sol";
import {SimplePaymentProcessor} from
    "src/modules/paymentProcessor/SimplePaymentProcessor.sol";

import {Beacon, IBeacon} from "src/factories/beacon/Beacon.sol";

/**
 * E2e test demonstrating how to register a new module at the ModuleFactory.
 */
contract RegisterModuleAtFactory is E2eTest {
    function test_e2e_RegisterModuleAtModuleFactory() public {
        // First deploy a new Module implementation.
        // We will use the SimplePaymentProcessor module as example.
        SimplePaymentProcessor module = new SimplePaymentProcessor();

        // We also need to defined the module's metadata.
        IModule.Metadata memory metadata = IModule.Metadata(
            1, 1, "https://github.com/inverter/my-module", "MyModule"
        );

        // Next we need to deploy the module's beacon contract.
        Beacon beacon = new Beacon();

        // Aftrwards, we need to set the beacon's implementation to the module.
        beacon.upgradeTo(address(module));

        // Now we can register the module at the ModuleFactory.
        moduleFactory.registerMetadata(metadata, beacon);
    }
}
