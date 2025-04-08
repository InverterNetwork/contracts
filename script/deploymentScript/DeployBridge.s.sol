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
import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

import {TestnetDeploymentScript} from "./TestnetDeploymentScript.s.sol";

contract DeployBridge is TestnetDeploymentScript {
    // Governor_v1 InverterBeaconProxy_v1
    IGovernor_v1 public governorProxy;

    address private fundingManager;

    IModule_v1.Metadata public bancorIssuanceTokenBridgeMetadata = IModule_v1
        .Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "LM_FM_IssuanceTokenBridge_v1"
    );

    function run() public override {
        super.run();

        governorProxy = IGovernor_v1(governor);

        if (address(governorProxy) == address(0)) {
            revert("Governor not deployed");
        }

        registerModule();
        deployPIM();
    }

    function registerModule() internal {
        address impl_mod_LM_FM_IssuanceTokenBridge_v1 = deployAndLogWithCreate2(
            "LM_FM_IssuanceTokenBridge_v1",
            vm.getCode(
                "LM_FM_IssuenceTokenBridge_v1.sol:LM_FM_IssuanceTokenBridge_v1"
            )
        );

        IInverterBeacon_v1 beacon = IInverterBeacon_v1(
            proxyAndBeaconDeployer.deployInverterBeacon(
                bancorIssuanceTokenBridgeMetadata.title,
                inverterReverter,
                governor,
                impl_mod_LM_FM_IssuanceTokenBridge_v1,
                bancorIssuanceTokenBridgeMetadata.majorVersion,
                bancorIssuanceTokenBridgeMetadata.minorVersion,
                bancorIssuanceTokenBridgeMetadata.patchVersion
            )
        );

        // Register the module in the Governor
        vm.startBroadcast(deployerPrivateKey);
        {
            governorProxy.registerMetadataInModuleFactory(
                bancorIssuanceTokenBridgeMetadata, beacon
            );
        }
        vm.stopBroadcast();
    }

    function deployPIM() internal {
        uint initialIssuuanceSupply = 100_999_999_999_999_998_676;
        uint initialCollateralSupply = 100_498_798_599;
        uint32 reserveRatio = 1000;

        IERC20Issuance_v1 issuanceToken;
        IOrchestrator_v1 orchestrator;
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig;
        IOrchestratorFactory_v1.ModuleConfig memory fundingManagerConfig;
        IOrchestratorFactory_v1.ModuleConfig memory authorizerConfig;
        IOrchestratorFactory_v1.ModuleConfig memory paymentProcessorConfig;
        IOrchestratorFactory_v1.ModuleConfig[] memory additionalModuleConfig;
        IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties memory
            bcProperties;

        vm.startBroadcast(deployerPrivateKey);
        {
            issuanceToken = new ERC20Issuance_v1(
                "Inverter Token", "INVT", 18, 100_000_000 ether, deployer
            );

            mockCollateralToken.mint(deployer, 10_000_000 ether);
        }
        vm.stopBroadcast();

        // Bonding Curve Properties
        bcProperties = IFM_BC_Bancor_Redeeming_VirtualSupply_v1
            .BondingCurveProperties({
            formula: impl_lib_BancorFormula,
            reserveRatioForBuying: reserveRatio,
            reserveRatioForSelling: reserveRatio,
            buyFee: 100,
            sellFee: 100,
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
            bancorRedeemingVirtualSupplyFundingManagerMetadata,
            abi.encode(
                address(issuanceToken),
                bcProperties,
                address(mockCollateralToken)
            )
        );

        // Payment Processor: only Metadata
        paymentProcessorConfig = IOrchestratorFactory_v1.ModuleConfig(
            simplePaymentProcessorMetadata, bytes("")
        );

        // Authorizer: Metadata, initial authorized addresses
        authorizerConfig = IOrchestratorFactory_v1.ModuleConfig(
            roleAuthorizerMetadata, abi.encode(deployer)
        );

        // Add logic module to bridge tokens
        additionalModuleConfig = new IOrchestratorFactory_v1.ModuleConfig[](1);
        additionalModuleConfig[0] = IOrchestratorFactory_v1.ModuleConfig(
            bancorIssuanceTokenBridgeMetadata,
            abi.encode(address(issuanceToken))
        );

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

        console2.log("Funding Manager: ", fundingManager);
        console2.log("Token Issuance: ", address(issuanceToken));
        console2.log("Orchestrator Token: ", address(mockCollateralToken));
        console2.log("Orchestrator Address: ", address(orchestrator));
    }
}

// forge script script/deploymentScript/DeployBridge.s.sol --rpc-url mainnet --broadcast

// forge script script/deploymentScript/DeployReceiver.s.sol --rpc-url http://localhost:8546 --broadcast

// forge script script/deploymentScript/TokenBridgeSettings.s.sol --rpc-url mainnet --broadcast

// forge script script/deploymentScript/Buy.s.sol --rpc-url mainnet --broadcast
