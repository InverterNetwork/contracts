// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Dependencies
import {Context} from "@oz/utils/Context.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Interfaces
import {IAuthorizer} from "src/modules/IAuthorizer.sol";
import {IPaymentProcessor} from "src/modules/IPaymentProcessor.sol";
import {IProposal} from "src/proposal/IProposal.sol";
import {IModule} from "src/modules/base/IModule.sol";
import {IModuleFactory} from "src/factories/IModuleFactory.sol";
import {IProposalFactory} from "src/factories/IProposalFactory.sol";

/**
 * @title Proposal Factory
 *
 * @author byterocket
 */
contract ProposalFactory is IProposalFactory {
    //--------------------------------------------------------------------------
    // Immutables

    /// @inheritdoc IProposalFactory
    address public immutable override target;

    /// @inheritdoc IProposalFactory
    address public immutable override moduleFactory;

    //--------------------------------------------------------------------------
    // Storage

    /// @dev The counter for the next proposal id.
    /// @dev Starts counting at 1.
    uint private _proposalIdCounter = 1;

    //--------------------------------------------------------------------------
    // Constructor

    constructor(address target_, address moduleFactory_) {
        target = target_;
        moduleFactory = moduleFactory_;
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IProposalFactory
    function createProposal(
        address[] calldata funders,
        // {IAuthorizer} data
        IModule.Metadata memory authorizerMetadata,
        bytes memory authorizerConfigdata,
        // {IPaymentProcessor} data
        IModule.Metadata memory paymentProcessorMetadata,
        bytes memory paymentProcessorConfigdata,
        // Token the Proposal will use
        IERC20 token,
        // Other module data
        IModule.Metadata[] memory moduleMetadatas,
        bytes[] memory moduleConfigdatas
    ) external returns (address) {
        address clone = Clones.clone(target);

        // Revert if data arrays' lengths mismatch.
        if (moduleMetadatas.length != moduleConfigdatas.length) {
            revert ProposalFactory__ModuleDataLengthMismatch();
        }

        // Deploy and cache {IAuthorizer} module.
        address authorizer = IModuleFactory(moduleFactory).createModule(
            authorizerMetadata, IProposal(clone), authorizerConfigdata
        );

        // Deploy and cache {IPaymentProcessor} module.
        address paymentProcessor = IModuleFactory(moduleFactory).createModule(
            paymentProcessorMetadata,
            IProposal(clone),
            paymentProcessorConfigdata
        );

        // Deploy and cache optional modules.
        uint modulesLen = moduleMetadatas.length;
        address[] memory modules = new address[](modulesLen);
        for (uint i; i < modulesLen; i++) {
            modules[i] = IModuleFactory(moduleFactory).createModule(
                moduleMetadatas[i], IProposal(clone), moduleConfigdatas[i]
            );
        }

        // Initialize proposal.
        IProposal(clone).init(
            _proposalIdCounter++,
            funders,
            modules,
            IAuthorizer(authorizer),
            IPaymentProcessor(paymentProcessor),
            IERC20(token)
        );

        return clone;
    }
}
