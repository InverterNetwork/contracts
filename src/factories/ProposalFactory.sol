// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

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
import {
    IFundingManager,
    IAuthorizer,
    IPaymentProcessor
} from "src/proposal/IProposal.sol";
import {IModuleFactory} from "src/factories/IModuleFactory.sol";

/**
 * @title Proposal Factory
 *
 * @dev An immutable factory for deploying proposals.
 *
 * @author Inverter Network
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

    /// @inheritdoc IProposalFactory
    function createProposal(
        ProposalConfig memory proposalConfig,
        ModuleConfig memory fundingManagerConfig,
        ModuleConfig memory authorizerConfig,
        ModuleConfig memory paymentProcessorConfig,
        ModuleConfig[] memory moduleConfigs
    ) external returns (IProposal) {
        address clone = Clones.clone(target);

        //Map proposal clone
        _proposals[++_proposalIdCounter] = clone;

        // Deploy and cache {IAuthorizer} module.
        address fundingManager = IModuleFactory(moduleFactory).createModule(
            fundingManagerConfig.metadata,
            IProposal(clone),
            fundingManagerConfig.configdata
        );

        // Deploy and cache {IAuthorizer} module.
        address authorizer = IModuleFactory(moduleFactory).createModule(
            authorizerConfig.metadata,
            IProposal(clone),
            authorizerConfig.configdata
        );

        // Deploy and cache {IPaymentProcessor} module.
        address paymentProcessor = IModuleFactory(moduleFactory).createModule(
            paymentProcessorConfig.metadata,
            IProposal(clone),
            paymentProcessorConfig.configdata
        );

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

        for(uint i; i < modulesLen; i++) {
            
        }

        // Initialize proposal.
        IProposal(clone).init(
            _proposalIdCounter,
            proposalConfig.owner,
            proposalConfig.token,
            modules,
            IFundingManager(fundingManager),
            IAuthorizer(authorizer),
            IPaymentProcessor(paymentProcessor)
        );

        return IProposal(clone);
    }

    // @note the current idea is to make every module go through 2 init functions, where the 2nd one is the 
    //       late dependency injection.
    // @note However, the problem again would be, if A wants to reference B and B has not been created yet, there is no use running the second init function
    // @note One solution could be to simply, do a loop of all the modules again in the modules array for the second init function 
    //       and whichever module requires the late dependency injection could implement that second init function and whichever module 
    //       does not require the dependency injection could simply leave that second init function blank

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
