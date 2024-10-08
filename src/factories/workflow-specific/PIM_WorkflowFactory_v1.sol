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

/**
 * @title   Inverter PIM Workflow Factory
 *
 * @notice  Facilitates the creation and configuration and setup of PIM workflows, including the deployment of
 *          bonding curves and  issuance tokens. It also provides functionalities for updating fee recipients and
 *          withdrawing fees from bonding  curves.
 *
 * @dev     An owned factory for deploying PIM workflows. Deploying the PIM workflow includes:
 *          - Deploying the bonding curve and issuance token.
 *          - Enable bonding curve to mint issuance token.
 *          - Transfer initial collateral supply from msg.sender to bonding curve and mint issuance token to recipient.
 *          - If applicable make first purchase.
 *          - If flag is set, renounce admin role by setting factory as admin.
 *
 * @custom:security-contact security@inverter.network
 *                          For any security concerns or findings, please refer to our Security Policy at
 *                          security.inverter.network or email us directly.
 *
 * @custom:author Inverter Network
 */
contract PIM_WorkflowFactory_v1 is
    Ownable2Step,
    ERC2771Context,
    IPIM_WorkflowFactory_v1
{
    //--------------------------------------------------------------------------
    // State Variables

    /// @dev	store address of {Orchestratorfactory_v1}.
    address public orchestratorFactory;

    /// @dev	mapping of Funding Manager address to `feeRecipient` address.
    mapping(address fundingManager => address feeRecipient) private
        _pimFeeRecipients;

    //--------------------------------------------------------------------------
    // Modifiers

    /// @dev	Modifier to guarantee the caller is the fee recipient for the given funding manager.
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

        // get bonding curve / funding manager
        address fundingManager = address(orchestrator.fundingManager());

        // enable bonding curve to mint issuance token
        issuanceToken.setMinter(fundingManager, true);

        // transfer initial collateral supply from msg.sender to  bonding curve and mint issuance token to recipient
        _manageInitialSupplies(
            IBondingCurveBase_v1(fundingManager),
            IERC20(PIMConfig.collateralToken),
            issuanceToken,
            PIMConfig.bcProperties.initialCollateralSupply,
            PIMConfig.bcProperties.initialIssuanceSupply,
            PIMConfig.recipient,
            PIMConfig.withInitialLiquidity
        );

        // if applicable make first purchase
        _manageInitialPurchase(
            IBondingCurveBase_v1(fundingManager),
            IERC20(PIMConfig.collateralToken),
            PIMConfig.firstCollateralIn,
            PIMConfig.recipient
        );

        // disable factory to mint issuance token
        issuanceToken.setMinter(address(this), false);

        // if isRenouncedToken flag is set burn owner role, else transfer ownership to specified admin
        if (PIMConfig.isRenouncedIssuanceToken) {
            _transferTokenOwnership(issuanceToken, address(0));
        } else {
            _transferTokenOwnership(issuanceToken, PIMConfig.admin);
        }

        // if isRenouncedWorkflow flag is set factory keeps admin rights over workflow, else transfer admin rights to
        // specified admin
        if (PIMConfig.isRenouncedWorkflow) {
            // record the admin as fee recipient eligible to claim buy/sell fees
            _pimFeeRecipients[fundingManager] = PIMConfig.admin;
        } else {
            _transferWorkflowAdminRights(orchestrator, PIMConfig.admin);
        }

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
        emit IPIM_WorkflowFactory_v1.PimFeeClaimed(_msgSender(), amount);
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
        uint initialIssuanceSupply,
        address recipient,
        bool withInitialLiquidity
    ) private {
        if (withInitialLiquidity) {
            // collateral token is paid for by the msg.sender
            collateralToken.transferFrom(
                _msgSender(), address(fundingManager), initialCollateralSupply
            );
            // issuance token is minted to the the specified recipient
            issuanceToken.mint(recipient, initialIssuanceSupply);
        } else {
            // issuance token is minted to the burn address
            issuanceToken.mint(address(0xDEAD), initialIssuanceSupply);
        }
    }

    function _manageInitialPurchase(
        IBondingCurveBase_v1 fundingManager,
        IERC20 collateralToken,
        uint firstCollateralIn,
        address recipient
    ) private {
        // transfer initial collateral amount from deployer to factory
        collateralToken.transferFrom(
            _msgSender(), address(this), firstCollateralIn
        );

        // set allowance for curve to spend factory's tokens
        collateralToken.approve(address(fundingManager), firstCollateralIn);

        // make first purchase
        IBondingCurveBase_v1(fundingManager).buyFor(
            recipient, firstCollateralIn, 1
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

    //--------------------------------------------------------------------------
    // ERC2771 Context

    /// Needs to be overridden, because they are imported via the Ownable2Step as well.
    function _msgSender()
        internal
        view
        virtual
        override(ERC2771Context, Context)
        returns (address sender)
    {
        return ERC2771Context._msgSender();
    }

    /// Needs to be overridden, because they are imported via the Ownable2Step as well.
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
