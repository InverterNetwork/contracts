// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Interfaces
import {
    IProposalFactory,
    IProposal,
    IModule
} from "src/factories/IProposalFactory.sol";
import {IAuthorizer, IPaymentProcessor} from "src/proposal/IProposal.sol";
import {IModuleFactory} from "src/factories/IModuleFactory.sol";

/**
 * @title Proposal Factory
 *
 * @dev An immutable factory for deploying proposals.
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

    /// @dev Maps the id to the proposals
    mapping(uint => address) private _proposals;

    /// @dev The counter of the current proposal id.
    /// @dev Starts counting from 1.
    uint private _proposalIdCounter;

    //--------------------------------------------------------------------------------
    // Modifier

    /// @notice Modifier to guarantee that the given id is valid
    modifier validProposalId(uint id) {
        if (id > _proposalIdCounter) {
            revert ProposalFactory__InvalidId();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Constructor

    constructor(address target_, address moduleFactory_) {
        target = target_;
        moduleFactory = moduleFactory_;
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    event Checkpoint(string cp);

    /// @inheritdoc IProposalFactory
    function createProposal(
        ProposalConfig memory proposalConfig,
        ModuleConfig memory authorizerConfig,
        ModuleConfig memory paymentProcessorConfig,
        ModuleConfig[] memory moduleConfigs
    ) external returns (IProposal) {
        address clone = Clones.clone(target);

        emit Checkpoint("1");

        //Map proposal clone
        _proposals[++_proposalIdCounter] = clone;

        emit Checkpoint("2");

        // Deploy and cache {IAuthorizer} module.
        address authorizer = IModuleFactory(moduleFactory).createModule(
            authorizerConfig.metadata,
            IProposal(clone),
            authorizerConfig.configdata
        );

        emit Checkpoint("3");

        // Deploy and cache {IPaymentProcessor} module.
        address paymentProcessor = IModuleFactory(moduleFactory).createModule(
            paymentProcessorConfig.metadata,
            IProposal(clone),
            paymentProcessorConfig.configdata
        );

        emit Checkpoint("4");

        // Deploy and cache optional modules.
        uint modulesLen = moduleConfigs.length;
        address[] memory modules = new address[](modulesLen);
        for (uint i; i < modulesLen; ++i) {
            modules[i] = IModuleFactory(moduleFactory).createModule(
                moduleConfigs[i].metadata,
                IProposal(clone),
                moduleConfigs[i].configdata
            );
        }

        emit Checkpoint("5");

        // Initialize proposal.
        IProposal(clone).init(
            _proposalIdCounter,
            proposalConfig.owner,
            proposalConfig.token,
            modules,
            IAuthorizer(authorizer),
            IPaymentProcessor(paymentProcessor)
        );

        emit Checkpoint("6");

        return IProposal(clone);
    }

    /// @inheritdoc IProposalFactory
    function getProposalByID(uint id)
        external
        view
        validProposalId(id)
        returns (address)
    {
        return _proposals[id];
    }

    function getProposalIDCounter() external view returns (uint) {
        return _proposalIdCounter;
    }
}
