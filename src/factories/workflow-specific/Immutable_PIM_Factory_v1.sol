// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IImmutable_PIM_Factory_v1} from
    "src/factories/interfaces/IImmutable_PIM_Factory_v1.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";

// Internal Implementations
import {FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Implementations
import {ERC20Issuance_v1} from "src/external/token/ERC20Issuance_v1.sol";

// External Dependencies
import {ERC2771Context, Context} from "@oz/metatx/ERC2771Context.sol";

contract Immutable_PIM_Factory_v1 is
    ERC2771Context,
    IImmutable_PIM_Factory_v1
{
    //--------------------------------------------------------------------------
    // State Variables

    /// @dev	Stores address of {Orchestratorfactory_v1}.
    address public orchestratorFactory;

    /// @dev	Mapping of who can claim fees for a given funding manager.
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

    constructor(address _orchestratorFactory, address _trustedForwarder)
        ERC2771Context(_trustedForwarder)
    {
        orchestratorFactory = _orchestratorFactory;
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IImmutable_PIM_Factory_v1
    function createPIMWorkflow(
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig,
        IOrchestratorFactory_v1.ModuleConfig memory fundingManagerConfig,
        IOrchestratorFactory_v1.ModuleConfig memory authorizerConfig,
        IOrchestratorFactory_v1.ModuleConfig memory paymentProcessorConfig,
        IOrchestratorFactory_v1.ModuleConfig[] memory moduleConfigs,
        IBondingCurveBase_v1.IssuanceToken memory issuanceTokenParams,
        uint initialPurchaseAmount
    ) external returns (IOrchestrator_v1 orchestrator) {
        // deploy issuance token
        ERC20Issuance_v1 issuanceToken = new ERC20Issuance_v1(
            issuanceTokenParams.name,
            issuanceTokenParams.symbol,
            issuanceTokenParams.decimals,
            issuanceTokenParams.maxSupply,
            address(this) // assigns owner role to itself initially to manage minting rights temporarily
        );

        // MODIFY AUTHORIZER CONFIG
        // decode configData of authorizer
        // set (own) factory as orchestrator admin
        // reinterpret the `initialAdmin` field as the `initiator` address
        bytes memory authorizerConfigData = authorizerConfig.configData;
        (address initiator) = abi.decode(authorizerConfigData, (address));
        if (initiator == address(0)) {
            revert
                IImmutable_PIM_Factory_v1
                .PIM_WorkflowFactory__InvalidZeroAddress();
        }
        authorizerConfigData = abi.encode(address(this));
        authorizerConfig.configData = authorizerConfigData;

        // MODIFY FUNDING MANAGER CONFIG
        // decode configData of fundingManager
        // set newly deployed token as issuance token
        bytes memory fundingManagerConfigData = fundingManagerConfig.configData;
        (
            ,
            IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties
                memory bcProperties,
            address collateralToken
        ) = abi.decode(
            fundingManagerConfigData,
            (
                address,
                IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties,
                address
            )
        );
        fundingManagerConfigData =
            abi.encode(address(issuanceToken), bcProperties, collateralToken);
        fundingManagerConfig.configData = fundingManagerConfigData;

        // deploy workflow
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

        // enable bonding curve to mint issuance token and disable minting from factory
        issuanceToken.setMinter(fundingManager, true);
        issuanceToken.setMinter(address(this), false);

        // if initial purchase amount is set (> 0) execute first purchase from curve
        // recipient: initiator
        if (initialPurchaseAmount > 0) {
            IERC20(collateralToken).transferFrom(
                _msgSender(), address(this), initialPurchaseAmount
            );
            IERC20(collateralToken).approve(
                fundingManager, initialPurchaseAmount
            );
            IBondingCurveBase_v1(fundingManager).buyFor(
                initiator, initialPurchaseAmount, 1
            );
        }

        // set fee recipient (initiator)
        _pimFeeRecipients[fundingManager] = initiator;

        // renounce token ownership
        issuanceToken.renounceOwnership();

        emit IImmutable_PIM_Factory_v1.PIMWorkflowCreated(
            address(orchestrator), address(issuanceToken), _msgSender()
        );
    }

    //--------------------------------------------------------------------------
    // Permissioned Functions

    /// @inheritdoc IImmutable_PIM_Factory_v1
    function withdrawPimFee(address fundingManager, address to)
        external
        onlyPimFeeRecipient(fundingManager)
    {
        // get accumulated fee amount from bonding curve
        uint amount =
            IBondingCurveBase_v1(fundingManager).projectCollateralFeeCollected();
        // withdraw fee from bonding curve and send to `to`
        IBondingCurveBase_v1(fundingManager).withdrawProjectCollateralFee(
            to, amount
        );
        emit IImmutable_PIM_Factory_v1.PimFeeClaimed(
            fundingManager, _msgSender(), to, amount
        );
    }

    /// @inheritdoc IImmutable_PIM_Factory_v1
    function transferPimFeeEligibility(address fundingManager, address to)
        external
        onlyPimFeeRecipient(fundingManager)
    {
        _pimFeeRecipients[fundingManager] = to;
        emit IImmutable_PIM_Factory_v1.PimFeeRecipientUpdated(
            fundingManager, _msgSender(), to
        );
    }
}
