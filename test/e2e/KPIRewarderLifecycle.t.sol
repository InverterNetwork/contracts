// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {E2eTest} from "test/e2e/E2eTest.sol";
import "forge-std/console.sol";

//Internal Dependencies
import {ModuleTest, IModule, IOrchestrator} from "test/modules/ModuleTest.sol";
import {IOrchestratorFactory} from "src/factories/OrchestratorFactory.sol";
import {AuthorizerMock} from "test/utils/mocks/modules/AuthorizerMock.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {RebasingFundingManager} from
    "src/modules/fundingManager/RebasingFundingManager.sol";

import {SimplePaymentProcesst, ISimplePaymentProcessor} from
    "src/modules/paymentProcessor/SimplePaymentProcessor.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract BountyManagerLifecycle is E2eTest {

    // How do we approach this.

    /*
    - This needs to be a fork test using an actual UMA instance.
    - Where are the UMA test deployments? =>
    - What Tokens are whitelisted? Which ones could we mint freely for non-fork tests? =>
    


    */

}