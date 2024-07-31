// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import "forge-std/console.sol";

// Internal Interfaces
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IPIM_WorkflowFactory_v1} from
    "src/factories/interfaces/IPIM_WorkflowFactory_v1.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";

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
    uint public creationFee;

    // mapping of bonding curve address to fee recipient address
    mapping(address fundingManager => address feeRecipient) private
        _pimFeeRecipients;

    //--------------------------------------------------------------------------
    // Modifiers

    modifier onlyPimFeeRecipient(address fundingManager) {
        if (_msgSender() != _pimFeeRecipients[fundingManager]) {
            revert PIM_WorkflowFactory__OnlyPimFeeRecipient();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Constructor

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

        orchestrator = IOrchestratorFactory_v1(orchestratorFactory)
            .createOrchestrator(
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

        // if renounced token flag is set, renounce ownership over token, else transfer ownership to specified admin
        if (PIMConfig.isRenouncedIssuanceToken) {
            _transferTokenOwnership(issuanceToken, address(0));
        } else {
            _transferTokenOwnership(issuanceToken, PIMConfig.admin);
        }

        // if renounced workflow flag is set factory keeps admin rights over workflow, else transfer admin rights to specified admin
        if (PIMConfig.isRenouncedWorkflow) {
            // record the admin as fee recipient eligible to claim buy/sell fees
            _pimFeeRecipients[fundingManager] = PIMConfig.admin;
        } else {
            _transferWorkflowAdminRights(orchestrator, PIMConfig.admin);
        }

        _manageInitialSupplies(
            IBondingCurveBase_v1(fundingManager),
            IERC20(PIMConfig.collateralToken),
            issuanceToken,
            PIMConfig.bcProperties.initialCollateralSupply,
            PIMConfig.bcProperties.initialIssuanceSupply
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
    // Permissioned Functions

    // onlyOwner

    /// @inheritdoc IPIM_WorkflowFactory_v1
    function setCreationFee(uint newFee) external onlyOwner {
        creationFee = newFee;
        emit IPIM_WorkflowFactory_v1.CreationFeeSet(newFee);
    }

    /// @inheritdoc IPIM_WorkflowFactory_v1
    function withdrawCreationFee(IERC20 token, address to) external onlyOwner {
        token.transfer(to, token.balanceOf(address(this)));
    }

    // onlyPimFeeRecipient

    /// @inheritdoc IPIM_WorkflowFactory_v1
    function withdrawPimFee(address fundingManager, address to)
        external
        onlyPimFeeRecipient(fundingManager)
    {
        uint amount =
            IBondingCurveBase_v1(fundingManager).projectCollateralFeeCollected();
        IBondingCurveBase_v1(fundingManager).withdrawProjectCollateralFee(
            to, amount
        );
        emit IPIM_WorkflowFactory_v1.CreationFeeWithdrawn(
            fundingManager, to, amount
        );
    }

    /// @inheritdoc IPIM_WorkflowFactory_v1
    function transferPimFeeEligibility(address fundingManager, address to)
        external
        onlyPimFeeRecipient(fundingManager)
    {
        _pimFeeRecipients[fundingManager] = to;
        emit IPIM_WorkflowFactory_v1.PimFeeRecipientUpdated(_msgSender(), to);
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    function _manageInitialSupplies(
        IBondingCurveBase_v1 fundingManager,
        IERC20 collateralToken,
        ERC20Issuance_v1 issuanceToken,
        uint initialCollateralSupply,
        uint initialIssuanceSupply
    ) private {
        collateralToken.transferFrom(
            _msgSender(), fundingManager, initialCollateralSupply
        );

        if (creationFee > 0) {
            uint feeAmount = _calculateFee(initialCollateralSupply);
            collateralToken.transferFrom(
                _msgSender(), address(this), feeAmount
            );
        }

        issuanceToken.mint(
            PIMConfig.recipient, PIMConfig.bcProperties.initialIssuanceSupply
        );
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
        return collateralAmount * creationFee / 10_000;
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
