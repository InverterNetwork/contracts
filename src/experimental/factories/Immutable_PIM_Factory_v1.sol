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
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";

import {IImmutable_PIM_Factory_v1} from
    "src/experimental/factories/interfaces/IImmutable_PIM_Factory_v1.sol";
import {LM_ImmutableMigration_v1} from
    "src/experimental/modules/ImmutableMigration/LM_ImmutableMigration_v1.sol";

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
    //-------------------------------------------------------------------------
    // Constants

    uint constant COLLATERAL_MIGRATION_THRESHOLD = 10_000 ether;

    //--------------------------------------------------------------------------
    // State Variables

    /// @dev	store address of {Orchestratorfactory_v1}.
    address public orchestratorFactory;

    mapping(address issuanceToken => PIM orchestrator) public pims;

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
        bytes memory authorizerConfigData = authorizerConfig.configData;
        (address initiator) = abi.decode(authorizerConfigData, (address));
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

        // store orchestrator for issuance token
        pims[address(issuanceToken)] = PIM(
            orchestrator,
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(fundingManager)
                .getVirtualIssuanceSupply(),
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(fundingManager)
                .getVirtualCollateralSupply()
        );

        // enable bonding curve to mint issuance token
        issuanceToken.setMinter(fundingManager, true);
        // grant privileges to factory
        bytes32 adminRole = orchestrator.authorizer().getAdminRole();
        bytes32 curveAccess = FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(
            fundingManager
        ).CURVE_INTERACTION_ROLE();
        orchestrator.authorizer().grantRole(adminRole, address(this));
        issuanceToken.setMinter(address(this), true);
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(fundingManager)
            .grantModuleRole(curveAccess, address(this));

        // if initial purchase amount set execute first purchase from curve
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

        // renounce token ownership
        issuanceToken.renounceOwnership();

        emit IImmutable_PIM_Factory_v1.PIMWorkflowCreated(
            address(orchestrator), address(issuanceToken), _msgSender()
        );
    }

    /**
     * @notice Buys tokens from the bonding curve funding manager for a recipient
     * @param token The issuance token to buy
     * @param amountIn The maximum amount of collateral tokens to spend
     * @param recipient The address to receive the purchased tokens
     */
    function buyForUpTo(
        address token,
        address recipient,
        uint amountIn,
        uint minAmountOut
    ) external {
        PIM memory pim = pims[token];
        address fundingManager = address(pim.orchestrator.fundingManager());
        IERC20 collateralToken = pim.orchestrator.fundingManager().token();

        console.log("check1");

        // Transfer collateral tokens from sender to this contract
        collateralToken.transferFrom(msg.sender, address(this), amountIn);
        console.log("check2");
        // Approve funding manager to spend collateral tokens
        collateralToken.approve(fundingManager, amountIn);

        // Check if buy would exceed threshold by calculating how much of amountIn
        // is valid (can be used for buying) and how much is excess (is reimbursed)
        (uint excessAmountIn, uint validAmountIn) =
            _checkBuyExceedsThreshold(token, amountIn);

        // Use valid amount to buy from curve
        if (validAmountIn > 0) {
            IBondingCurveBase_v1(fundingManager).buyFor(
                recipient, validAmountIn, minAmountOut
            );
        }

        console.log("check3");

        // Reimburse potential
        if (excessAmountIn > 0) {
            collateralToken.transfer(_msgSender(), excessAmountIn);
        }

        // If threshold has been reached, close curve and initiate graduation
        if (
            collateralToken.balanceOf(fundingManager)
                == COLLATERAL_MIGRATION_THRESHOLD
                    - pim.initialVirtualCollateralSupply
        ) {
            // Close buying & selling on the funding manager
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(fundingManager)
                .closeBuy();
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(fundingManager)
                .closeSell();

            // Initiate graduation
            // _graduate();
        }
    }

    // function sellFor(address recipient, uint amountIn, uint minAmountOut)
    //     external
    // {
    //     FM_BC_Bancor_Redeeming_VirtualSupply_v1 fundingManager =
    //     FM_BC_Bancor_Redeeming_VirtualSupply_v1(
    //         address(__Module_orchestrator.fundingManager())
    //     );
    //     IERC20Issuance_v1 issuanceToken =
    //         IERC20Issuance_v1(fundingManager.getIssuanceToken());

    //     // Transfer issuance tokens from sender to this contract
    //     issuanceToken.transferFrom(msg.sender, address(this), amountIn);

    //     // Approve funding manager to spend issuance token
    //     issuanceToken.approve(address(fundingManager), amountIn);

    //     // Make sell order
    //     fundingManager.sellTo(recipient, amountIn, minAmountOut);
    // }

    function _checkBuyExceedsThreshold(address token, uint amountIn)
        internal
        view
        returns (uint excessAmountIn, uint validAmountIn)
    {
        PIM memory pim = pims[token];

        // Get funding manager and collateral token
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 fundingManager =
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(
            address(pim.orchestrator.fundingManager())
        );

        // Get virtual collateral supply before and after buy
        uint currentCollateral = fundingManager.getVirtualCollateralSupply();
        uint collateralAfterBuy = currentCollateral + amountIn;

        // Check if total would exceed threshold
        if (collateralAfterBuy > COLLATERAL_MIGRATION_THRESHOLD) {
            // Calculate how much can be validly bought before hitting threshold
            validAmountIn = COLLATERAL_MIGRATION_THRESHOLD > currentCollateral
                ? COLLATERAL_MIGRATION_THRESHOLD - currentCollateral
                : 0;

            // Remaining amount is excess
            excessAmountIn = amountIn - validAmountIn;
        } else {
            // Entire amount is valid if under threshold
            validAmountIn = amountIn;
            excessAmountIn = 0;
        }
    }

    // function _graduate() internal {
    //     FM_BC_Bancor_Redeeming_VirtualSupply_v1 fundingManager =
    //     FM_BC_Bancor_Redeeming_VirtualSupply_v1(
    //         address(__Module_orchestrator.fundingManager())
    //     );
    //     IERC20 collateralToken = fundingManager.token();
    //     IERC20Issuance_v1 issuanceToken =
    //         IERC20Issuance_v1(fundingManager.getIssuanceToken());

    //     // Transfer collateral reserve into adapter
    //     fundingManager.transferOrchestratorToken(
    //         address(dexAdapter),
    //         collateralToken.balanceOf(address(fundingManager))
    //     );

    //     // Mint initial liquidity to dex adapter
    //     issuanceToken.mint(
    //         address(dexAdapter),
    //         fundingManager.getVirtualIssuanceSupply()
    //             - initialVirtualIssuanceSupply
    //     );

    //     // Call migration on adapter
    //     dexAdapter.createLiquidity(
    //         address(collateralToken), address(issuanceToken), address(this)
    //     );
    // }
}
