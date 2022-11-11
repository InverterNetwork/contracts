// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Dependencies
import {ERC4626Upgradeable} from
    "@oz-up/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";

// Internal Interfaces
import {
    IProposal,
    IPaymentProcessor,
    IAuthorizer
} from "src/proposal/IProposal.sol";

// Mock Dependencies
import {ModuleManagerMock} from "./base/ModuleManagerMock.sol";
import {ContributorManagerMock} from "./base/ContributorManagerMock.sol";

contract ProposalMock is
    IProposal,
    ModuleManagerMock,
    ContributorManagerMock,
    ERC4626Upgradeable // @audit Should be FundingVaultMock.
{
    IAuthorizer public authorizer;
    IPaymentProcessor public paymentProcessor;
    IERC20 public token;

    uint public proposalId;
    address[] public modules;

    // @todo mp: Add paymentProcessor to ProposalMock::contstructor.
    constructor(IAuthorizer authorizer_) {
        authorizer = authorizer_;
    }

    function init(
        uint proposalId_,
        IERC20 token_,
        address[] calldata modules_,
        IAuthorizer authorizer_,
        IPaymentProcessor paymentProcessor_
    ) public {
        proposalId = proposalId_;
        modules = modules_;
        authorizer = authorizer_;
        paymentProcessor = paymentProcessor_;
        token = token_;
    }

    function executeTx(address target, bytes memory data)
        external
        returns (bytes memory)
    {}

    function version() external pure returns (string memory) {
        return "1";
    }

    function initModules(address[] calldata modules_) public initializer {
        __ModuleManager_init(modules_);
    }
}
