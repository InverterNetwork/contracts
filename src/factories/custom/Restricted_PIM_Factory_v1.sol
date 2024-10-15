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
import {ILM_PC_PaymentRouter_v1} from
    "src/modules/logicModule/interfaces/ILM_PC_PaymentRouter_v1.sol";

// Internal Implementations
import {FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.sol";
import {LM_PC_PaymentRouter_v1} from
    "src/modules/logicModule/LM_PC_PaymentRouter_v1.sol";

// External Interfaces
import {IOwnable} from "@ex/interfaces/IOwnable.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Implementations
import {ERC20Issuance_v1} from "src/external/token/ERC20Issuance_v1.sol";
import {MintWrapper} from "src/external/token/MintWrapper.sol";

// External Dependencies
import {ERC2771Context, Context} from "@oz/metatx/ERC2771Context.sol";
import {ERC165} from "@oz/utils/introspection/ERC165.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

/**
 * @title   Inverter Restricted PIM Factory
 *
 * @notice  Used to deploy a PIM workflow with a restricted bonding curve with a
 *          mechanism to sponsor the required collateral supply and an
 *          opinionated initial configuration.
 *
 * @dev     More user-friendly way to deploy a PIM workflow with an restricted
 *          bonding curve. Anyone can sponsor the required collateral supply for
 *          a bonding curve deployment. Initial issuance token supply is minted
 *          to the deployer. The deployer receives the role to interact with the
 *          curve. Overall control over workflow remains with `initialAdmin` of
 *          the role authorizer.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @author  Inverter Network
 */
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
        address sponsor
            => mapping(address actor => mapping(address token => uint amount))
    ) public fundings;

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
        IBondingCurveBase_v1.IssuanceToken memory issuanceTokenParams,
        address beneficiary
    ) external returns (IOrchestrator_v1) {
        // deploy workflow and decode relevant config params
        (
            DeployedContracts memory deployedContracts,
            DecodedConfigParams memory decodedConfigParams
        ) = _deployWorkflow(
            workflowConfig,
            fundingManagerConfig,
            authorizerConfig,
            paymentProcessorConfig,
            moduleConfigs,
            issuanceTokenParams
        );

        // finish workflow configuration
        _configureWorkflow(deployedContracts, decodedConfigParams, beneficiary);

        emit IRestricted_PIM_Factory_v1.PIMWorkflowCreated(
            address(deployedContracts.orchestrator),
            address(deployedContracts.issuanceToken),
            beneficiary
        );

        return deployedContracts.orchestrator;
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

    // deploys
    function _deployWorkflow(
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig,
        IOrchestratorFactory_v1.ModuleConfig memory fundingManagerConfig,
        IOrchestratorFactory_v1.ModuleConfig memory authorizerConfig,
        IOrchestratorFactory_v1.ModuleConfig memory paymentProcessorConfig,
        IOrchestratorFactory_v1.ModuleConfig[] memory moduleConfigs,
        IBondingCurveBase_v1.IssuanceToken memory issuanceTokenParams
    ) private returns (DeployedContracts memory, DecodedConfigParams memory) {
        // MODIFY AUTHORIZER CONFIG
        // decode configData of authorizer
        // set (own) factory as orchestrator admin
        // store decoded realAdmin to return
        address realAdmin;
        {
            bytes memory auhorizerConfigData = authorizerConfig.configData;
            (realAdmin) = abi.decode(auhorizerConfigData, (address));
        }
        authorizerConfig.configData = abi.encode(address(this));

        // deploy issuance token
        ERC20Issuance_v1 issuanceToken = new ERC20Issuance_v1(
            issuanceTokenParams.name,
            issuanceTokenParams.symbol,
            issuanceTokenParams.decimals,
            issuanceTokenParams.maxSupply,
            address(this) // assigns owner role to itself initially to manage minting rights temporarily
        );

        // deploy mint wrapper
        MintWrapper mintWrapper = new MintWrapper(
            issuanceToken,
            address(this) // assigns owner role to itself initially to manage minting rights temporarily
        );

        // set mint wrapper as minter
        issuanceToken.setMinter(address(mintWrapper), true);
        // MODIFY FUNDING MANAGER CONFIG
        // decode configData of fundingManager
        // store bcProperties and collateralToken to return
        IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties memory
            bcProperties;
        address collateralToken;
        {
            bytes memory fundingManagerConfigData =
                fundingManagerConfig.configData;
            (, bcProperties, collateralToken) = abi.decode(
                fundingManagerConfigData,
                (
                    address,
                    IFM_BC_Bancor_Redeeming_VirtualSupply_v1
                        .BondingCurveProperties,
                    address
                )
            );
        }
        // set newly deployed mint wrapper as issuance token
        fundingManagerConfig.configData =
            abi.encode(address(mintWrapper), bcProperties, collateralToken);

        // deploy workflow
        IOrchestrator_v1 orchestrator = IOrchestratorFactory_v1(
            orchestratorFactory
        ).createOrchestrator(
            workflowConfig,
            fundingManagerConfig,
            authorizerConfig,
            paymentProcessorConfig,
            moduleConfigs
        );

        // return deployed contracts and all relevant decoded config params
        return (
            DeployedContracts({
                issuanceToken: issuanceToken,
                mintWrapper: mintWrapper,
                orchestrator: orchestrator
            }),
            DecodedConfigParams({
                collateralToken: IERC20(collateralToken),
                initialCollateralSupply: bcProperties.initialCollateralSupply,
                initialIssuanceSupply: bcProperties.initialIssuanceSupply,
                realAdmin: realAdmin
            })
        );
    }

    function _configureWorkflow(
        DeployedContracts memory deployedContracts,
        DecodedConfigParams memory decodedConfigParams,
        address beneficiary
    ) private {
        // get bonding curve / funding manager
        address fundingManager =
            address(deployedContracts.orchestrator.fundingManager());
        // get payment router
        address[] memory modules = deployedContracts.orchestrator.listModules();
        address paymentRouter;
        bytes4 paymentRouterInterfaceId =
            type(ILM_PC_PaymentRouter_v1).interfaceId;
        for (uint i; i < modules.length; ++i) {
            if (ERC165(modules[i]).supportsInterface(paymentRouterInterfaceId))
            {
                paymentRouter = modules[i];
            }
        }

        // enable bonding curve to mint issuance token
        deployedContracts.mintWrapper.setMinter(fundingManager, true);

        // transfer initial collateral supply from realAdmin to bonding curve and mint issuance token to msg.sender
        _manageInitialSupplies(
            IBondingCurveBase_v1(fundingManager),
            decodedConfigParams.collateralToken,
            deployedContracts.issuanceToken,
            decodedConfigParams.initialCollateralSupply,
            decodedConfigParams.initialIssuanceSupply,
            decodedConfigParams.realAdmin,
            beneficiary
        );

        // assign permissions to buy/sell from curve to admin
        bytes32 curveAccess = FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(
            fundingManager
        ).CURVE_INTERACTION_ROLE();
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(fundingManager)
            .grantModuleRole(curveAccess, beneficiary);

        // assign payment pusher role to beneficiary
        bytes32 paymentPusherRole =
            LM_PC_PaymentRouter_v1(paymentRouter).PAYMENT_PUSHER_ROLE();
        LM_PC_PaymentRouter_v1(paymentRouter).grantModuleRole(
            paymentPusherRole, beneficiary
        );

        // revoke privileges from factory
        _renounceTokenPrivileges(deployedContracts.issuanceToken);
        _transferWorkflowAdminRights(
            deployedContracts.orchestrator, decodedConfigParams.realAdmin
        );
        _transferOwnership(
            address(deployedContracts.mintWrapper),
            decodedConfigParams.realAdmin
        );
    }

    function _manageInitialSupplies(
        IBondingCurveBase_v1 fundingManager,
        IERC20 collateralToken,
        ERC20Issuance_v1 issuanceToken,
        uint initialCollateralSupply,
        uint initialIssuanceSupply,
        address admin,
        address beneficiary
    ) private {
        uint availableFunding =
            fundings[admin][beneficiary][address(collateralToken)];

        if (availableFunding < initialCollateralSupply) {
            revert IRestricted_PIM_Factory_v1.InsufficientFunding(
                availableFunding
            );
        }

        fundings[admin][beneficiary][address(collateralToken)] -=
            initialCollateralSupply;

        // collateral token funding needs to be sponsored beforehand
        collateralToken.safeTransfer(
            address(fundingManager), initialCollateralSupply
        );

        // issuance token is minted to the the specified recipient
        issuanceToken.mint(beneficiary, initialIssuanceSupply);
    }

    function _transferOwnership(address ownableContract, address newAdmin)
        private
    {
        if (newAdmin == address(0)) {
            IOwnable(ownableContract).renounceOwnership();
        } else {
            IOwnable(ownableContract).transferOwnership(newAdmin);
        }
    }

    function _renounceTokenPrivileges(ERC20Issuance_v1 issuanceToken) private {
        issuanceToken.setMinter(address(this), false);
        _transferOwnership(address(issuanceToken), address(0));
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
