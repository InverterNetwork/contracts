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
import {MintWrapper} from "src/external/token/MintWrapper.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

/**
 * @title   Inverter Restricted PIM Factory
 *
 * @notice  Used to deploy a PIM workflow with a restricted bonding curve with a
 *          mechanism to sponsor the required collateral supply and a highly
 *          opinionated initial configuration.
 *
 * @dev     More user-friendly way to deploy a use case-specific PIM workflow
 *          with an restricted bonding curve. Anyone can sponsor the
 *          required collateral supply for a bonding curve deployment. Initial
 *          issuance token supply is minted to the beneficiary. The beneficiary receives
 *          the role to interact with the curve. Overall control over workflow remains
 *          with `initialAdmin` of the role authorizer.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @author  Inverter Network
 */
interface IRestricted_PIM_Factory_v1 {
    //--------------------------------------------------------------------------
    // Structs

    /// @notice Contains all contracts deployed by the factory.
    /// @param  orchestrator The orchestrator contract.
    /// @param  issuanceToken The issuance token.
    /// @param  mintWrapper The wrapper that directly mints from issuance token.
    struct DeployedContracts {
        IOrchestrator_v1 orchestrator;
        ERC20Issuance_v1 issuanceToken;
        MintWrapper mintWrapper;
    }

    /// @notice Contains all decoded configuration parameters.
    /// @param  collateralToken The collateral token.
    /// @param  initialCollateralSupply The initial collateral supply.
    /// @param  initialIssuanceSupply The initial issuance supply.
    /// @param  realAdmin The admin of the workflow.
    struct DecodedConfigParams {
        IERC20 collateralToken;
        uint initialCollateralSupply;
        uint initialIssuanceSupply;
        address realAdmin;
    }

    /// @notice Contains information about a funding.
    /// @dev The sponsor is stored in this struct (vs in the mapping) to not have
    ///      the deployer have to know about the sponsor.
    /// @param  amount The amount of funding.
    /// @param  sponsor The address of the sponsor.
    struct Funding {
        uint amount;
        address sponsor;
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice There is not enough funding for the desired transaction.
    /// @param  availableFunding Currently available funding.
    error InsufficientFunding(uint availableFunding);

    /// @notice The funding has already been added by a different sponsor.
    /// @dev This is to prevent a new sponsor adding funding to a previously
    ///      funded deployment.
    error FundingAlreadyAddedByDifferentSponsor();

    /// @notice The caller is not authorized to perform the desired action.
    error NotAuthorized();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new PIM workflow is created.
    /// @param orchestrator The address of the orchestrator.
    /// @param issuanceToken The token issued by the bonding curve.
    /// @param beneficiary The beneficiary receives initial issuance supply and minting rights.
    event PIMWorkflowCreated(
        address indexed orchestrator,
        address indexed issuanceToken,
        address indexed beneficiary
    );

    /// @notice Event emitted when new funding is added.
    /// @param sponsor Address that sponsors the funding.
    /// @param deployer Address that can do the deployment.
    /// @param beneficiary Address that can use new funding.
    /// @param admin Address that can interact with the workflow.
    /// @param token Address of token used for funding.
    /// @param amount Funding amount.
    event FundingAdded(
        address indexed sponsor,
        address indexed deployer,
        address indexed beneficiary,
        address admin,
        address token,
        uint amount
    );

    /// @notice Event emitted when existing funding is removed.
    /// @param sponsor Address that would have sponsored the funding.
    /// @param deployer Address that could have done the deployment.
    /// @param beneficiary Address that could have used new funding.
    /// @param admin Address that could have interacted with the workflow.
    /// @param token Address of token used for funding.
    /// @param amount Funding amount.
    event FundingRemoved(
        address indexed sponsor,
        address indexed deployer,
        address indexed beneficiary,
        address admin,
        address token,
        uint amount
    );

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Returns an existing Funding.
    /// @param  deployer The address of the deployer.
    /// @param  beneficiary The address of the beneficiary (who receives benefits of deployment).
    /// @param  admin The address of the admin.
    /// @param  token The address of the token used for funding.
    /// @return amount The amount of funding.
    /// @return sponsor The address of the sponsor.
    function fundings(
        address deployer,
        address beneficiary,
        address admin,
        address token
    ) external view returns (uint amount, address sponsor);

    /// @notice Deploys a new issuance token and uses that to deploy a workflow with restricted bonding curve.
    /// @dev Requires the deployment to have been funded previously via `addFunding`.
    /// @param workflowConfig The workflow's config data.
    /// @param fundingManagerConfig The config data for the orchestrator's {IFundingManager_v1} instance.
    /// @param authorizerConfig The config data for the orchestrator's {IAuthorizer_v1} instance.
    /// @param paymentProcessorConfig The config data for the orchestrator's {IPaymentProcessor_v1} instance.
    /// @param moduleConfigs Variable length set of optional module's config data.
    /// @param issuanceTokenParams The issuance token's parameters (name, symbol, decimals, maxSupply).
    /// @param beneficiary The beneficiary of the PIM receives initial supply & holds minting rights).
    /// @return CreatedOrchestrator Returns the created orchestrator instance.
    function createPIMWorkflow(
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig,
        IOrchestratorFactory_v1.ModuleConfig memory fundingManagerConfig,
        IOrchestratorFactory_v1.ModuleConfig memory authorizerConfig,
        IOrchestratorFactory_v1.ModuleConfig memory paymentProcessorConfig,
        IOrchestratorFactory_v1.ModuleConfig[] memory moduleConfigs,
        IBondingCurveBase_v1.IssuanceToken memory issuanceTokenParams,
        address beneficiary
    ) external returns (IOrchestrator_v1);

    /// @notice Adds `amount` of some `token` to factory to be used by some `actor` for a bonding curve deployment.
    /// @param deployer The address that can do the deployment.
    /// @param beneficiary The address that can use the funding.
    /// @param admin The address that controls the workflow.
    /// @param token The token used for funding.
    /// @param amount The amount of `token` to be provided as initialCollateralSupply.
    function addFunding(
        address deployer,
        address beneficiary,
        address admin,
        address token,
        uint amount
    ) external;

    /// @notice Withdraws an existing funding from the factory.
    /// @dev Can only be withdrawn by the address that added funding in the first place.
    /// @param deployer The address that could have dobe the deployment.
    /// @param beneficiary The address that could have used the funding.
    /// @param admin The address that would have controlled the workflow.
    /// @param token The token supposed to be used for funding.
    /// @param amount The amount of `token` to be withdrawn.
    function withdrawFunding(
        address deployer,
        address beneficiary,
        address admin,
        address token,
        uint amount
    ) external;
}
