// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {TestnetDeploymentScript} from
    "script/deploymentScript/TestnetDeploymentScript.s.sol";

import {console2} from "forge-std/console2.sol";

import {DeterministicFactory_v1} from "@df/DeterministicFactory_v1.sol";

import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";

import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";

import "src/modules/fundingManager/bondingCurve/types/PackedSegment_v1.sol";

import {DiscreteCurveMathLibV1_Exposed} from
    "@mocks/modules/fundingManager/bondingCurve/DiscreteCurveMathLibV1_Exposed.sol";

import {ERC20Mock} from "@mocks/external/token/ERC20Mock.sol";
import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";

contract DeployFullSetupAndDiscreteBondingCurveWorkflow is
    TestnetDeploymentScript
{
    function run() public override {
        console2.log("\n===============================================");
        console2.log(
            "  DEPLOYING FULL SETUP AND DISCRETE BONDING CURVE WORKFLOW"
        );
        console2.log("   DISCLAIMER: This is a test deployment");
        console2.log("           !!! DO NOT USE THIS IN PRODUCTION !!!");
        console2.log("  ================================\n");

        // Fetch workflowAdmin
        console2.log("Fetching workflow admin address");
        address workflowAdmin = vm.envAddress("WORKFLOW_ADMIN_ADDRESS");
        require(workflowAdmin != address(0), "Workflow admin not set");

        // Fetch issuanceTokenOwner
        console2.log("Fetching issuance token owner address");
        address issuanceTokenOwner =
            vm.envAddress("ISSUANCE_TOKEN_OWNER_ADDRESS");
        require(
            issuanceTokenOwner != address(0), "Issuance token owner not set"
        );

        // Deploy all contracts
        super.run();

        // Deploy Collateral Token

        address collateralToken = _deployCollateralToken();

        // Deploy Issuance Token

        address issuanceToken = _deployIssuanceToken();

        // Create Workflow Config
        console2.log("Creating orchestrator config");

        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
        IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        // Create Funding Manager Config
        IOrchestratorFactory_v1.ModuleConfig memory fundingManagerConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            bondingCurveDiscreteRedeemingVirtualSupplyMetadata,
            abi.encode(
                issuanceToken,
                collateralToken,
                _createDiscreteBondingCurveSegments()
            )
        );

        // Create Authorizer Config
        IOrchestratorFactory_v1.ModuleConfig memory authorizerConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            roleAuthorizerMetadata, abi.encode(workflowAdmin)
        );

        // Create Payment Processor Config
        IOrchestratorFactory_v1.ModuleConfig memory paymentProcessorConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            simplePaymentProcessorMetadata, bytes("")
        );

        IOrchestratorFactory_v1.ModuleConfig[] memory moduleConfigs =
            new IOrchestratorFactory_v1.ModuleConfig[](0);

        // Deploy Workflow
        console2.log("Deploying orchestrator");
        vm.startBroadcast(deployerPrivateKey);
        address orchestrator = address(
            IOrchestratorFactory_v1(orchestratorFactory).createOrchestrator(
                workflowConfig,
                fundingManagerConfig,
                authorizerConfig,
                paymentProcessorConfig,
                moduleConfigs
            )
        );
        vm.stopBroadcast();
        console2.log("Orchestrator: %s", orchestrator);

        // Get Funding Manager Address
        address fundingManager =
            address(IOrchestrator_v1(orchestrator).fundingManager());
        console2.log("Funding Manager: %s", fundingManager);

        // Set Minter and Transfer Ownership of Issuance Token
        address[] memory minters = new address[](1);
        minters[0] = fundingManager;

        _setMinterAndTransderOwnership(
            issuanceToken, minters, issuanceTokenOwner
        );
    }

    function _deployCollateralToken() internal returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        address collateralToken =
            address(new ERC20Mock("Inverter USD", "iUSD", 18));
        vm.stopBroadcast();
        console2.log(
            "Deploying Collateral Token at address: %s", collateralToken
        );
        return collateralToken;
    }

    function _deployIssuanceToken() internal returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        address issuanceToken = address(
            new ERC20Issuance_v1("Inverter USD", "iUSD", 18, type(uint).max)
        );
        vm.stopBroadcast();
        console2.log("Deploying Issuance Token at address: %s", issuanceToken);
        return issuanceToken;
    }

    function _createDiscreteBondingCurveSegments()
        internal
        returns (PackedSegment[] memory)
    {
        console2.log("Creating discrete bonding curve segments");

        DiscreteCurveMathLibV1_Exposed exposedLib =
            new DiscreteCurveMathLibV1_Exposed();

        // Floor Values
        uint floorPrice = 1e6; //1 Dollar
        uint floorSupply = 1_000_000 ether; // 1 Million Floor Tokens

        // Curve Values
        uint initialPrice = 1.4e6; //1.4 Dollar
        uint priceIncrease = 0.4e6; //0.4 Dollar
        uint supplyPerStep = 40_000 ether; //40.000 Floor Tokens
        uint numberOfSteps = type(uint16).max; //65535 Steps (max value)

        // --- Initialize flatSlopedCurve ---
        PackedSegment[] memory flatSlopedCurve = new PackedSegment[](2);

        // Floor Segment
        flatSlopedCurve[0] = exposedLib.exposed_createSegment(
            floorPrice, //initialPriceOfSegment
            0, //priceIncreasePerStep (We have only one step)
            floorSupply, //supplyPerStep
            1 //numberOfSteps (1 equals one vertical element)
        );

        // Discrete Curve Segment
        flatSlopedCurve[1] = exposedLib.exposed_createSegment(
            initialPrice, //initialPriceOfSegment
            priceIncrease, //priceIncreasePerStep
            supplyPerStep, //supplyPerStep
            numberOfSteps //numberOfSteps
        );

        return flatSlopedCurve;
    }

    function _setMinterAndTransderOwnership(
        address token_,
        address[] memory minters_,
        address newOwner_
    ) internal {
        console2.log("Setting minters and transferring ownership");
        vm.startBroadcast(deployerPrivateKey);
        for (uint i; i < minters_.length; i++) {
            ERC20Issuance_v1(token_).setMinter(minters_[i], true);
        }
        ERC20Issuance_v1(token_).transferOwnership(newOwner_);
        vm.stopBroadcast();
    }
}
