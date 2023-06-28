// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// SuT
import {Test} from "forge-std/Test.sol";

import {RoleAuthorizerTest} from "test/modules/authorizer/RoleAuthorizer.t.sol";

import {TokenGatedRoleAuthorizer} from
    "src/modules/authorizer/TokenGatedRoleAuthorizer.sol";
import {IAuthorizer} from "src/modules/authorizer/IAuthorizer.sol";
// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";
// Internal Dependencies
import {Proposal} from "src/proposal/Proposal.sol";
// Interfaces
import {IModule, IProposal} from "src/modules/base/IModule.sol";
// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {ModuleMock} from "test/utils/mocks/modules/base/ModuleMock.sol";
import {FundingManagerMock} from
    "test/utils/mocks/modules/FundingManagerMock.sol";
import {PaymentProcessorMock} from
    "test/utils/mocks/modules/PaymentProcessorMock.sol";

contract TokenGatedRoleAuthorizerTest is RoleAuthorizerTest {}
