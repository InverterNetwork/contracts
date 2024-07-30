// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IPIM_WorkflowFactory_v1} from
    "src/factories/interfaces/IPIM_WorkflowFactory_v1.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Implementations
import {ERC20Issuance_v1} from "src/external/token/ERC20Issuance_v1.sol";

// External Dependencies
import {Ownable2Step} from "@oz/access/Ownable2Step.sol";
import {Ownable} from "@oz/access/Ownable.sol";
import {ERC2771Context, Context} from "@oz/metatx/ERC2771Context.sol";

contract PIM_WorkflowFactory_v1 is
    Ownable2Step,
    ERC2771Context,
    IPIM_WorkflowFactory_v1
{
    //--------------------------------------------------------------------------
    // State Variables

    // store address of orchestratorfactory
    address public orchestratorFactory;
    // relative fees on collateral token in basis points
    uint public fee;

    constructor(
        address _orchestratorFactory,
        address _owner,
        address _trustedForwarder
    ) Ownable(_owner) ERC2771Context(_trustedForwarder) {
        orchestratorFactory = _orchestratorFactory;
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IPIM_WorkflowFactory_v1
    function createPIMWorkflow(
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig,
        IOrchestratorFactory_v1.ModuleConfig memory paymentProcessorConfig,
        IOrchestratorFactory_v1.ModuleConfig[] memory moduleConfigs,
        IPIM_WorkflowFactory_v1.PIMConfig memory PIMConfig
    )
        external
        returns (IOrchestrator_v1 orchestrator, ERC20Issuance_v1 issuanceToken)
    {
        // deploy issuance token
        issuanceToken = new ERC20Issuance_v1(
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

        // assemble fundingManager config, authorizer config and deploy orchestrator
        IOrchestratorFactory_v1.ModuleConfig memory fundingManagerConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            PIMConfig.fundingManagerMetadata,
            abi.encode(
                address(issuanceToken),
                PIMConfig.bcProperties,
                PIMConfig.collateralToken
            )
        );

        IOrchestratorFactory_v1.ModuleConfig memory authorizerConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            PIMConfig.authorizerMetadata, abi.encode(address(this))
        );
        
        orchestrator = IOrchestratorFactory_v1(
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
        if (!PIMConfig.isRenouncedWorkflow) {
            _transferWorkflowAdminRights(
                orchestrator, PIMConfig.issuanceTokenParams.initialAdmin
            );
        }

        _manageInitialCollateral(
            fundingManager,
            PIMConfig.collateralToken,
            PIMConfig.bcProperties.initialCollateralSupply
        );

        emit IPIM_WorkflowFactory_v1.PIMWorkflowCreated(
            fundingManager,
            address(issuanceToken),
            _msgSender(),
            PIMConfig.recipient,
            PIMConfig.isRenouncedIssuanceToken,
            PIMConfig.isRenouncedWorkflow
        );

        return (orchestrator, issuanceToken);
    }

    //--------------------------------------------------------------------------
    // onlyOwner Functions

    /// @inheritdoc IPIM_WorkflowFactory_v1
    function setFee(uint newFee) external onlyOwner {
        fee = newFee;
        emit IPIM_WorkflowFactory_v1.FeeSet(newFee);
    }

    /// @inheritdoc IPIM_WorkflowFactory_v1
    function withdrawFee(IERC20 token, address to) external onlyOwner {
        token.transfer(to, token.balanceOf(address(this)));
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    function _manageInitialCollateral(
        address fundingManager,
        address collateralToken,
        uint initialCollateralSupply
    ) private {
        IERC20(collateralToken).transferFrom(
            _msgSender(), fundingManager, initialCollateralSupply
        );

        if (fee > 0) {
            uint feeAmount = _calculateFee(initialCollateralSupply);
            IERC20(collateralToken).transferFrom(
                _msgSender(), address(this), feeAmount
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

    function _calculateFee(uint collateralAmount) private view returns (uint) {
        return collateralAmount * fee / 10_000;
    }

    //--------------------------------------------------------------------------
    // ERC2771 Context

    /// Needs to be overriden, because they are imported via the Ownable2Step as well
    function _msgSender()
        internal
        view
        virtual
        override(ERC2771Context, Context)
        returns (address sender)
    {
        return ERC2771Context._msgSender();
    }

    /// Needs to be overriden, because they are imported via the Ownable2Step as well
    function _msgData()
        internal
        view
        virtual
        override(ERC2771Context, Context)
        returns (bytes calldata)
    {
        return ERC2771Context._msgData();
    }

    function _contextSuffixLength()
        internal
        view
        virtual
        override(ERC2771Context, Context)
        returns (uint)
    {
        return ERC2771Context._contextSuffixLength();
    }
}
