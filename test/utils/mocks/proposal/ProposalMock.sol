// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC20MetadataUpgradeable} from
    "@oz-up/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

// External Dependencies
import {OwnableUpgradeable} from "@oz-up/access/OwnableUpgradeable.sol";
import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@oz-up/security/PausableUpgradeable.sol";

// Internal Interfaces
import {
    IProposal,
    IPaymentProcessor,
    IAuthorizer
} from "src/proposal/IProposal.sol";

// Mock Dependencies
import {ModuleManagerMock} from "./base/ModuleManagerMock.sol";
import {ContributorManagerMock} from "./base/ContributorManagerMock.sol";
import {FundingVaultMock} from "./base/FundingVaultMock.sol";

contract ProposalMock is
    IProposal,
    OwnableUpgradeable,
    PausableUpgradeable,
    ModuleManagerMock, // @todo Should not be mocks!
    ContributorManagerMock,
    FundingVaultMock
{
    uint public proposalId;
    IERC20 public token;

    IAuthorizer public authorizer;
    IPaymentProcessor public paymentProcessor;

    // Note that this is a shortcut for tests that only to mock a proposal's
    // authorization.
    constructor(IAuthorizer authorizer_) {
        authorizer = authorizer_;
    }

    function init(
        uint proposalId_,
        address owner_,
        IERC20 token_,
        address[] calldata modules_,
        IAuthorizer authorizer_,
        IPaymentProcessor paymentProcessor_
    ) public initializer {
        __Pausable_init();
        __Ownable_init();
        __ModuleManager_init(modules_);
        __ContributorManager_init();
        __FundingVault_init(
            proposalId_, IERC20MetadataUpgradeable(address(token_))
        );

        proposalId = proposalId_;
        _transferOwnership(owner_);
        authorizer = authorizer_;
        paymentProcessor = paymentProcessor_;
        token = token_;

        __ModuleManager_addModule(address(authorizer_));
        __ModuleManager_addModule(address(paymentProcessor_));
    }

    function executeTx(address target, bytes memory data)
        external
        returns (bytes memory)
    {}

    function version() external pure returns (string memory) {
        return "1";
    }

    function owner()
        public
        view
        override (OwnableUpgradeable, IProposal)
        returns (address)
    {
        return super.owner();
    }

    function paused()
        public
        view
        override (PausableUpgradeable, IProposal)
        returns (bool)
    {
        return super.paused();
    }
}
