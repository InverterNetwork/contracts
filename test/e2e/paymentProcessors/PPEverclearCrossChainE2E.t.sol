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

// Modules to be tested and their dependencies
import {PP_Everclear_CrossChain_v1} from
    "src/modules/paymentProcessor/PP_Everclear_CrossChain_v1.sol";
import {Mock_LM_PC_PaymentRouter_Everclear_v1} from
    "test/utils/mocks/Mock_LM_PC_PaymentRouter_Everclear_v1.sol";
import {IEverclear} from
    "src/modules/paymentProcessor/interfaces/IEverclear.sol";
import {IERC20PaymentClientBase_v2} from
    "src/modules/logicModule/interfaces/IERC20PaymentClientBase_v2.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

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
            // Check for a more specific interface if available, or rely on name for mocks
            // The 'name' field in our local Metadata struct corresponds to 'title' in IModule_v1
            string memory currentModuleTitle =
                IModule_v1(modulesList[i]).title();
            if (
                // Cast to the specific interface that should have supportsInterface
                // or to a generic IERC165 if available.
                // Mock_LM_PC_PaymentRouter_Everclear_v1 inherits supportsInterface.
                keccak256(abi.encodePacked(currentModuleTitle))
                    == keccak256(
                        abi.encodePacked(
                            mockLmPcPaymentRouterEverclearMetadata.title
                        )
                    )
                    && Mock_LM_PC_PaymentRouter_Everclear_v1(
                        payable(modulesList[i])
                    ).supportsInterface(
                        type(IERC20PaymentClientBase_v2).interfaceId
                    )
            ) {
                paymentClient =
                    Mock_LM_PC_PaymentRouter_Everclear_v1(modulesList[i]);
                vm.label(
                    address(paymentClient),
                    "Mock_LM_PC_PaymentRouter_Everclear_v1_Instance"
                );
                break;
            }
        }
        require(
            address(paymentClient) != address(0),
            "PaymentClient not found in orchestrator"
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
        bytes32 PAYMENT_PUSHER_ROLE = keccak256("PAYMENT_PUSHER_ROLE");
        paymentClient.grantModuleRole(PAYMENT_PUSHER_ROLE, owner);

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
    function test_e2e_EverclearCrossChain_FullLifecycle() public {
        // Test logic will be implemented later
        if (skipTestsWithFailingRpc) {
            console.log(
                "Skipping test_e2e_EverclearCrossChain_FullLifecycle due to RPC/forking issues."
            );
            return;
        }
        // TODO: Implement test
    }
}
