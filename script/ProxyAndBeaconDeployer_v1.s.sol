pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {IDeterministicFactory_v1} from
    "script/deterministicFactory/interfaces/IDeterministicFactory.sol";

import {ProtocolConstants_v1} from "script/ProtocolConstants_v1.s.sol";

import {InverterBeacon_v1} from "src/proxies/InverterBeacon_v1.sol";
import {InverterBeaconProxy_v1} from "src/proxies/InverterBeaconProxy_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";

/**
 * @title DeployAndSetupInverterBeacon_v1 Deployment Script
 *
 * @dev Script to deploy and setup new InverterBeacon_v1.
 *
 *
 * @author Inverter Network
 */
contract ProxyAndBeaconDeployer_v1 is Script, ProtocolConstants_v1 {
    IDeterministicFactory_v1 public factory =
        IDeterministicFactory_v1(deterministicFactory);

    bytes32 factorySalt = keccak256(abi.encodePacked("inverter-deployment"));

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
            "Creation of InverterBeaconProxy_v1 for %s at address: %s",
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
            // Deploy the beacon.

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
        console2.log(
            "Deployment of Inverter Beacon for %s at address %s",
            implementationName,
            beacon
        );

        return beacon;
    }
}
