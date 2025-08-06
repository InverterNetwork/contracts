// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

// Scripts
import {DeploymentScript} from "script/deploymentScript/DeploymentScript.s.sol";

// Contracts
import {DeterministicFactory_v1} from "@df/DeterministicFactory_v1.sol";
import {Testnet_ModuleFactory_v1} from
    "script/testnetContracts/Testnet_ModuleFactory_v1.sol";

// Interfaces
import {IInverterBeacon_v1} from "src/proxies/interfaces/IInverterBeacon_v1.sol";
import {IModule_v2} from "src/modules/base/IModule_v2.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Mocks
import {
    OptimisticOracleV3Mock,
    OptimisticOracleV3Interface
} from "@mocks/modules/logicModule/oracle/OptimisiticOracleV3Mock.sol";
import {ERC20Mock} from "@mocks/external/token/ERC20Mock.sol";

/**
 * @title Inverter Testnet Deployment Script
 *
 * @dev Script to deploy the Inverter protocol in a testnet environment.
 *      This means that the script deploys the DeterministicFactory as well.
 *
 * @author Inverter Network
 */
contract TestnetDeploymentScript is DeploymentScript {
    OptimisticOracleV3Mock ooV3;
    ERC20Mock mockCollateralToken;

    uint64 immutable DEFAULT_LIVENESS = 25_000;

    function run() public virtual override {
        console2.log();
        console2.log(
            "================================================================================"
        );
        console2.log("Start Testnet Deployment Script");
        console2.log(
            "================================================================================"
        );

        // Set required parameters to testnet values
        // For a testnet deployment, this means that if not set otherwise,
        // the deployer will also act as both multisigs and the treasury.
        if (communityMultisig == address(0)) {
            communityMultisig = deployer;
        }
        if (teamMultisig == address(0)) {
            teamMultisig = deployer;
        }
        if (treasury == address(0)) {
            treasury = deployer;
        }

        vm.startBroadcast(deployerPrivateKey);
        {
            console2.log(" Set up dependency contracts ");

            // Deploy and setup DeterministicFactory
            deterministicFactory =
                address(new DeterministicFactory_v1(deployer));
            DeterministicFactory_v1(deterministicFactory).setAllowedDeployer(
                deployer
            );
            console2.log("\tDeterministic Factory: %s", deterministicFactory);

            console2.log(" Set up mocks");

            // Deploy and setup UMA's OptimisticOracleV3Mock
            ooV3 = new OptimisticOracleV3Mock(
                IERC20(address(mockCollateralToken)), DEFAULT_LIVENESS
            ); // @note FeeToken?
            console2.log("\tOptimisticOracleV3Mock: %s", address(ooV3));

            // Deploy and setup Mock Collateral Token
            mockCollateralToken = new ERC20Mock("Inverter USD", "iUSD", 18);
            console2.log("\tERC20Mock iUSD: %s", address(mockCollateralToken));
        }
        vm.stopBroadcast();

        // Set DeterministicFactory so it's used in the DeploymentScript
        // downstream
        setFactory(deterministicFactory);
        proxyAndBeaconDeployer.setFactory(deterministicFactory);

        super.run();
    }

    function createModuleFactorySingleton(address transactionForwarder)
        internal
        override
    {
        // Replace the implementation of the ModuleFactory with its
        // testnet version.
        impl_fac_ModuleFactory_v1 = deployAndLogWithCreate2(
            "Testnet_ModuleFactory_v1",
            abi.encodePacked(
                vm.getCode(
                    "Testnet_ModuleFactory_v1.sol:Testnet_ModuleFactory_v1"
                ),
                abi.encode(impl_ext_InverterReverter_v1, transactionForwarder)
            )
        );
    }

    // Overriding the parent function to verify that the module factory is not
    // permissioned for testnets.
    function verifyModuleFactoryPermissions() public override {
        (IInverterBeacon_v1 testBeacon,) = Testnet_ModuleFactory_v1(
            moduleFactory
        ).getBeaconAndId(initialMetadataRegistration[0]);

        IModule_v2.Metadata memory testMetadata = IModule_v2.Metadata(
            type(uint).max,
            type(uint).max,
            type(uint).max,
            "Test_Module_Name",
            "https://github.com/Test/test"
        );

        // We do not actually want to send this transaction, just simulate it,
        // which is why there is no startBroadcast() here.
        try Testnet_ModuleFactory_v1(moduleFactory).registerMetadata(
            testMetadata, testBeacon
        ) {
            return;
        } catch (bytes memory reason) {
            // If the OwnableUnauthorizedAccount error is thrown, we know that
            // the wrong factory is deployed.
            if (
                keccak256(reason)
                    == keccak256(
                        abi.encodeWithSignature(
                            "OwnableUnauthorizedAccount(address)", address(this)
                        )
                    )
            ) {
                revert("Deployment failed - Module Factory is permissioned.");
            }

            // If any other error is thrown, we know that the factory has some other
            // issue, even if it's not the permissioning - and we still revert because of
            // that.
            revert("Deployment failed - Module Factory can't be used properly.");
        }
    }
}
