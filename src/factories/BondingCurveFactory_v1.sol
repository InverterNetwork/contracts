// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import "forge-std/console.sol";

// Internal Interfaces
import {
    IOrchestratorFactory_v1,
    IOrchestrator_v1,
    IModule_v1
} from "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {IFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IBondingCurveFactory_v1} from
    "src/factories/interfaces/IBondingCurveFactory_v1.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC20Issuance_v1} from "src/external/token/IERC20Issuance_v1.sol";

import {ERC20Issuance_v1} from "src/external/token/ERC20Issuance_v1.sol";

contract BondingCurveFactory_v1 {
    // store address of orchestratorfactory
    address public orchestratorFactory;

    constructor(address _orchestratorFactory) {
        orchestratorFactory = _orchestratorFactory;
    }

    function createBondingCurve(
        IOrchestratorFactory_v1.WorkflowConfig memory _workflowConfig,
        IOrchestratorFactory_v1.ModuleConfig memory _authorizerConfig,
        IOrchestratorFactory_v1.ModuleConfig memory _paymentProcessorConfig,
        IOrchestratorFactory_v1.ModuleConfig[] memory _moduleConfigs,
        IBondingCurveFactory_v1.LaunchConfig memory _launchConfig
    )
        external
        returns (IOrchestrator_v1 orchestrator, ERC20Issuance_v1 issuanceToken)
    {
        // deploy issuance token
        ERC20Issuance_v1 issuanceToken = new ERC20Issuance_v1(
            _launchConfig.issuanceTokenParams.name,
            _launchConfig.issuanceTokenParams.symbol,
            _launchConfig.issuanceTokenParams.decimals,
            _launchConfig.issuanceTokenParams.maxSupply,
            address(this) // assigns owner role to itself initially to manage minting rights temporarily
        );

        // mint initial issuance supply to initial admin
        issuanceToken.mint(
            _launchConfig.issuanceTokenParams.initialAdmin,
            _launchConfig.bcProperties.initialIssuanceSupply
        );

        // assemble fundingManager config and deploy orchestrator
        IOrchestratorFactory_v1.ModuleConfig memory f = IOrchestratorFactory_v1
            .ModuleConfig(
            _launchConfig.metadata,
            abi.encode(
                address(issuanceToken),
                _launchConfig.bcProperties,
                _launchConfig.collateralToken
            )
        );
        IOrchestrator_v1 orchestrator = IOrchestratorFactory_v1(
            orchestratorFactory
        ).createOrchestrator(
            _workflowConfig,
            f,
            _authorizerConfig,
            _paymentProcessorConfig,
            _moduleConfigs
        );

        // get bonding curve (= funding manager) address
        address fundingManager = address(orchestrator.fundingManager());
        issuanceToken.setMinter(fundingManager, true);

        // revoke minter role from factory
        issuanceToken.setMinter(address(this), false);
        emit IBondingCurveFactory_v1.BcPimCreated(address(issuanceToken));

        bytes32 adminRole = orchestrator.authorizer().getAdminRole();
        // if renounced flag is set, renounce all control
        if (_launchConfig.isRenounced) {
            _transferControl(orchestrator, issuanceToken, address(0));
        } else {
            _transferControl(
                orchestrator,
                issuanceToken,
                _launchConfig.issuanceTokenParams.initialAdmin
            );
        }

        // transfer initial collateral supply to funding manager
        IERC20(_launchConfig.collateralToken).transferFrom(
            msg.sender,
            fundingManager,
            _launchConfig.bcProperties.initialCollateralSupply
        );

        return (orchestrator, issuanceToken);
    }

    function _transferControl(
        IOrchestrator_v1 _orchestrator,
        ERC20Issuance_v1 _issuanceToken,
        address _newAdmin
    ) private {
        if (_newAdmin == address(0)) {
            _issuanceToken.renounceOwnership();
        } else {
            _issuanceToken.transferOwnership(_newAdmin);
        }

        bytes32 adminRole = _orchestrator.authorizer().getAdminRole();
        // set zero address as admin (because workflow must have at least one admin set)
        _orchestrator.authorizer().grantRole(adminRole, _newAdmin);
        // and revoke admin role from factory
        _orchestrator.authorizer().revokeRole(adminRole, address(this));
    }
}
