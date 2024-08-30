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
import {IRestricted_PIM_Factory_v1} from
    "src/factories/interfaces/IRestricted_PIM_Factory_v1.sol";
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

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

contract Restricted_PIM_Factory_v1 is
    ERC2771Context,
    IRestricted_PIM_Factory_v1
{
    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // State Variables

    // Stores address of orchestratorfactory.
    address public orchestratorFactory;
    // Stores available fundings.
    mapping(
        address paymaster
            => mapping(address actor => mapping(address token => uint amount))
    ) fundings;

    //--------------------------------------------------------------------------
    // Constructor

    constructor(address _orchestratorFactory, address _trustedForwarder)
        ERC2771Context(_trustedForwarder)
    {
        orchestratorFactory = _orchestratorFactory;
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IRestricted_PIM_Factory_v1
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
        auhorizerConfigData = abi.encode(address(this));
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
            realAdmin,
            _msgSender()
        );

        // assign permissions to buy/sell from curve to admin
        bytes32 curveAccess = FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(
            fundingManager
        ).CURVE_INTERACTION_ROLE();
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(fundingManager)
            .grantModuleRole(curveAccess, _msgSender());
        // revoke minting rights from factory
        issuanceToken.setMinter(address(this), false);

        // revoke privileges from factory
        _transferTokenOwnership(issuanceToken, realAdmin);
        _transferWorkflowAdminRights(orchestrator, realAdmin);

        emit IRestricted_PIM_Factory_v1.PIMWorkflowCreated(
            address(orchestrator), address(issuanceToken), _msgSender()
        );
    }

    /// @inheritdoc IRestricted_PIM_Factory_v1
    function addFunding(address actor, address token, uint amount) external {
        // records funding amount
        fundings[_msgSender()][actor][token] += amount;
        // sends amount from msg.sender to factory
        IERC20(token).safeTransferFrom(_msgSender(), address(this), amount);

        emit IRestricted_PIM_Factory_v1.FundingAdded(
            _msgSender(), actor, token, amount
        );
    }

    /// @inheritdoc IRestricted_PIM_Factory_v1
    function withdrawFunding(address actor, address token, uint amount)
        external
    {
        // checks if the requested amount is available
        uint availableFunding = fundings[_msgSender()][actor][token];
        if (amount > availableFunding) {
            revert IRestricted_PIM_Factory_v1.InsufficientFunding(
                availableFunding
            );
        }
        // if so adjusts internal balancing
        fundings[_msgSender()][actor][token] -= amount;
        // and sends amount to msg sender
        IERC20(token).safeTransfer(_msgSender(), amount);

        emit IRestricted_PIM_Factory_v1.FundingRemoved(
            _msgSender(), actor, token, amount
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
        address admin,
        address actor
    ) private {
        uint availableFunding = fundings[admin][actor][address(collateralToken)];
        if (availableFunding < initialCollateralSupply) {
            revert IRestricted_PIM_Factory_v1.InsufficientFunding(
                availableFunding
            );
        }

        fundings[admin][actor][address(collateralToken)] -=
            initialCollateralSupply;

        // collateral token is paid for by the msg.sender
        collateralToken.safeTransfer(
            address(fundingManager), initialCollateralSupply
        );
        // issuance token is minted to the the specified recipient
        issuanceToken.mint(actor, initialIssuanceSupply);
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
        // grant role to address from role authorizer's `initialAdmin`
        orchestrator.authorizer().grantRole(adminRole, newAdmin);
        // and revoke admin role from factory
        orchestrator.authorizer().revokeRole(adminRole, address(this));
    }
}
