// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

// Scripts
import {ProtocolConstants_v1} from
    "script/deploymentSuite/ProtocolConstants_v1.s.sol";

// Interfaces
import {InverterBeacon_v1} from "src/proxies/InverterBeacon_v1.sol";
import {IDeterministicFactory_v1} from
    "@df/interfaces/IDeterministicFactory_v1.sol";

/**
 * @title Inverter Beacon Deployment & Setup Script
 *
 * @dev Script to deploy and setup InverterBeacon_v1's.
 *      It uses a deterministic factory to deploy all the contracts.
 *
 * @author Inverter Network
 */
contract ProxyAndBeaconDeployer_v1 is Script, ProtocolConstants_v1 {
    IDeterministicFactory_v1 public factory =
        IDeterministicFactory_v1(deterministicFactory);

    function setFactory(address _factory) external {
        factory = IDeterministicFactory_v1(_factory);
    }

    function deployBeaconAndSetupProxy(
        string memory implementationName,
        address reverter,
        address owner,
        address implementation,
        uint majorVersion,
        uint minorVersion,
        uint patchVersion
    ) external returns (address proxy) {
        // Deploy the beacon.
        address beaconAddress = deployInverterBeacon(
            implementationName,
            reverter,
            owner,
            implementation,
            majorVersion,
            minorVersion,
            patchVersion
        );
        vm.startBroadcast(deployerPrivateKey);
        {
            proxy = factory.deployWithCreate2(
                factorySalt,
                abi.encodePacked(
                    vm.getCode(
                        "InverterBeaconProxy_v1.sol:InverterBeaconProxy_v1"
                    ),
                    abi.encode(InverterBeacon_v1(beaconAddress))
                )
            );
        }
        vm.stopBroadcast();

        console2.log(
            "\t%s InverterBeaconProxy_v1: %s",
            implementationName,
            address(proxy)
        );
    }

    function deployInverterBeacon(
        string memory implementationName,
        address reverter,
        address owner,
        address implementation,
        uint majorVersion,
        uint minorVersion,
        uint patchVersion
    ) public returns (address beacon) {
        vm.startBroadcast(deployerPrivateKey);
        {
            beacon = factory.deployWithCreate2(
                factorySalt,
                abi.encodePacked(
                    vm.getCode("InverterBeacon_v1.sol:InverterBeacon_v1"),
                    abi.encode(
                        reverter,
                        owner,
                        majorVersion,
                        implementation,
                        minorVersion,
                        patchVersion
                    )
                )
            );
        }

        vm.stopBroadcast();

        // Log the deployed Beacon contract address.
        console2.log("\t%s InverterBeacon_v1: %s", implementationName, beacon);
    }
}
