// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "forge-std/Script.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {IGovernor_v1} from "@ex/governance/interfaces/IGovernor_v1.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IInverterBeacon_v1} from "src/proxies/interfaces/IInverterBeacon_v1.sol";
import {IERC20Issuance_v1} from "@ex/token/IERC20Issuance_v1.sol";
import {IFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {NativeIssuance_v1} from "@ex/token/NativeIssuance_v1.sol";
import {TestnetDeploymentScript} from "./TestnetDeploymentScript.s.sol";

// Import the contracts so they will be added to the built artifacts
import {InverterReverter_v1} from "@ex/reverter/InverterReverter_v1.sol";
import {BancorFormula} from "@fm/bondingCurve/formulas/BancorFormula.sol";
import {AUT_Roles_v1} from "@aut/role/AUT_Roles_v1.sol";
import {AUT_TokenGated_Roles_v1} from "@aut/role/AUT_TokenGated_Roles_v1.sol";
import {AUT_EXT_VotingRoles_v1} from
    "@aut/extensions/AUT_EXT_VotingRoles_v1.sol";
import {FM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.sol";
import {FM_DepositVault_v1} from "@fm/depositVault/FM_DepositVault_v1.sol";
import {LM_PC_Bounties_v1} from "@lm/LM_PC_Bounties_v1.sol";
import {LM_PC_KPIRewarder_v1} from "@lm/LM_PC_KPIRewarder_v1.sol";
import {LM_PC_PaymentRouter_v1} from "@lm/LM_PC_PaymentRouter_v1.sol";
import {LM_PC_RecurringPayments_v1} from "@lm/LM_PC_RecurringPayments_v1.sol";
import {PP_Simple_v1} from "@pp/PP_Simple_v1.sol";
import {PP_Streaming_v1} from "@pp/PP_Streaming_v1.sol";

contract DeployPIML1 is TestnetDeploymentScript {
    address public erc20TokenRemote;
    address public nativeTokenHome;

    // Governor_v1 InverterBeaconProxy_v1
    IGovernor_v1 public governorProxy;

    address private fundingManager;

    // BancorRedeemingVirtualSupplyNativeFundingManager
    IModule_v1.Metadata public
        bancorRedeemingVirtualSupplyNativeFundingManagerMetadata = IModule_v1
            .Metadata(
            1,
            0,
            0,
            "https://github.com/InverterNetwork/contracts",
            "FM_BC_Bancor_Redeeming_VirtualSupply_Native_v1"
        );

    function run(address _nativeTokenHome, address _erc20TokenRemote) public {
        if (_nativeTokenHome == address(0)) {
            revert("NATIVE_TOKEN_HOME not set");
        }

        if (_erc20TokenRemote == address(0)) {
            revert("ERC20_TOKEN_REMOTE not set");
        }

        nativeTokenHome = _nativeTokenHome;
        erc20TokenRemote = _erc20TokenRemote;

        super.run();

        governorProxy = IGovernor_v1(governor);

        if (address(governorProxy) == address(0)) {
            revert("Governor not deployed");
        }

        registerModule();
        deployPIMNative();
    }

    function registerModule() internal {
        address impl_mod_FM_BC_Bancor_Redeeming_VirtualSupply_Native_v1 =
        deployAndLogWithCreate2(
            "FM_BC_Bancor_Redeeming_VirtualSupply_Native_v1",
            vm.getCode(
                "FM_BC_Bancor_Redeeming_VirtualSupply_Native_v1.sol:FM_BC_Bancor_Redeeming_VirtualSupply_Native_v1"
            )
        );

        IInverterBeacon_v1 beacon = IInverterBeacon_v1(
            proxyAndBeaconDeployer.deployInverterBeacon(
                bancorRedeemingVirtualSupplyNativeFundingManagerMetadata.title,
                inverterReverter,
                governor,
                impl_mod_FM_BC_Bancor_Redeeming_VirtualSupply_Native_v1,
                bancorRedeemingVirtualSupplyNativeFundingManagerMetadata
                    .majorVersion,
                bancorRedeemingVirtualSupplyNativeFundingManagerMetadata
                    .minorVersion,
                bancorRedeemingVirtualSupplyNativeFundingManagerMetadata
                    .patchVersion
            )
        );

        // Register the module in the Governor
        vm.startBroadcast(deployerPrivateKey);
        {
            governorProxy.registerMetadataInModuleFactory(
                bancorRedeemingVirtualSupplyNativeFundingManagerMetadata, beacon
            );
        }
        vm.stopBroadcast();
    }

    function deployPIMNative() internal {
        uint initialIssuuanceSupply = 122_727_272_727_272_727_272_727;
        uint initialCollateralSupply = 3_163_408_614_166_851_161;
        uint32 reserveRatio = 160_000;

        IERC20Issuance_v1 issuanceToken;
        IOrchestrator_v1 orchestrator;
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig;
        IOrchestratorFactory_v1.ModuleConfig memory fundingManagerConfig;
        IOrchestratorFactory_v1.ModuleConfig memory authorizerConfig;
        IOrchestratorFactory_v1.ModuleConfig memory paymentProcessorConfig;
        IOrchestratorFactory_v1.ModuleConfig[] memory additionalModuleConfig;
        IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties memory
            bcProperties;

        // Deploy Native Issuance Token
        vm.startBroadcast(deployerPrivateKey);
        {
            issuanceToken = new NativeIssuance_v1(deployer);
        }
        vm.stopBroadcast();

        // Bonding Curve Properties
        bcProperties = IFM_BC_Bancor_Redeeming_VirtualSupply_v1
            .BondingCurveProperties({
            formula: impl_lib_BancorFormula,
            reserveRatioForBuying: reserveRatio,
            reserveRatioForSelling: reserveRatio,
            buyFee: 0,
            sellFee: 0,
            buyIsOpen: true,
            sellIsOpen: true,
            initialIssuanceSupply: initialIssuuanceSupply,
            initialCollateralSupply: initialCollateralSupply
        });

        // Orchestrator_v1 config
        workflowConfig = IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        // Funding Manager: Metadata, token address
        fundingManagerConfig = IOrchestratorFactory_v1.ModuleConfig(
            bancorRedeemingVirtualSupplyNativeFundingManagerMetadata,
            abi.encode(address(issuanceToken), bcProperties, erc20TokenRemote)
        );

        // Payment Processor: only Metadata
        paymentProcessorConfig = IOrchestratorFactory_v1.ModuleConfig(
            simplePaymentProcessorMetadata, bytes("")
        );

        // Authorizer: Metadata, initial authorized addresses
        authorizerConfig = IOrchestratorFactory_v1.ModuleConfig(
            roleAuthorizerMetadata, abi.encode(deployer)
        );

        // Add the configuration for all the non-mandatory modules. In this case nothing added.
        additionalModuleConfig = new IOrchestratorFactory_v1.ModuleConfig[](0);

        // ------------------------------------------------------------------------
        // Orchestrator_v1 Creation

        vm.startBroadcast(deployerPrivateKey);
        {
            orchestrator = IOrchestratorFactory_v1(orchestratorFactory)
                .createOrchestrator(
                workflowConfig,
                fundingManagerConfig,
                authorizerConfig,
                paymentProcessorConfig,
                additionalModuleConfig
            );
        }
        vm.stopBroadcast();

        // Get the Funding Manager
        fundingManager = address(orchestrator.fundingManager());

        // Set the minter role to the Funding Manager
        vm.startBroadcast(deployerPrivateKey);
        {
            issuanceToken.setMinter(fundingManager, true);
        }
        vm.stopBroadcast();

        console2.log("Native Funding Manager: ", fundingManager);
        console2.log("Native Token Issuence: ", address(issuanceToken));
        console2.log("Orchestrator Token: ", address(erc20TokenRemote));
        console2.log("Orchestrator Address: ", address(orchestrator));

        vm.setEnv("NATIVE_TOKEN_ISSUANCE", vm.toString(address(issuanceToken)));
    }
}
