// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IPIM_WorkflowFactory} from
    "src/factories/interfaces/IPIM_WorkflowFactory.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Implementations
import {ERC20Issuance_v1} from "src/external/token/ERC20Issuance_v1.sol";

// External Dependencies
import {Ownable} from "@oz/access/Ownable.sol";

contract PIM_WorkflowFactory is Ownable, IPIM_WorkflowFactory {
    // store address of orchestratorfactory
    address public orchestratorFactory;
    // relative fees on collateral token in basis points
    uint public fee;

    constructor(address _orchestratorFactory, address _owner) Ownable(_owner) {
        orchestratorFactory = _orchestratorFactory;
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IPIM_WorkflowFactory
    function createPIMWorkflow(
        IOrchestratorFactory_v1.WorkflowConfig memory _workflowConfig,
        IOrchestratorFactory_v1.ModuleConfig memory _authorizerConfig,
        IOrchestratorFactory_v1.ModuleConfig memory _paymentProcessorConfig,
        IOrchestratorFactory_v1.ModuleConfig[] memory _moduleConfigs,
        IPIM_WorkflowFactory.PIMConfig memory _PIMConfig
    )
        external
        returns (IOrchestrator_v1 orchestrator, ERC20Issuance_v1 issuanceToken)
    {
        // deploy issuance token
        ERC20Issuance_v1 issuanceToken = new ERC20Issuance_v1(
            _PIMConfig.issuanceTokenParams.name,
            _PIMConfig.issuanceTokenParams.symbol,
            _PIMConfig.issuanceTokenParams.decimals,
            _PIMConfig.issuanceTokenParams.maxSupply,
            address(this) // assigns owner role to itself initially to manage minting rights temporarily
        );

        // mint initial issuance supply to recipient
        issuanceToken.mint(
            _PIMConfig.recipient, _PIMConfig.bcProperties.initialIssuanceSupply
        );

        // assemble fundingManager config and deploy orchestrator
        IOrchestratorFactory_v1.ModuleConfig memory fundingManagerConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            _PIMConfig.metadata,
            abi.encode(
                address(issuanceToken),
                _PIMConfig.bcProperties,
                _PIMConfig.collateralToken
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
        if (_PIMConfig.isRenouncedIssuanceToken) {
            _transferTokenOwnership(issuanceToken, address(0));
        } else {
            _transferTokenOwnership(
                issuanceToken, _PIMConfig.issuanceTokenParams.initialAdmin
            );
        }

        // if renounced workflow flag is set, renounce admin rights over workflow, else transfer admin rights to initial admin
        if (_PIMConfig.isRenouncedWorkflow) {
            _transferWorkflowAdminRights(orchestrator, address(0));
        } else {
            _transferWorkflowAdminRights(
                orchestrator, _PIMConfig.issuanceTokenParams.initialAdmin
            );
        }

        _manageInitialCollateral(
            fundingManager,
            _PIMConfig.collateralToken,
            _PIMConfig.bcProperties.initialCollateralSupply
        );

        emit IPIM_WorkflowFactory.PIMWorkflowCreated(address(issuanceToken));

        return (orchestrator, issuanceToken);
    }

    //--------------------------------------------------------------------------
    // onlyOwner Functions

    /// @inheritdoc IPIM_WorkflowFactory
    function setFee(uint _fee) external onlyOwner {
        fee = _fee;
        emit IPIM_WorkflowFactory.FeeSet(_fee);
    }

    /// @inheritdoc IPIM_WorkflowFactory
    function withdrawFee(IERC20 _token, address _to) external onlyOwner {
        _token.transfer(_to, _token.balanceOf(address(this)));
    }

    //--------------------------------------------------------------------------
    // Internal Functions

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
