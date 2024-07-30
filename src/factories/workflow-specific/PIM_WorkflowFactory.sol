// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IPIM_WorkflowFactory} from
    "src/factories/interfaces/IPIM_WorkflowFactory.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Implementations
import {ERC20Issuance_v1} from "src/external/token/ERC20Issuance_v1.sol";

// External Dependencies
import {Ownable} from "@oz/access/Ownable.sol";

contract PIM_WorkflowFactory is Ownable, IPIM_WorkflowFactory {
    // store address of orchestratorfactory
    address public orchestratorFactory;
    // relative fees on collateral token in basis points
    uint public fee;

    constructor(address _orchestratorFactory, address _owner) Ownable(_owner) {
        orchestratorFactory = _orchestratorFactory;
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IPIM_WorkflowFactory
    function createPIMWorkflow(
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig,
        IOrchestratorFactory_v1.ModuleConfig memory authorizerConfig,
        IOrchestratorFactory_v1.ModuleConfig memory paymentProcessorConfig,
        IOrchestratorFactory_v1.ModuleConfig[] memory moduleConfigs,
        IPIM_WorkflowFactory.PIMConfig memory PIMConfig
    )
        external
        returns (IOrchestrator_v1 orchestrator, ERC20Issuance_v1 issuanceToken)
    {
        // deploy issuance token
        ERC20Issuance_v1 issuanceToken = new ERC20Issuance_v1(
            PIMConfig.issuanceTokenParams.name,
            PIMConfig.issuanceTokenParams.symbol,
            PIMConfig.issuanceTokenParams.decimals,
            PIMConfig.issuanceTokenParams.maxSupply,
            address(this) // assigns owner role to itself initially to manage minting rights temporarily
        );

        // mint initial issuance supply to recipient
        issuanceToken.mint(
            PIMConfig.recipient, PIMConfig.bcProperties.initialIssuanceSupply
        );

        // assemble fundingManager config and deploy orchestrator
        IOrchestratorFactory_v1.ModuleConfig memory fundingManagerConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            PIMConfig.metadata,
            abi.encode(
                address(issuanceToken),
                PIMConfig.bcProperties,
                PIMConfig.collateralToken
            )
        );
        IOrchestrator_v1 orchestrator = IOrchestratorFactory_v1(
            orchestratorFactory
        ).createOrchestrator(
            workflowConfig,
            fundingManagerConfig,
            authorizerConfig,
            paymentProcessorConfig,
            moduleConfigs
        );

        // get bonding curve (= funding manager) address
        address fundingManager = address(orchestrator.fundingManager());
        issuanceToken.setMinter(fundingManager, true);

        // revoke minter role from factory
        issuanceToken.setMinter(address(this), false);

        // if renounced token flag is set, renounce ownership over token, else transfer ownership to initial admin
        if (PIMConfig.isRenouncedIssuanceToken) {
            _transferTokenOwnership(issuanceToken, address(0));
        } else {
            _transferTokenOwnership(
                issuanceToken, PIMConfig.issuanceTokenParams.initialAdmin
            );
        }

        // if renounced workflow flag is set, renounce admin rights over workflow, else transfer admin rights to initial admin
        if (PIMConfig.isRenouncedWorkflow) {
            _transferWorkflowAdminRights(orchestrator, address(0));
        } else {
            _transferWorkflowAdminRights(
                orchestrator, PIMConfig.issuanceTokenParams.initialAdmin
            );
        }

        _manageInitialCollateral(
            fundingManager,
            PIMConfig.collateralToken,
            PIMConfig.bcProperties.initialCollateralSupply
        );

        emit IPIM_WorkflowFactory.PIMWorkflowCreated(
            fundingManager,
            address(issuanceToken),
            msg.sender,
            PIMConfig.recipient,
            PIMConfig.isRenouncedIssuanceToken,
            PIMConfig.isRenouncedWorkflow
        );

        return (orchestrator, issuanceToken);
    }

    //--------------------------------------------------------------------------
    // onlyOwner Functions

    /// @inheritdoc IPIM_WorkflowFactory
    function setFee(uint newFee) external onlyOwner {
        fee = newFee;
        emit IPIM_WorkflowFactory.FeeSet(newFee);
    }

    /// @inheritdoc IPIM_WorkflowFactory
    function withdrawFee(IERC20 token, address to) external onlyOwner {
        token.transfer(to, token.balanceOf(address(this)));
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    function _manageInitialCollateral(
        address fundingManager,
        address collateralToken,
        uint initialCollateralSupply
    ) internal {
        IERC20(collateralToken).transferFrom(
            msg.sender, fundingManager, initialCollateralSupply
        );

        if (fee > 0) {
            uint feeAmount = _calculateFee(initialCollateralSupply);
            IERC20(collateralToken).transferFrom(
                msg.sender, address(this), feeAmount
            );
        }
    }

    function _transferTokenOwnership(
        ERC20Issuance_v1 issuanceToken,
        address newAdmin
    ) private {
        if (newAdmin == address(0)) {
            issuanceToken.renounceOwnership();
        } else {
            issuanceToken.transferOwnership(newAdmin);
        }
    }

    function _transferWorkflowAdminRights(
        IOrchestrator_v1 orchestrator,
        address newAdmin
    ) private {
        bytes32 adminRole = orchestrator.authorizer().getAdminRole();
        // if renounced flag is set, add zero address as admin (because workflow must have at least one admin set)
        orchestrator.authorizer().grantRole(adminRole, newAdmin);
        // and revoke admin role from factory
        orchestrator.authorizer().revokeRole(adminRole, address(this));
    }

    function _calculateFee(uint collateralAmount)
        internal
        view
        returns (uint)
    {
        return collateralAmount * fee / 10_000;
    }
}
