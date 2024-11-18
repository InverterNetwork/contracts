// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Factories
import {ModuleFactory_v1} from "src/factories/ModuleFactory_v1.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";

// Governance
import {Governor_v1} from "@ex/governance/Governor_v1.sol";

// Modules
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";
import {E2ETest} from "test/e2e/E2ETest.sol";
import {
    InverterBeacon_v1,
    IInverterBeacon_v1
} from "src/proxies/InverterBeacon_v1.sol";

import {LM_ImmutableMigration_v1} from
    "src/experimental/modules/ImmutableMigration/LM_ImmutableMigration_v1.sol";

contract ExtendedE2ETest is E2ETest {
    // LM_ImmutableMigration_v1
    LM_ImmutableMigration_v1 LM_ImmutableMigration_v1Impl;

    InverterBeacon_v1 LM_ImmutableMigration_v1Beacon;

    IModule_v1.Metadata LM_ImmutableMigration_v1Metadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "LM_ImmutableMigration_v1"
    );

    function setUpLM_ImmutableMigration_v1() internal {
        // Deploy module implementations.
        LM_ImmutableMigration_v1Impl = new LM_ImmutableMigration_v1();

        // Deploy module beacons.
        LM_ImmutableMigration_v1Beacon = new InverterBeacon_v1(
            moduleFactory.reverter(),
            DEFAULT_BEACON_OWNER,
            LM_ImmutableMigration_v1Metadata.majorVersion,
            address(LM_ImmutableMigration_v1Impl),
            LM_ImmutableMigration_v1Metadata.minorVersion,
            LM_ImmutableMigration_v1Metadata.patchVersion
        );

        // Register modules at moduleFactory.
        vm.prank(teamMultisig);
        gov.registerMetadataInModuleFactory(
            LM_ImmutableMigration_v1Metadata,
            IInverterBeacon_v1(LM_ImmutableMigration_v1Beacon)
        );
    }
}
