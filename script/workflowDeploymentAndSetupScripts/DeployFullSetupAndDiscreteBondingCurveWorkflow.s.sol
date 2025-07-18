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

/*
--------------------------------------------------------------------------------------
General Guidelines:
- This script is meant to be used to deploy a full setup of a workflow with Discrete Bonding Curve
- It is based on the base DeploymentScript so it deploys all factories, as well as the feeManager, Governor and Transaction Forwarder
- All contract addresses can be looked up in the console output
- In addition to the base deployment, it deploys a Collateral Token, an Issuance Token and the Discrete Bonding Curve Workflow
- For the usage of the Discrete Bonding Curve Funding Manager, you wanna take a look at:
    - the E2E test FM_BC_Discrete_Redeeming_VirtualSupply_v1_E2E in test/e2e/fundingManager/FM_BC_Discrete_Redeeming_VirtualSupply_v1_E2E.t.sol
    - This describes the basic functionalities of the Funding Manager itself

----------
deployer (with the deployerPrivateKey)
- This is the address that is used to deploy the contracts
- This is set in the .env file (see usage of this script section)

----------
communityMultisig
- This would normally be the multisig that is used to access the governor contracts
- Because this script is based on the TesnetDeploymentScript it is set to be the deployer address

----------
treasury
- This is the address that is used to collect the protocol fees
- Because this script is based on the TesnetDeploymentScript it is set to be the deployer address
- Disclaimer: Because the Protocol fees might directly be send to the treasury (deployer)
              it might cause some confusion for later tracking of collaterl Token in general

----------
Governor
- This contract contains most of the protocol level functionalities
    - in our usecase it is used to set the protocol fees
- Normally all of the functions would be only accessible by the communityMultisig
    - The deployer should be able to access all of the functions because they are set as the communityMultisig address
- To adapt the fees use the following functions
        - setFeeManagerDefaultProtocolTreasury
            - This sets the protocol fees to be sent to the treasury address
        - setFeeManagerDefaultCollateralFee
            - This sets the default collateral fee
        - setFeeManagerDefaultIssuanceFee
            - This sets the default issuance fee
----------
Collateral Token
- This contract is a mock up so any address can just be used to call the mint and burn functions
- It can be found in the test/mocks/external/token/ERC20Mock.sol file

----------
Issuance Token
- Initialization:
    - This contract has an initial owner
        - This script sets the owner to be the deployer address, which can be adapted in the script itself
        - There is a outcommented alternative to set the owner via the env variable ISSUANCE_TOKEN_OWNER_ADDRESS
---------
Discrete Bonding Curve Workflow
- Initialization:
    - The workflow has a workflowAdmin
        - This script sets the workflowAdmin to be the deployer address, which can be adapted in the script itself
        - There is a outcommented alternative to set the workflowAdmin via the env variable WORKFLOW_ADMIN_ADDRESS

---------
Discrete Bonding Curve Funding Manager
- Initialization:
    - It initializes with the prewritten Curve (see_createDiscreteBondingCurveSegments() function)
        - Should this curve not fit the usecase it can either
            - be adapted in the script itself, so that it launches with the different curve
            - or be adapted via the reconfigureSegments function of the Funding Manager 
                - Disclaimer: I only tested this in the E2E test for a single usecase, so this might not work in all cases
    - It sets the issuanceToken to be the Issuance Token address and the collateralToken to be the Collateral Token address
    - The protocol buy and sell fee functionality is not used until the updateProtocolFeeCache() function is called
        - Essentially the protocol buy and sell fee are 0 until the updateProtocolFeeCache() function is called
        - Disclaimer: Everytime the protocol fees are updated, this function needs to be called as well
    - Project collateral buy and sell fees are set to 1% at the start of deployment
    - Buy and sell are not open until the openBuy and openSell functions are called

- Functionalities:
    - buy and sell
        - The caller needs to approve the collateralToken to be used to buy the issuanceToken
        - The calculation uses the Segments of the discrete bonding curve
        - Fees can be taken from the project as well as the protocol side
            - These fees are taken cumulatively and not additive
            - meaning if the protocol fee is 1% and the project fee is 2%
                - First the protocol fee is taken of 2% of the total amount
                - From the rest the project fee of 1% is taken 
                - With this the project fee is not 1% of the total amount
    - setting project buy and sell fees
        - The project buy and sell fees are set to 1% at the start of deployment
        - They can be set via the setBuyFee and setSellFee functions respectively
        - This needs to be called by the workflowAdmin
    - setting virtual collateral supply
        - This value represents the amount of tokens that can actually be used as collateral for the issuance token
        - It should be used to inject collateral liquidity into the contract
        - Remember: Only adding liquidity is not enough to change the form of the curve
          and is therefor useless if not paired with the reconfigureSegments functionality
        - The virtual collateral supply can be set via the setVirtualCollateralSupply function
        - Disclaimer: The function doesnt care about the current virtual collateral supply.
            - If called remember to add the current virtual collateral supply to the value you want to inject
            - If used incorrectly it might lead to locking the collateral tokens in the contract
              so that they cant be traded with issuance token
            - I would recommend to only use this to raise the virtual collateral supply to the
              same level as the actually available collateral liquidity
        - This needs to be called by the workflowAdmin
    - reconfigureSegments
        - This function is used to reconfigure the segments of the discrete bonding curve
        - It can be used to change the price, supply, or number of steps of the segments
        - This function reverts if the value of the old configuration is not equal to the new configuration
        - The function can only be called by the workflowAdmin
        - There are two use cases for this function
            1. Reconfigure Curve without injecting new collateral
            2. Reconfigure Curve with injecting new collateral

          - Usecase 1 Example: 
            - Old Curve:
                - Floor is 100 tokens with a price of 1 dollar
                - Steps are 50 tokens long with a price increase of 1 dollar
                - Current Issuance Supply is 125 tokens
                - The total value of the issuance token is 100*1Dollar + 25*2Dollar = 150 Dollar
            - New Curve has to have the same value of the old curve
                - New Curve Example:
                    - Floor is 100 tokens with a price of 1.1 dollar
                    - Steps are 50 tokens long with a price increase of 0.6 dollar
                    - Current Issuance Supply stays the same at 125 tokens
                    - The total value of the issuance token stays the same at 150 Dollar
                        - 100*1.1Dollar + 25*0.6Dollar = 150 Dollar
          - Usecase 2 Example:
            - Old Curve:
                - Floor is 100 tokens with a price of 1 dollar
                - Steps are 50 tokens long with a price increase of 1 dollar
                - Current Issuance Supply is 125 tokens
                - The total value of the issuance token is 100*1Dollar + 25*2Dollar = 150 Dollar
            - We want to inject 100 tokens of collateral into the contract
                - For this we would need to use the setVirtualCollateralSupply function (see above)
            - The new collateral value would be 250 Dollars
            - the supply would still be 125 tokens
            - The new Curve would need to fulfill both of these conditions
            - New Curve Example:
                - Floor is 100 tokens with a price of 1.75 dollar
                - Steps are 50 tokens long with a price increase of 1.25 dollar
                - Current Issuance Supply is 125 tokens
                - The total value of the issuance token is
                    - 100*1.75Dollar = 175 Dollar
                    - 25*3 Dollar = 75 Dollar
                - coming to 250 Dollars
            
--------
Usage of the script:
- The script is meant to be used in the context of a testnet deployment
- For it to be used a .env file needs to be created and filled out accordingly
    - For this the dev.env file can be used as a template
    - Adapt the env variables to be filled out
        - realisticly only the deployer private key is needed
    - Disclaimer: As written above (see communityMultisig) some env variables are overwritten in the script itself and are therefore not needed in the env file


To run this script use the following command:
forge script script/workflowDeploymentAndSetupScripts/DeployFullSetupAndDiscreteBondingCurveWorkflow.s.sol:DeployFullSetupAndDiscreteBondingCurveWorkflow


*/

contract DeployFullSetupAndDiscreteBondingCurveWorkflow is
    TestnetDeploymentScript
{
    function run() public override {
        console2.log("\n===============================================");
        console2.log(
            "  DEPLOYING FULL SETUP AND DISCRETE BONDING CURVE WORKFLOW"
        );
        console2.log("   DISCLAIMER: This is a test deployment");
        console2.log("   !!! DO NOT USE THIS IN PRODUCTION !!!");
        console2.log("  ================================\n");

        // Fetch workflowAdmin
        console2.log("Fetching workflow admin address");
        address workflowAdmin = deployer;
        //Alternatively use vm.envAddress("WORKFLOW_ADMIN_ADDRESS");
        require(workflowAdmin != address(0), "Workflow admin not set");

        // Fetch issuanceTokenOwner
        console2.log("Fetching issuance token owner address");
        address issuanceTokenOwner = deployer;
        //Alternatively use vm.envAddress("ISSUANCE_TOKEN_OWNER_ADDRESS");
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
