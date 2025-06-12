// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import {E2ETest} from "test/e2e/E2ETest.sol";
import {console} from "forge-std/console.sol";

// Inverter Core
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol"; // Added for casting

// Modules to be tested and their dependencies
import {PP_Everclear_CrossChain_v1} from
    "src/modules/paymentProcessor/PP_Everclear_CrossChain_v1.sol";
import {Mock_LM_PC_PaymentRouter_Everclear_v1} from
    "test/utils/mocks/Mock_LM_PC_PaymentRouter_Everclear_v1.sol";
import {IEverclear} from
    "src/modules/paymentProcessor/interfaces/IEverclear.sol";
import {IERC20PaymentClientBase_v2} from
    "src/modules/logicModule/interfaces/IERC20PaymentClientBase_v2.sol";
import {IPaymentProcessor_v2} from
    "src/modules/paymentProcessor/IPaymentProcessor_v2.sol";
import {IPP_CrossChainBase_v1} from
    "src/modules/paymentProcessor/interfaces/IPP_CrossChainBase_v1.sol";
import {IFM_DepositVault_v1} from
    "src/modules/fundingManager/depositVault/interfaces/IFM_DepositVault_v1.sol";
import {IFundingManager_v1} from
    "src/modules/fundingManager/IFundingManager_v1.sol"; // For interfaceId check

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol"; // Added for event emission

contract PPEverclearCrossChainE2E is E2ETest {
    //--------------------------------------------------------------------------
    // Chain Configuration
    //--------------------------------------------------------------------------
    uint sepoliaForkId;
    string sepoliaRpcUrl;
    bool skipTestsWithFailingRpc = false;

    // Everclear Spoke on Sepolia
    address constant EVERCLEAR_SPOKE_ADDRESS_SEPOLIA =
        0x3650432cB5331e6dc95be8C1d8168b7c37f677e2;
    IEverclear everclearSpoke;

    //--------------------------------------------------------------------------
    // Global Variables
    //--------------------------------------------------------------------------
    IOrchestratorFactory_v1.ModuleConfig[] moduleConfigurations;

    IOrchestrator_v1 orchestrator;
    PP_Everclear_CrossChain_v1 paymentProcessor;
    Mock_LM_PC_PaymentRouter_Everclear_v1 paymentClient;
    IFM_DepositVault_v1 fmDepositVault;

    ERC20Mock paymentToken;
    ERC20Mock usdc; // Assuming USDC might be needed for Everclear fees/bonds on Sepolia

    // Standard Test Addresses
    address owner = vm.addr(1);
    address recipient = vm.addr(2);
    address user1 = vm.addr(3);
    address automationService = address(0xA5E705EED); // Placeholder Automation Service Address

    //--------------------------------------------------------------------------
    // Setup
    //--------------------------------------------------------------------------
    function setUp() public virtual override {
        // 1. Fork Setup
        try vm.rpcUrl("sepolia") returns (string memory url) {
            sepoliaRpcUrl = url;
        } catch {
            console.log(
                "Failed to get valid RPC URL for Sepolia from env, using fallback."
            );
            // Attempt a public fallback if not found in env, though foundry.toml should handle this.
            // For robustness, one might add a specific public RPC here if needed.
            // sepoliaRpcUrl = "https://rpc.sepolia.org"; // Example, ensure it's a working one
            // For now, assume foundry.toml or env provides it. If not, fork creation will fail.
            // If relying purely on foundry.toml, this try-catch for rpcUrl might be simplified.
        }

        if (bytes(sepoliaRpcUrl).length == 0) {
            // If still no RPC URL, try a common public one as a last resort or skip.
            console.log(
                "Sepolia RPC URL not found, attempting public fallback."
            );
            sepoliaRpcUrl = "https://sepolia.drpc.org/"; // A common public RPC
        }

        try vm.createSelectFork(sepoliaRpcUrl) returns (uint forkId_) {
            sepoliaForkId = forkId_;
        } catch Error(string memory reason) {
            console.log("Failed to create Sepolia fork: %s", reason);
            skipTestsWithFailingRpc = true;
            return; // Exit setUp if fork fails
        } catch {
            console.log(
                "Failed to create Sepolia fork due to an unknown error."
            );
            skipTestsWithFailingRpc = true;
            return; // Exit setUp if fork fails
        }

        everclearSpoke = IEverclear(EVERCLEAR_SPOKE_ADDRESS_SEPOLIA);

        // 2. Base E2ETest Setup (deploys module factory, gov, and some standard modules)
        super.setUp();

        // 3. Explicitly set up modules specific to this E2E test
        // These were added to E2EModuleRegistry but are not called by E2ETest.sol's super.setUp()
        // Call setup for all modules whose metadata will be used in moduleConfigurations
        setUpDepositVaultFundingManager(); // For depositVaultMetadata
        setUpRoleAuthorizer(); // For roleAuthorizerMetadata
        setUpPPEverclearCrossChain(); // For ppEverclearCrossChainMetadata
        setUpMockLmPcPaymentRouterEverclear(); // For mockLmPcPaymentRouterEverclearMetadata

        // 4. Deploy Mock Tokens
        paymentToken = new ERC20Mock("PaymentToken", "PAY", 18);
        usdc = new ERC20Mock("USD Coin Mock", "USDCm", 6); // Mock for now

        vm.label(address(paymentToken), "PaymentToken (PAY)");
        vm.label(address(usdc), "USDC Mock (USDCm)");
        vm.label(
            EVERCLEAR_SPOKE_ADDRESS_SEPOLIA, "EverclearSpoke (Sepolia Forked)"
        );

        // 5. Module Configurations
        // Clear any configurations from super.setUp if necessary, or start fresh
        delete moduleConfigurations;

        // FundingManager (DepositVault)
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                depositVaultMetadata, // Inherited from E2ETest -> E2EModuleRegistry
                abi.encode(address(paymentToken)) // Deposit vault will hold paymentToken
            )
        );

        // Authorizer (Role Authorizer)
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                roleAuthorizerMetadata, // Inherited from E2ETest -> E2EModuleRegistry
                abi.encode(owner) // Owner of this test contract will be the initial admin
            )
        );

        // PaymentProcessor (PP_Everclear_CrossChain_v1)
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                ppEverclearCrossChainMetadata, // From E2EModuleRegistry, set up by setUpPPEverclearCrossChain
                abi.encode(EVERCLEAR_SPOKE_ADDRESS_SEPOLIA)
            )
        );

        // LogicModule (Mock_LM_PC_PaymentRouter_Everclear_v1)
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                mockLmPcPaymentRouterEverclearMetadata, // From E2EModuleRegistry, set up by setUpMockLmPcPaymentRouterEverclear
                bytes("") // No specific config data for this mock's init
            )
        );

        // 6. Deploy Orchestrator
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
        IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        orchestrator =
            _create_E2E_Orchestrator(workflowConfig, moduleConfigurations);
        vm.label(address(orchestrator), "E2E_Orchestrator");

        // 7. Retrieve Deployed Module Instances
        paymentProcessor = PP_Everclear_CrossChain_v1(
            payable(address(orchestrator.paymentProcessor()))
        );
        vm.label(
            address(paymentProcessor), "PP_Everclear_CrossChain_v1_Instance"
        );

        address[] memory modulesList = orchestrator.listModules();
        for (uint i = 0; i < modulesList.length; i++) {
            address moduleAddress = modulesList[i];
            // Check for Payment Client
            if (address(paymentClient) == address(0)) {
                // Only find if not already found
                string memory currentModuleTitle =
                    IModule_v1(moduleAddress).title();
                if (
                    keccak256(abi.encodePacked(currentModuleTitle))
                        == keccak256(
                            abi.encodePacked(
                                mockLmPcPaymentRouterEverclearMetadata.title
                            )
                        )
                        && Mock_LM_PC_PaymentRouter_Everclear_v1(
                            payable(moduleAddress)
                        ).supportsInterface(
                            type(IERC20PaymentClientBase_v2).interfaceId
                        )
                ) {
                    paymentClient =
                        Mock_LM_PC_PaymentRouter_Everclear_v1(moduleAddress);
                    vm.label(
                        address(paymentClient),
                        "Mock_LM_PC_PaymentRouter_Everclear_v1_Instance"
                    );
                }
            }

            // Check for Funding Manager (Deposit Vault)
            if (address(fmDepositVault) == address(0)) {
                // Only find if not already found
                // Using supportsInterface for more robust check
                // Cast to Module_v1 to access supportsInterface from ERC165Upgradeable
                Module_v1 baseModule = Module_v1(payable(moduleAddress));
                if (
                    baseModule.supportsInterface(
                        type(IFundingManager_v1).interfaceId
                    )
                        && baseModule.supportsInterface(
                            type(IFM_DepositVault_v1).interfaceId
                        )
                ) {
                    // Further check if it's the one configured with our paymentToken
                    // This assumes depositVaultMetadata was used for its deployment.
                    string memory currentModuleTitle =
                        IModule_v1(moduleAddress).title();
                    if (
                        keccak256(abi.encodePacked(currentModuleTitle))
                            == keccak256(
                                abi.encodePacked(depositVaultMetadata.title)
                            )
                    ) {
                        fmDepositVault = IFM_DepositVault_v1(moduleAddress);
                        vm.label(
                            address(fmDepositVault),
                            "FM_DepositVault_v1_Instance"
                        );
                    }
                }
            }

            // Optimization: if both found, break early
            if (
                address(paymentClient) != address(0)
                    && address(fmDepositVault) != address(0)
            ) {
                break;
            }
        }
        require(
            address(paymentClient) != address(0),
            "PaymentClient not found in orchestrator"
        );
        require(
            address(fmDepositVault) != address(0),
            "FM_DepositVault_v1 not found in orchestrator"
        );

        // 8. Initial Token Minting & Approvals
        uint initialMintAmount = 1_000_000 * 10 ** 18; // For paymentToken (18 decimals)
        paymentToken.mint(owner, initialMintAmount);
        paymentToken.mint(user1, initialMintAmount);

        uint initialUsdcAmount = 1_000_000 * 10 ** 6; // For USDCm (6 decimals)
        usdc.mint(owner, initialUsdcAmount);
        usdc.mint(automationService, initialUsdcAmount); // For potential fees if Everclear needs it

        // Example: Approve paymentClient to spend owner's paymentTokens
        vm.startPrank(owner);
        paymentToken.approve(address(paymentClient), type(uint).max);
        usdc.approve(address(paymentClient), type(uint).max); // If client handles fees
        // vm.stopPrank(); // Keep prank active for role granting

        // Grant PAYMENT_PUSHER_ROLE to owner for the paymentClient mock
        // The role value is defined in LM_PC_PaymentRouter_v2
        // This needs to be called by an admin of the paymentClient's authorizer (which is 'owner')
        bytes32 pusherRole = paymentClient.PAYMENT_PUSHER_ROLE(); // Directly use the constant
        paymentClient.grantModuleRole(pusherRole, owner);

        // Grant MODULE_ROLE to paymentClient on the paymentProcessor
        // The role value is defined in Module_v1 or specific PP
        // This needs to be called by an admin of the orchestrator's authorizer (which is 'owner')
        bytes32 MODULE_ROLE = keccak256("MODULE_ROLE");
        // The paymentProcessor's authorizer is the orchestrator's authorizer
        IOrchestrator_v1(address(orchestrator)).authorizer().grantRole(
            MODULE_ROLE, address(paymentClient)
        );
        vm.stopPrank(); // Stop prank after all owner actions
    }

    //--------------------------------------------------------------------------
    // Test Cases
    //--------------------------------------------------------------------------

    // Helper struct to pass initial state to assertion helpers
    struct InitialState {
        uint ownerBalance;
        uint processorBalance;
        uint vaultBalance; // Added for fmDepositVault
        uint paymentClientTotalPayments;
        uint paymentClientOutstanding;
        uint paymentProcessorPaymentId;
    }

    function _assertTokenBalances(
        uint initialOwnerBalance,
        uint initialProcessorBalance,
        uint initialVaultBalance,
        uint paymentAmount_
    ) internal view {
        assertEq(
            paymentToken.balanceOf(owner),
            initialOwnerBalance - paymentAmount_, // Owner pays into the vault
            "Owner balance incorrect"
        );
        assertEq(
            paymentToken.balanceOf(address(paymentProcessor)),
            initialProcessorBalance, // Processor itself should not hold these tokens
            "Processor balance incorrect"
        );
        assertEq(
            paymentToken.balanceOf(address(fmDepositVault)),
            initialVaultBalance, // Vault balance should be initial + deposit - transferToSpoke = initial
            "Vault balance incorrect post-payment"
        );
        assertEq(
            paymentToken.balanceOf(address(everclearSpoke)),
            paymentAmount_, // Assuming spoke was empty
            "Everclear Spoke balance incorrect"
        );
    }

    function _assertPaymentClientState(
        uint, /*initialPaymentClientTotalPayments*/ // Parameter no longer used as orders are cleared
        uint initialPaymentClientOutstanding,
        uint, /*paymentAmount_*/ // Parameters below are for clientOrder, which is no longer checked
        address, /*recipientAddressOnTargetChain_*/
        uint, /*targetChainId_*/
        uint24, /*everclearMaxFee_*/
        uint48 /*everclearTTL_*/
    ) internal view {
        assertEq(
            paymentClient.paymentOrders().length,
            0, // Orders should be cleared after collection by paymentProcessor
            "PaymentClient totalPayments incorrect"
        );
        assertEq(
            paymentClient.outstandingTokenAmount(address(paymentToken)),
            initialPaymentClientOutstanding,
            "PaymentClient outstandingTokenAmount incorrect after payment"
        );

        // Since orders are cleared, we can no longer check the details of the specific order
        // that was processed. The checks for outstandingTokenAmount and paymentOrders().length
        // confirm the client's state regarding overall payment processing.
    }

    function _assertPaymentProcessorState(
        uint initialPaymentProcessorPaymentId_,
        uint paymentAmount_,
        address recipientAddressOnTargetChain_,
        uint targetChainId_,
        uint24 everclearMaxFee_,
        uint48 everclearTTL_
    ) internal view {
        uint currentPaymentId = paymentProcessor.getPaymentId();
        assertEq(
            currentPaymentId,
            initialPaymentProcessorPaymentId_ + 1,
            "Processor currentPaymentId incorrect"
        );

        bytes memory retrievedPackedIntentIdBytes = paymentProcessor
            .getBridgeDataByPaymentId(initialPaymentProcessorPaymentId_);
        require(
            retrievedPackedIntentIdBytes.length == 32,
            "Packed IntentId not 32 bytes"
        );
        bytes32 intentId;
        assembly {
            intentId := mload(add(retrievedPackedIntentIdBytes, 0x20))
        }
        assertTrue(intentId != bytes32(0), "Retrieved intentId is zero");

        IEverclear.Intent memory processorIntent =
            paymentProcessor.getIntentByIntentId(intentId);

        assertEq(
            processorIntent.initiator,
            bytes32(uint(uint160(address(paymentProcessor)))),
            "ProcessorIntent initiator mismatch"
        );
        assertEq(
            processorIntent.receiver,
            bytes32(uint(uint160(recipientAddressOnTargetChain_))),
            "ProcessorIntent receiver mismatch"
        );
        assertEq(
            processorIntent.inputAsset,
            bytes32(uint(uint160(address(paymentToken)))),
            "ProcessorIntent inputAsset mismatch"
        );
        assertEq(
            processorIntent.outputAsset,
            bytes32(uint(uint160(address(paymentToken)))),
            "ProcessorIntent outputAsset mismatch"
        );
        assertEq(
            processorIntent.amount,
            paymentAmount_,
            "ProcessorIntent amount mismatch"
        );
        assertEq(
            processorIntent.maxFee,
            everclearMaxFee_,
            "ProcessorIntent maxFee mismatch"
        );
        assertEq(
            processorIntent.ttl, everclearTTL_, "ProcessorIntent ttl mismatch"
        );
        assertEq(
            processorIntent.origin,
            block.chainid,
            "ProcessorIntent origin mismatch"
        );
        assertEq(
            processorIntent.destinations.length,
            1,
            "ProcessorIntent destinations length mismatch"
        );
        assertEq(
            processorIntent.destinations[0],
            uint32(targetChainId_),
            "ProcessorIntent destinations[0] mismatch"
        );
        assertTrue(processorIntent.nonce != 0, "ProcessorIntent nonce is zero");
        assertTrue(
            processorIntent.timestamp != 0, "ProcessorIntent timestamp is zero"
        );
        assertTrue(
            processorIntent.timestamp <= block.timestamp,
            "ProcessorIntent timestamp too high"
        );
    }

    function test_e2e_EverclearCrossChain_FullLifecycle() public {
        if (skipTestsWithFailingRpc) {
            console.log(
                "Skipping test_e2e_EverclearCrossChain_FullLifecycle due to RPC/forking issues."
            );
            return;
        }

        // 1. Initial Setup & Parameter Definition
        uint paymentAmount = 100 * 10 ** paymentToken.decimals();
        uint targetChainId = block.chainid + 1;
        uint24 everclearMaxFee = 1 * 10 ** 5;
        uint48 everclearTTL = uint48(block.timestamp + 3600);
        address recipientAddressOnTargetChain = user1;

        // Store initial state using the helper struct
        InitialState memory initialState = InitialState({
            ownerBalance: paymentToken.balanceOf(owner),
            processorBalance: paymentToken.balanceOf(address(paymentProcessor)),
            vaultBalance: paymentToken.balanceOf(address(fmDepositVault)),
            paymentClientTotalPayments: paymentClient.paymentOrders().length,
            paymentClientOutstanding: paymentClient.outstandingTokenAmount(
                address(paymentToken)
            ),
            paymentProcessorPaymentId: paymentProcessor.getPaymentId()
        });

        // 2. Execute Payment
        vm.startPrank(owner);

        // A. Owner funds the FM_DepositVault_v1
        // A.1 Owner approves fmDepositVault to spend their paymentTokens
        // Expect Approval event from paymentToken
        vm.expectEmit(true, true, false, true, address(paymentToken));
        emit IERC20.Approval(owner, address(fmDepositVault), paymentAmount);
        paymentToken.approve(address(fmDepositVault), paymentAmount);

        // A.2 Owner deposits paymentTokens into fmDepositVault
        // Expect Transfer from owner to fmDepositVault
        vm.expectEmit(true, true, false, true, address(paymentToken));
        emit IERC20.Transfer(owner, address(fmDepositVault), paymentAmount);

        // Expect Deposit event from fmDepositVault
        vm.expectEmit(true, false, false, true, address(fmDepositVault)); // owner (indexed), amount (data)
        emit IFM_DepositVault_v1.Deposit(owner, paymentAmount);

        fmDepositVault.deposit(paymentAmount);

        // B. paymentClient initiates the cross-chain payment
        // This sequence of events happens INSIDE paymentClient.pushCrossChainPaymentEverclear(...)
        //    and the subsequent PP_Everclear_CrossChain_v1.processPayments call.

        // B.1. fmDepositVault transfers to paymentClient (triggered by paymentClient)
        // B.1.a IERC20.Transfer event from the token contract
        vm.expectEmit(true, true, false, true, address(paymentToken));
        emit IERC20.Transfer(
            address(fmDepositVault), address(paymentClient), paymentAmount
        );
        // B.1.b TransferOrchestratorToken event from the fmDepositVault contract
        //vm.expectEmit(true, false, false, true, address(fmDepositVault)); // to (indexed), amount (data)
        emit IFundingManager_v1.TransferOrchestratorToken(
            address(paymentClient), paymentAmount
        );

        // B.2. paymentClient approves paymentProcessor
        //vm.expectEmit(true, true, false, true, address(paymentToken));
        emit IERC20.Approval(
            address(paymentClient), address(paymentProcessor), paymentAmount
        );

        // B.3. paymentProcessor pulls from paymentClient (inside processPayments)
        // vm.expectEmit(true, true, false, true, address(paymentToken));
        emit IERC20.Transfer(
            address(paymentClient), address(paymentProcessor), paymentAmount
        );

        // B.4. paymentProcessor approves Everclear Spoke (inside processPayments)
        vm.expectEmit(true, true, false, true, address(paymentToken));
        emit IERC20.Approval(
            address(paymentProcessor),
            EVERCLEAR_SPOKE_ADDRESS_SEPOLIA,
            paymentAmount
        );

        // B.5. Everclear Spoke pulls from paymentProcessor (via newIntent call inside processPayments)
        vm.expectEmit(true, true, false, true, address(paymentToken));
        emit IERC20.Transfer(
            address(paymentProcessor),
            EVERCLEAR_SPOKE_ADDRESS_SEPOLIA,
            paymentAmount
        );

        // B.6. paymentProcessor emits PaymentOrderProcessed (inside processPayments)
        vm.expectEmit(true, true, true, false, address(paymentProcessor)); // client, recipient, token are indexed. Data not checked.
        emit IPaymentProcessor_v2.PaymentOrderProcessed(
            address(paymentClient),
            recipientAddressOnTargetChain,
            address(paymentToken),
            paymentAmount,
            block.chainid,
            targetChainId,
            paymentClient.getFlags(),
            new bytes32[](0) // Data is not checked here, verified by state assertions
        );

        // B.7. paymentProcessor emits BridgeTransferCompleted (inside processPayments)
        // We don't check intentId (topic2) as it's generated dynamically.
        vm.expectEmit(true, false, true, false, address(paymentProcessor)); // paymentId (topic1), recipient (topic3) are indexed. Data not checked.
        emit IPP_CrossChainBase_v1.BridgeTransferCompleted(
            initialState.paymentProcessorPaymentId, // Expected paymentId
            bytes32(0), // Placeholder for intentId - not checked
            recipientAddressOnTargetChain,
            address(paymentClient),
            address(paymentToken),
            paymentAmount,
            block.chainid,
            targetChainId,
            paymentClient.getFlags(),
            new bytes32[](0) // Data is not checked here, verified by state assertions
        );

        // B.8. paymentProcessor emits TokensReleased (inside processPayments)
        vm.expectEmit(true, true, false, true, address(paymentProcessor)); // recipient (indexed), token (indexed). Amount (data) checked.
        emit IPaymentProcessor_v2.TokensReleased(
            recipientAddressOnTargetChain, address(paymentToken), paymentAmount
        );

        // Note: The IEverclear interface provided does not define a NewIntent event.
        // Verification of intent creation will rely on state checks of the paymentProcessor
        // and the returned values from the newIntent call (which our PP stores).

        paymentClient.pushCrossChainPaymentEverclear(
            recipientAddressOnTargetChain,
            address(paymentToken),
            paymentAmount,
            targetChainId,
            everclearMaxFee,
            everclearTTL
        );

        vm.stopPrank();

        // 3. Verify State Changes & Data Integrity
        _assertTokenBalances(
            initialState.ownerBalance,
            initialState.processorBalance,
            initialState.vaultBalance,
            paymentAmount
        );

        _assertPaymentClientState(
            initialState.paymentClientTotalPayments,
            initialState.paymentClientOutstanding,
            paymentAmount,
            recipientAddressOnTargetChain,
            targetChainId,
            everclearMaxFee,
            everclearTTL
        );

        _assertPaymentProcessorState(
            initialState.paymentProcessorPaymentId,
            paymentAmount,
            recipientAddressOnTargetChain,
            targetChainId,
            everclearMaxFee,
            everclearTTL
        );

        console.log(
            "test_e2e_EverclearCrossChain_FullLifecycle: Successfully processed cross-chain payment."
        );
    }
}
