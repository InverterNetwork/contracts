// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// SuT
import {RoleAuthorizer} from "src/modules/authorizer/RoleAuthorizer.sol";

//Internal Dependencies
import {
    E2ETest, IOrchestratorFactory, IOrchestrator
} from "test/e2e/E2ETest.sol";

import {RebasingFundingManager} from
    "src/modules/fundingManager/RebasingFundingManager.sol";

import {
    BountyManager,
    IBountyManager
} from "src/modules/logicModule/BountyManager.sol";
import {
    TransactionForwarder_v1,
    ITransactionForwarder_v1,
    ERC2771Forwarder
} from "src/external/forwarder/TransactionForwarder_v1.sol";

contract MetaTxAndMulticallE2E is E2ETest {
    // Module Configurations for the current E2E test. Should be filled during setUp() call.
    IOrchestratorFactory.ModuleConfig[] moduleConfigurations;

    function setUp() public override {
        // Setup common E2E framework
        super.setUp();

        // Set Up individual Modules the E2E test is going to use and store their configurations:
        // NOTE: It's important to store the module configurations in order, since _create_E2E_Orchestrator() will copy from the array.
        // The order should be:
        //      moduleConfigurations[0]  => FundingManager
        //      moduleConfigurations[1]  => Authorizer
        //      moduleConfigurations[2]  => PaymentProcessor
        //      moduleConfigurations[3:] => Additional Logic Modules

        // FundingManager
        setUpRebasingFundingManager();
        moduleConfigurations.push(
            IOrchestratorFactory.ModuleConfig(
                rebasingFundingManagerMetadata,
                abi.encode(address(token)),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );

        // Authorizer
        setUpTokenGatedRoleAuthorizer();
        moduleConfigurations.push(
            IOrchestratorFactory.ModuleConfig(
                tokenRoleAuthorizerMetadata,
                abi.encode(address(this), address(this)),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );

        // PaymentProcessor
        setUpSimplePaymentProcessor();
        moduleConfigurations.push(
            IOrchestratorFactory.ModuleConfig(
                simplePaymentProcessorMetadata,
                bytes(""),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );

        // Additional Logic Modules
        setUpBountyManager();
        moduleConfigurations.push(
            IOrchestratorFactory.ModuleConfig(
                bountyManagerMetadata,
                bytes(""),
                abi.encode(true, EMPTY_DEPENDENCY_LIST)
            )
        );
    }

    function test_e2e_SendMetaTransaction() public {
        //--------------------------------------------------------------------------------
        // Orchestrator Initialization
        //--------------------------------------------------------------------------------

        IOrchestratorFactory.OrchestratorConfig memory orchestratorConfig =
        IOrchestratorFactory.OrchestratorConfig({
            owner: address(this),
            token: token
        });

        IOrchestrator orchestrator =
            _create_E2E_Orchestrator(orchestratorConfig, moduleConfigurations);

        //--------------------------------------------------------------------------------
        // Module E2E Test
        //--------------------------------------------------------------------------------

        //-----------------------------------------------------
        // Create signer

        uint signerPrivateKey = 0xa11ce;
        address signer = vm.addr(signerPrivateKey);

        //-----------------------------------------------------
        // Call Function without role
        //In this example we're gonna call the rebasing fundingmanagers deposit function

        //Lets get the fundingmanager address
        address fundingManager = address(orchestrator.fundingManager());

        //lets define how much he wants to deposit
        uint depositAmount = 1000;
        //For this to work the signer would have to have that amount of tokens
        token.mint(signer, depositAmount);
        //and the token transferal approved before
        vm.prank(signer);
        token.approve(fundingManager, depositAmount);

        //We create a simplyfied ForwardRequest without the signature
        ERC2771Forwarder.ForwardRequestData memory req = ERC2771Forwarder
            .ForwardRequestData({
            from: signer,
            to: fundingManager,
            value: 0,
            //This should be approximately be the gas value of the called function in this case the deposit function
            gas: 1_000_000,
            //This is the timestamp after which the request is not executable anymore.
            deadline: uint48(block.timestamp + 1 weeks),
            data: abi.encodeWithSignature("deposit(uint256)", depositAmount),
            //This has to be empty until we create the signature
            signature: bytes("")
        });

        //Create the digest needed to create the signature
        bytes32 digest = forwarder.createDigest(req);

        //Create Signature with digest (This has to be handled by the frontend)
        vm.prank(signer);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        req.signature = signature;

        //Do call
        forwarder.execute(req);

        //Check if successful
        assertEq(
            RebasingFundingManager(fundingManager).token().balanceOf(
                fundingManager
            ),
            depositAmount
        );

        //-----------------------------------------------------
        //Call Function with role
        //In this example we're gonna call the bountyManagers createBounty Function
        //The function needs a role to access it

        //Lets get the bountyManager address
        BountyManager bountyManager;

        address[] memory modulesList = orchestrator.listModules();
        for (uint i; i < modulesList.length; ++i) {
            try IBountyManager(modulesList[i]).isExistingBountyId(0) returns (
                bool
            ) {
                bountyManager = BountyManager(modulesList[i]);
                break;
            } catch {
                continue;
            }
        }
        //Give the signer address the according role
        bountyManager.grantModuleRole(
            bountyManager.BOUNTY_ISSUER_ROLE(), signer
        );

        //Then we need to create the ForwardRequest
        req = ERC2771Forwarder.ForwardRequestData({
            from: signer,
            to: address(bountyManager),
            value: 0,
            //This should be approximately be the gas value of the called function in this case the addBounty function
            gas: 1_000_000,
            deadline: uint48(block.timestamp + 1 weeks),
            data: abi.encodeWithSignature(
                "addBounty(uint256,uint256,bytes)",
                100e18, //minimumPayoutAmount
                500e18, //maximumPayoutAmount
                bytes("This is a test bounty") //details
            ),
            //This has to be empty until we create the signature
            signature: bytes("")
        });

        //Create the digest needed to create the signature
        digest = forwarder.createDigest(req);

        //Create Signature with digest (This has to be handled by the frontend)
        vm.prank(signer);
        (v, r, s) = vm.sign(signerPrivateKey, digest);
        signature = abi.encodePacked(r, s, v);

        req.signature = signature;

        //Do call
        forwarder.execute(req);

        //Check if successful
        assertTrue(bountyManager.isExistingBountyId(1));
    }

    function test_e2e_SendMulticall() public {
        //--------------------------------------------------------------------------------
        // Orchestrator Initialization
        //--------------------------------------------------------------------------------

        IOrchestratorFactory.OrchestratorConfig memory orchestratorConfig =
        IOrchestratorFactory.OrchestratorConfig({
            owner: address(this),
            token: token
        });

        IOrchestrator orchestrator =
            _create_E2E_Orchestrator(orchestratorConfig, moduleConfigurations);

        //lets use this example user
        address user = address(0xBEEF);

        // for the multicall to work we need to collect all the individual calls we want to make
        // For this we use an array of Singlecall Structs from the Transaction Forwarder
        ITransactionForwarder_v1.SingleCall[] memory callCollection =
            new ITransactionForwarder_v1.SingleCall[](2);

        //-----------------------------------------------------
        // Call Function without role
        //In this example we're gonna call the rebasing fundingmanagers deposit function

        //Lets get the fundingmanager address
        address fundingManager = address(orchestrator.fundingManager());

        //lets define how much he wants to deposit
        uint depositAmount = 1000;
        //For this to work the signer would have to have that amount of tokens
        token.mint(user, depositAmount);
        //and the token transferal approved before
        vm.prank(user);
        token.approve(fundingManager, depositAmount);

        //We create a call struct containing the call we want to make
        ITransactionForwarder_v1.SingleCall memory call1 =
        ITransactionForwarder_v1.SingleCall({
            //target of the call should be the fundingmanager
            target: fundingManager,
            //We dont allow the call to fail. In some circumstances this might be useful though
            allowFailure: false,
            //The encoded data of the call we want to make
            callData: abi.encodeWithSignature("deposit(uint256)", depositAmount)
        });

        //Put the call into our call collection
        callCollection[0] = call1;

        //-----------------------------------------------------
        //Call Function with role
        //In this example we're gonna call the bountyManagers createBounty Function
        //The function needs a role to access it

        //Lets get the bountyManager address
        BountyManager bountyManager;

        address[] memory modulesList = orchestrator.listModules();
        for (uint i; i < modulesList.length; ++i) {
            try IBountyManager(modulesList[i]).isExistingBountyId(0) returns (
                bool
            ) {
                bountyManager = BountyManager(modulesList[i]);
                break;
            } catch {
                continue;
            }
        }

        //Give the signer address the according role
        bountyManager.grantModuleRole(bountyManager.BOUNTY_ISSUER_ROLE(), user);

        //We create a call struct containing the call we want to make
        ITransactionForwarder_v1.SingleCall memory call2 =
        ITransactionForwarder_v1.SingleCall({
            //target of the call should be the fundingmanager
            target: address(bountyManager),
            //We dont allow the call to fail. In some circumstances this might be useful though
            allowFailure: false,
            //The encoded data of the call we want to make
            callData: abi.encodeWithSignature(
                "addBounty(uint256,uint256,bytes)",
                100e18, //minimumPayoutAmount
                500e18, //maximumPayoutAmount
                bytes("This is a test bounty") //details
            )
        });

        //Put the call into our call collection
        callCollection[1] = call2;

        //Do the multiCall
        //!!! the user has to make the call
        vm.prank(user);
        forwarder.executeMulticall(callCollection);

        //Check if successful
        //For the fundingmanager
        assertEq(
            RebasingFundingManager(fundingManager).token().balanceOf(
                fundingManager
            ),
            depositAmount
        );
        //For the bountyManager
        assertTrue(bountyManager.isExistingBountyId(1));
    }
}
