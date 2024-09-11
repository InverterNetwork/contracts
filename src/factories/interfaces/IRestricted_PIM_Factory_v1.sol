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
 * @title   Inverter Restricted PIM Factory
 *
 * @notice  Used to deploy a PIM workflow with a restricted bonding curve with a mechanism to pre-fund
 *          the required collateral supply and an opinionated initial configuration.
 *
 * @dev     More user-friendly way to deploy a PIM workflow with an restricted bonding curve.
 *          Anyone can pre-fund the required collateral supply for a bonding curve deployment.
 *          Initial issuance token supply is minted to the deployer.
 *          The deployer receives the role to interact with the curve.
 *          Overall control over workflow remains with `initialAdmin` of the role authorizer.
 *
 * @custom:security-contact security@inverter.network
 *                          This contract is experimental in nature and has not been audited.
 *                          Please use at your own risk!
 *
 * @author  Inverter Network
 */
interface IRestricted_PIM_Factory_v1 {
    //--------------------------------------------------------------------------
    // Errors
    error InsufficientFunding(uint availableFunding);

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new PIM workflow is created.
    /// @param orchestrator The address of the orchestrator.
    /// @param issuanceToken The address of the issuance token.
    /// @param deployer The address of the deployer.
    event PIMWorkflowCreated(
        address indexed orchestrator,
        address indexed issuanceToken,
        address indexed deployer
    );

    /// @notice Event emitted when new funding is added.
    /// @param sponsor Address that pays funding.
    /// @param actor Address that can use new funding.
    /// @param token Address of token used for funding.
    /// @param amount Funding amount.
    event FundingAdded(
        address indexed sponsor,
        address indexed actor,
        address indexed token,
        uint amount
    );

    /// @notice Event emitted when existing funding is removed.
    /// @param sponsor Address that agreed to pay for funding.
    /// @param actor Address that could have used the funding.
    /// @param token Address of token used that would have been used for funding.
    /// @param amount Funding amount.
    event FundingRemoved(
        address indexed sponsor,
        address indexed actor,
        address indexed token,
        uint amount
    );

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Returns the amount of funding for a given sponsor, actor and token.
    /// @param  sponsor The address of the sponsor.
    /// @param  actor The address of the actor (who can use the funding).
    /// @param  token The address of the token used for funding.
    /// @return uint The amount of funding.
    function fundings(address sponsor, address actor, address token)
        external
        view
        returns (uint);

    /// @notice Deploys a new issuance token and uses that to deploy a workflow with restricted bonding curve.
    /// @param workflowConfig The workflow's config data.
    /// @param fundingManagerConfig The config data for the orchestrator's {IFundingManager_v1} instance.
    /// @param authorizerConfig The config data for the orchestrator's {IAuthorizer_v1} instance.
    /// @param paymentProcessorConfig The config data for the orchestrator's {IPaymentProcessor_v1} instance.
    /// @param moduleConfigs Variable length set of optional module's config data.
    /// @param issuanceTokenParams The issuance token's parameters (name, symbol, decimals, maxSupply).
    /// @return CreatedOrchestrator Returns the created orchestrator instance.
    function createPIMWorkflow(
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig,
        IOrchestratorFactory_v1.ModuleConfig memory fundingManagerConfig,
        IOrchestratorFactory_v1.ModuleConfig memory authorizerConfig,
        IOrchestratorFactory_v1.ModuleConfig memory paymentProcessorConfig,
        IOrchestratorFactory_v1.ModuleConfig[] memory moduleConfigs,
        IBondingCurveBase_v1.IssuanceToken memory issuanceTokenParams
    ) external returns (IOrchestrator_v1);

    /// @notice Adds `amount` of some `token` to factory to be used by some `actor` for a bonding curve deployment.
    /// @param actor The address that can use the funding for a new bonding curve deployment.
    /// @param token The token sent to the factory and to be used as collateral token for a bonding curve.
    /// @param amount The amount of `token` to be provided as initialCollateralSupply.
    function addFunding(address actor, address token, uint amount) external;

    /// @notice Withdraws an existing funding from the factory.
    /// @dev Can only be withdrawn by the address that added funding in the first place.
    /// @param actor The address could have used the funding for a new bonding curve deployment.
    /// @param token The token that was sent to the factory to be used as collateral token for a bonding curve.
    /// @param amount The amount of `token` that was provided.
    function withdrawFunding(address actor, address token, uint amount)
        external;
}
