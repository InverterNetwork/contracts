// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";


// External Dependencies
import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";

// Internal Interfaces
import {IProposal} from "src/proposal/IProposal.sol";
import {IPaymentProcessor} from "src/modules/IPaymentProcessor.sol";
import {IAuthorizer} from "src/modules/IAuthorizer.sol";

// Mock Dependencies
import {ModuleManagerMock} from "./base/ModuleManagerMock.sol";

contract ProposalMock is IProposal, ModuleManagerMock {
    IAuthorizer public authorizer;
    IPaymentProcessor public paymentProcessor;
    IERC20 public token;

    uint public proposalId;
    address[] public funders;
    address[] public modules;

    // @todo mp: Add paymentProcessor to ProposalMock::contstructor.
    constructor(IAuthorizer authorizer_) {
        authorizer = authorizer_;
    }

    function init(
        uint proposalId_,
        address[] memory funders_,
        address[] memory modules_,
        IAuthorizer authorizer_,
        IPaymentProcessor paymentProcessor_,
        IERC20 token_
    ) public {
        proposalId = proposalId_;
        funders = funders_;
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
