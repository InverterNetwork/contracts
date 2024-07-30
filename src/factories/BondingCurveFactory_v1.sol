// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IBondingCurveFactory_v1} from
    "src/factories/interfaces/IBondingCurveFactory_v1.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Implementations
import {ERC20Issuance_v1} from "src/external/token/ERC20Issuance_v1.sol";

// External Dependencies
import {Ownable} from "@oz/access/Ownable.sol";

contract BondingCurveFactory_v1 is Ownable {
    // store address of orchestratorfactory
    address public orchestratorFactory;
    // relative fees on collateral token in basis points
    uint public fee;

    constructor(address _orchestratorFactory, address _owner) Ownable(_owner) {
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

        // mint initial issuance supply to recipient
        issuanceToken.mint(
            _launchConfig.recipient,
            _launchConfig.bcProperties.initialIssuanceSupply
        );

        // assemble fundingManager config and deploy orchestrator
        IOrchestratorFactory_v1.ModuleConfig memory fundingManagerConfig =
        IOrchestratorFactory_v1.ModuleConfig(
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
            fundingManagerConfig,
            _authorizerConfig,
            _paymentProcessorConfig,
            _moduleConfigs
        );

        // get bonding curve (= funding manager) address
        address fundingManager = address(orchestrator.fundingManager());
        issuanceToken.setMinter(fundingManager, true);

        // revoke minter role from factory
        issuanceToken.setMinter(address(this), false);

        // if renounced token flag is set, renounce ownership over token, else transfer ownership to initial admin
        if (_launchConfig.isRenouncedIssuanceToken) {
            _transferTokenOwnership(issuanceToken, address(0));
        } else {
            _transferTokenOwnership(
                issuanceToken, _launchConfig.issuanceTokenParams.initialAdmin
            );
        }

        // if renounced workflow flag is set, renounce admin rights over workflow, else transfer admin rights to initial admin
        if (_launchConfig.isRenouncedWorkflow) {
            _transferWorkflowAdminRights(orchestrator, address(0));
        } else {
            _transferWorkflowAdminRights(
                orchestrator, _launchConfig.issuanceTokenParams.initialAdmin
            );
        }

        _manageInitialCollateral(
            fundingManager,
            _launchConfig.collateralToken,
            _launchConfig.bcProperties.initialCollateralSupply
        );

        emit IBondingCurveFactory_v1.BcPimCreated(address(issuanceToken));

        return (orchestrator, issuanceToken);
    }

    function setFee(uint _fee) external onlyOwner {
        fee = _fee;
        emit IBondingCurveFactory_v1.FeeSet(_fee);
    }

    function withdrawFee(IERC20 _token, address _to) external onlyOwner {
        _token.transfer(
            _to, _token.balanceOf(address(this))
        );
    }

    function _manageInitialCollateral(
        address _fundingManager,
        address _collateralToken,
        uint _initialCollateralSupply
    ) internal {
        IERC20(_collateralToken).transferFrom(
            msg.sender, _fundingManager, _initialCollateralSupply
        );

        if (fee > 0) {
            uint feeAmount = _calculateFee(_initialCollateralSupply);
            IERC20(_collateralToken).transferFrom(
                msg.sender, address(this), feeAmount
            );
        }
    }

    function _transferTokenOwnership(
        ERC20Issuance_v1 _issuanceToken,
        address _newAdmin
    ) private {
        if (_newAdmin == address(0)) {
            _issuanceToken.renounceOwnership();
        } else {
            _issuanceToken.transferOwnership(_newAdmin);
        }
    }

    function _transferWorkflowAdminRights(
        IOrchestrator_v1 _orchestrator,
        address _newAdmin
    ) private {
        bytes32 adminRole = _orchestrator.authorizer().getAdminRole();
        // if renounced flag is set, add zero address as admin (because workflow must have at least one admin set)
        _orchestrator.authorizer().grantRole(adminRole, _newAdmin);
        // and revoke admin role from factory
        _orchestrator.authorizer().revokeRole(adminRole, address(this));
    }

    function _calculateFee(uint _collateralAmount)
        internal
        view
        returns (uint)
    {
        return _collateralAmount * fee / 10_000;
    }
}
