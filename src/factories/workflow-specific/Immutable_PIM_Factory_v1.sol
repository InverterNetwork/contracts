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

    // store address of orchestratorfactory
    address public orchestratorFactory;

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
        IBondingCurveBase_v1.IssuanceToken memory issuanceTokenParams
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
        bytes memory auhorizerConfigData = authorizerConfig.configData;
        (address realAdmin) = abi.decode(auhorizerConfigData, (address));
        address temporaryAdmin = address(this);
        auhorizerConfigData = abi.encode(temporaryAdmin);
        authorizerConfig.configData = auhorizerConfigData;

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
            IERC20(collateralToken),
            issuanceToken,
            bcProperties.initialCollateralSupply,
            bcProperties.initialIssuanceSupply,
            realAdmin
        );

        // assign permissions to buy/sell from curve to admin
        bytes32 curveAccess = FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(
            fundingManager
        ).CURVE_INTERACTION_ROLE();
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(fundingManager)
            .grantModuleRole(curveAccess, realAdmin);
        // revoke minting rights from factory
        issuanceToken.setMinter(address(this), false);

        // revoke privileges from factory
        _transferTokenOwnership(issuanceToken, realAdmin);
        _transferWorkflowAdminRights(orchestrator, realAdmin);

        emit IImmutable_PIM_Factory_v1.PIMWorkflowCreated(
            address(orchestrator), address(issuanceToken), _msgSender()
        );
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    function _manageInitialSupplies(
        IBondingCurveBase_v1 fundingManager,
        IERC20 collateralToken,
        ERC20Issuance_v1 issuanceToken,
        uint initialCollateralSupply,
        uint initialIssuanceSupply,
        address recipient
    ) private {
        // collateral token is paid for by the msg.sender
        collateralToken.transferFrom(
            _msgSender(), address(fundingManager), initialCollateralSupply
        );
        // issuance token is minted to the the specified recipient
        issuanceToken.mint(recipient, initialIssuanceSupply);
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
}
