// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";

// Internal Dependencies
import {ERC20Issuance_v1} from "src/external/token/ERC20Issuance_v1.sol";

/**
 * @title   Immutable PIM Factory
 *
 * @notice  Used to deploy a PIM workflow with an unrestricted bonding curve and a mechanism to
 *          ensure immutability of the workflow while still enabling the claiming of fees.
 *
 * @dev     More user-friendly way to deploy a PIM workflow with an unrestricted bonding curve.
 *          Acts as wrapper for workflow to make it "unruggable" while exposing fee claiming functionality.
 *
 * @custom:security-contact security@inverter.network
 *                          This contract is experimental in nature and has not been audited.
 *                          Please use at your own risk!
 *
 * @author  Inverter Network
 */
interface IImmutable_PIM_Factory_v1 {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Error thrown when an unpermissioned address tries to claim fees or to transfer role.
    error PIM_WorkflowFactory__OnlyPimFeeRecipient();

    /// @notice Error thrown when a zero address is passed as initiator.
    error PIM_WorkflowFactory__InvalidZeroAddress();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new PIM workflow is created.
    /// @param orchestrator The address of the funding manager.
    /// @param issuanceToken The address of the issuance token.
    /// @param deployer The address of the deployer.
    event PIMWorkflowCreated(
        address indexed orchestrator,
        address indexed issuanceToken,
        address indexed deployer
    );

    /// @notice Event emitted when factory owner sets new fee.
    /// @param fundingManager The address of the funding manager.
    /// @param oldRecipient The previous pim fee recipient.
    /// @param  newRecipient The new pim fee recipient.
    event PimFeeRecipientUpdated(
        address indexed fundingManager,
        address indexed oldRecipient,
        address indexed newRecipient
    );

    /// @notice Event emitted when PIM fee (buy/sell fees) is claimed.
    /// @param fundingManager The address of the funding manager.
    /// @param  claimer The address of the one that is claiming.
    /// @param  to The address of that is receiving the fee.
    /// @param  amount The amount claimed.
    event PimFeeClaimed(
        address indexed fundingManager,
        address indexed claimer,
        address indexed to,
        uint amount
    );

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Deploys a new issuance with workflow that includes open yet immutable bonding curve.
    /// @param workflowConfig The workflow's config data.
    /// @param fundingManagerConfig The config data for the orchestrator's {IFundingManager_v1} instance.
    /// @param authorizerConfig The config data for the orchestrator's {IAuthorizer_v1} instance.
    /// @param paymentProcessorConfig The config data for the orchestrator's {IPaymentProcessor_v1} instance.
    /// @param moduleConfigs Variable length set of optional module's config data.
    /// @param issuanceTokenParams The issuance token's parameters (name, symbol, decimals, maxSupply).
    /// @param initialPurchaseAmount The volume of the first purchase in terms of collateral token.
    /// @return Returns an instance of the created orchestrator.
    function createPIMWorkflow(
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig,
        IOrchestratorFactory_v1.ModuleConfig memory fundingManagerConfig,
        IOrchestratorFactory_v1.ModuleConfig memory authorizerConfig,
        IOrchestratorFactory_v1.ModuleConfig memory paymentProcessorConfig,
        IOrchestratorFactory_v1.ModuleConfig[] memory moduleConfigs,
        IBondingCurveBase_v1.IssuanceToken memory issuanceTokenParams,
        uint initialPurchaseAmount
    ) external returns (IOrchestrator_v1);

    /// @notice Withdraws buy/sell fees accumulated by a bonding curve.
    /// @dev Only callable by the current fee recipient.
    /// @param fundingManager The address of the funding manager.
    /// @param to The address to send the fees to.
    function withdrawPimFee(address fundingManager, address to) external;

    /// @notice Transfers the fee recipient eligibility of a bonding curve to another address.
    /// @dev Only callable by the current fee recipient.
    /// @param fundingManager The address of the funding manager.
    /// @param to The address to transfer the fee recipient eligibility to.
    function transferPimFeeEligibility(address fundingManager, address to)
        external;
}
