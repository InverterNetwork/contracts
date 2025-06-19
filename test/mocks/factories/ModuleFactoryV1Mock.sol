// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {LibMetadata} from "src/modules/lib/LibMetadata.sol";

import {
    IModuleFactory_v1,
    IInverterBeacon_v1,
    IModule_v2,
    IOrchestrator_v2
} from "src/factories/interfaces/IModuleFactory_v1.sol";

import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {Module_v2_Mock} from "@mocks/modules/base/Module_v2_Mock.sol";

import {FundingManagerV1Mock} from
    "@mocks/modules/fundingManager/FundingManagerV1Mock.sol";
import {Authorizer_v2_Mock} from
    "@mocks/modules/authorizer/Authorizer_v2_Mock.sol";
import {PaymentProcessor_v3_Mock} from
    "@mocks/modules/paymentProcessor/PaymentProcessor_v3_Mock.sol";

import {Clones} from "@oz/proxy/Clones.sol";

contract ModuleFactoryV1Mock is IModuleFactory_v1 {
    IInverterBeacon_v1 private _beacon;

    uint public howManyCalls;

    address public governor = address(0x999999);
    address public reverter = address(0x111111);

    IOrchestratorFactory_v1.WorkflowConfig public givenWorkflowConfig;

    IModule_v2.Metadata fundingManagerMetadata = IModule_v2.Metadata(
        1, 0, 0, "https://fundingmanager.com", "FundingManager"
    );

    IModule_v2.Metadata authorizerMetadata =
        IModule_v2.Metadata(1, 0, 0, "https://authorizer.com", "Authorizer");

    IModule_v2.Metadata paymentProcessorMetadata = IModule_v2.Metadata(
        1, 1, 0, "https://paymentprocessor.com", "PP_Simple_v3"
    );

    function createAndInitModule(
        IModule_v2.Metadata memory metadata,
        IOrchestrator_v2,
        bytes memory,
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig
    ) external returns (address) {
        givenWorkflowConfig = workflowConfig;
        if (
            LibMetadata.identifier(metadata)
                == LibMetadata.identifier(fundingManagerMetadata)
        ) {
            return address(new FundingManagerV1Mock());
        } else if (
            LibMetadata.identifier(metadata)
                == LibMetadata.identifier(authorizerMetadata)
        ) {
            return address(new Authorizer_v2_Mock());
        } else if (
            LibMetadata.identifier(metadata)
                == LibMetadata.identifier(paymentProcessorMetadata)
        ) {
            return address(new PaymentProcessor_v3_Mock());
        } else {
            return address(new Module_v2_Mock());
        }
    }

    function createModuleProxy(
        IModule_v2.Metadata memory,
        IOrchestrator_v2,
        IOrchestratorFactory_v1.WorkflowConfig memory
    ) external returns (address) {
        return Clones.clone(address(new Module_v2_Mock()));
    }

    function getBeaconAndId(IModule_v2.Metadata memory metadata)
        external
        view
        returns (IInverterBeacon_v1, bytes32)
    {
        return (_beacon, LibMetadata.identifier(metadata));
    }

    function getOrchestratorOfProxy(address /*proxy*/ )
        external
        view
        returns (address)
    {
        // we return msg.sender here, because this is just a mocked factory.
        // this means, that when we are using this, we are not actually testing the
        // real functionality of the factory, but of another contract.
        // the calling contract (ModuleManager) expects the returned address to be
        // itself, if the module proxy was created for it properly.
        return msg.sender;
    }

    function registerMetadata(IModule_v2.Metadata memory, IInverterBeacon_v1)
        external
    {
        howManyCalls++;
    }
}
