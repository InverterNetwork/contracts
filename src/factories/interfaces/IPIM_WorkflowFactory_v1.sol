// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {IInverterBeacon_v1} from "src/proxies/interfaces/IInverterBeacon_v1.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IPIM_WorkflowFactory_v1} from
    "src/factories/interfaces/IPIM_WorkflowFactory_v1.sol";
import {IERC20Issuance_v1} from "src/external/token/IERC20Issuance_v1.sol";

// Internal Dependencies
import {ERC20Issuance_v1} from "src/external/token/ERC20Issuance_v1.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

interface IPIM_WorkflowFactory_v1 {
    //--------------------------------------------------------------------------
    // Errors
    /// @notice Error thrown when an unpermissioned address tries to claim fees to to transfer role.
    error PIM_WorkflowFactory__OnlyPimFeeRecipient();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new PIM workflow is created.
    /// @param bondingCurve The address of the bonding curve.
    /// @param issuanceToken The address of the issuance token.
    /// @param deployer The address of the deployer.
    /// @param recipient The address of the recipient.
    /// @param isRenouncedIssuanceToken If ownership over the issuance token should be renounced.
    /// @param isRenouncedWorkflow If admin rights over the workflow should be renounced.
    event PIMWorkflowCreated(
        address indexed bondingCurve,
        address indexed issuanceToken,
        address indexed deployer,
        address recipient,
        bool isRenouncedIssuanceToken,
        bool isRenouncedWorkflow
    );

    /// @notice Event emitted when factory owner sets new fee..
    /// @param fee The fee in basis points.
    event CreationFeeSet(uint fee);

    /// @notice Event emitted when factory owner withdraws accumulated creation fees.
    /// @param fundingManager The address of the funding manager from which to withdraw fees.
    /// @param to The address to which the fees are sent.
    /// @param amount The amount of fees that were withdrawn.
    event CreationFeeWithdrawn(
        address indexed fundingManager, address indexed to, uint amount
    );

    /// @notice Event emitted when factory owner sets new fee.
    /// @param oldRecipient The previous pim fee recipient.
    /// @param newRecipient The new pim fee recipient.
    event PimFeeRecipientUpdated(
        address indexed oldRecipient, address indexed newRecipient
    );

    //--------------------------------------------------------------------------
    // Structs

    /// @notice Struct for the issuance token parameters.
    /// @param name The name of the issuance token.
    /// @param symbol The symbol of the issuance token.
    /// @param decimals The decimals of the issuance token.
    /// @param maxSupply The maximum supply of the issuance token.
    /// @param initialAdmin The owner and initial minter of the issuance token.
    struct IssuanceTokenParams {
        string name;
        string symbol;
        uint8 decimals;
        uint maxSupply;
        address initialAdmin;
    }

    /// @notice Struct for the issuance token parameters.
    /// @param fundingManagerMetadata The funding manager's metadata.
    /// @param authorizerMetadata The authorizer's metadata.
    /// @param bcProperties The bonding curve's properties.
    /// @param issuanceTokenParams The issuance token's parameters.
    /// @param recipient The recipient of the initial issuance token supply.
    /// @param collateralToken The collateral token.
    /// @param isRenouncedIssuanceToken If ownership over the issuance token should be renounced.
    /// @param isRenouncedWorkflow If admin rights over the workflow should be renounced.
    struct PIMConfig {
        IModule_v1.Metadata fundingManagerMetadata;
        IModule_v1.Metadata authorizerMetadata;
        IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties
            bcProperties;
        IssuanceTokenParams issuanceTokenParams;
        address recipient;
        address collateralToken;
        bool isRenouncedIssuanceToken;
        bool isRenouncedWorkflow;
    }

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Deploys a workflow with a bonding curve and an issuance token
    /// @param workflowConfig The workflow's config data.
    /// @param paymentProcessorConfig The config data for the orchestrator's {IPaymentProcessor_v1} instance.
    /// @param moduleConfigs Variable length set of optional module's config data.
    /// @param PIMConfig The configuration for the issuance token and the bonding curve.
    /// @return Returns the address of orchestrator and the address of the issuance token.
    function createPIMWorkflow(
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig,
        IOrchestratorFactory_v1.ModuleConfig memory paymentProcessorConfig,
        IOrchestratorFactory_v1.ModuleConfig[] memory moduleConfigs,
        IPIM_WorkflowFactory_v1.PIMConfig memory PIMConfig
    ) external returns (IOrchestrator_v1, ERC20Issuance_v1);

    /// @notice Sets a fee in basis points that is added to the initial collateral supply and sent to the factory.
    /// @dev Only callable by the owner.
    /// @param newFee Fee in basis points.
    function setCreationFee(uint newFee) external;

    /// @notice  Withdraws the complete balance of the specified token to the specified address.
    /// @dev Only callable by the owner.
    /// @param token The token to withdraw.
    /// @param to The recipient of the withdrawn tokens.
    function withdrawCreationFee(IERC20 token, address to) external;

    /// @notice Updates who can claim the buy/sell fees of a given bonding curve.
    /// @dev Only callable by the currently eligible fee recipient.
    /// @param fundingManager The address of the bonding curve from which to withdraw fees.
    /// @param to The address that should be eligible to claim fees in the future.
    function transferPimFeeEligibility(address fundingManager, address to)
        external;

    /// @notice Withdraws the buy/sell fees of a given bonding curve.
    /// @dev Only callable by the currently eligible fee recipient.
    /// @param fundingManager The address of the bonding curve from which to withdraw fees.
    /// @param to The address to which the fees are sent.
    function withdrawPimFee(address fundingManager, address to) external;

    /// @notice Returns the address of the orchestrator factory.
    /// @return Address of the orchestrator factory.
    function orchestratorFactory() external view returns (address);

    /// @notice Returns the fee in basis points.
    /// @return Fee in basis points.
    function creationFee() external view returns (uint);
}
