// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

//Internal Dependencies
import {
    E2ETest,
    IOrchestratorFactory_v1,
    IOrchestrator_v1
} from "test/e2e/E2ETest.sol";

import {ERC20IssuanceMock} from "test/utils/mocks/ERC20IssuanceMock.sol";

//SuT
import {
    FM_BC_Bancor_Redeeming_VirtualSupply_v1,
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1
} from
    "test/modules/fundingManager/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.t.sol";

contract BondingCurveFundingManagerE2E is E2ETest {
    // Module Configurations for the current E2E test. Should be filled during setUp() call.
    IOrchestratorFactory_v1.ModuleConfig[] moduleConfigurations;

    ERC20IssuanceMock issuanceToken;

    address alice = address(0xA11CE);
    address bob = address(0x606);

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
        setUpBancorVirtualSupplyBondingCurveFundingManager();

        issuanceToken = new ERC20IssuanceMock();
        issuanceToken.init("Bonding Curve Token", "BCT", 18, type(uint).max);

        //BancorFormula 'formula' is instantiated in the E2EModuleRegistry

        IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties memory
            bc_properties = IFM_BC_Bancor_Redeeming_VirtualSupply_v1
                .BondingCurveProperties({
                formula: address(formula),
                reserveRatioForBuying: 200_000,
                reserveRatioForSelling: 200_000,
                buyFee: 0,
                sellFee: 0,
                buyIsOpen: true,
                sellIsOpen: true,
                initialIssuanceSupply: 100,
                initialCollateralSupply: 100
            });

        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                bancorVirtualSupplyBondingCurveFundingManagerMetadata,
                abi.encode(address(issuanceToken), bc_properties, token),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );

        // Authorizer
        setUpRoleAuthorizer();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                roleAuthorizerMetadata,
                abi.encode(address(this), address(this)),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );

        // PaymentProcessor
        setUpSimplePaymentProcessor();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                simplePaymentProcessorMetadata,
                bytes(""),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );

        // Additional Logic Modules
        setUpBountyManager();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                bountyManagerMetadata,
                bytes(""),
                abi.encode(true, EMPTY_DEPENDENCY_LIST)
            )
        );
    }

    function test_e2e_OrchestratorFundManagement() public {
        // address(this) creates a new orchestrator.
        IOrchestratorFactory_v1.OrchestratorConfig memory orchestratorConfig =
        IOrchestratorFactory_v1.OrchestratorConfig({
            owner: address(this),
            token: token
        });

        IOrchestrator_v1 orchestrator =
            _create_E2E_Orchestrator(orchestratorConfig, moduleConfigurations);

        FM_BC_Bancor_Redeeming_VirtualSupply_v1 fundingManager =
        FM_BC_Bancor_Redeeming_VirtualSupply_v1(
            address(orchestrator.fundingManager())
        );

        // We allow the FundingManager to mint tokens
        issuanceToken.setMinter(address(fundingManager));

        // IMPORTANT
        // =========
        // Due to how the underlying rebase mechanism works, it is necessary
        // to always have some amount of tokens in the fundingmanager.
        // It's best, if the owner deposits them right after deployment.
        //uint initialDeposit = 10e18;
        //token.mint(address(this), initialDeposit);
        //token.approve(address(fundingManager), initialDeposit);
        //fundingManager.deposit(initialDeposit);

        // Mint some tokens to alice and bob in order to fund the fundingmanager.
        token.mint(alice, 1000e18);
        token.mint(bob, 5000e18);
        uint buf_minAmountOut = fundingManager.calculatePurchaseReturn(1000e18); //buffer variable to store the minimum amount out on calls to the buy and sell functions

        // Alice funds the fundingmanager with 1k tokens.
        vm.startPrank(alice);
        {
            // Approve tokens to orchestrator.
            token.approve(address(fundingManager), 1000e18);

            // Deposit tokens, i.e. fund the fundingmanager.
            fundingManager.buy(1000e18, buf_minAmountOut);

            // After the deposit, alice received some amount of receipt tokens
            // from the fundingmanager.
            assertTrue(issuanceToken.balanceOf(alice) > 0);
        }
        vm.stopPrank();
        buf_minAmountOut = fundingManager.calculatePurchaseReturn(5000e18);

        // Bob funds the fundingmanager with 5k tokens.
        vm.startPrank(bob);
        {
            // Approve tokens to fundingmanager.
            token.approve(address(fundingManager), 5000e18);

            // Deposit tokens, i.e. fund the fundingmanager.
            fundingManager.buy(5000e18, buf_minAmountOut);

            // After the deposit, bob received some amount of receipt tokens
            // from the fundingmanager.
            assertTrue(issuanceToken.balanceOf(bob) > 0);
        }
        vm.stopPrank();

        // If the orchestrator spends half of the deposited tokens in the fundingmanager, i.e. for a milestone,
        // alice and bob are still able to withdraw their respective leftover
        // of the tokens.
        // Note that we simulate orchestrator spending by just burning tokens.
        uint halfOfDeposit = token.balanceOf(address(fundingManager)) / 2;
        fundingManager.setVirtualCollateralSupply(halfOfDeposit);

        buf_minAmountOut =
            fundingManager.calculateSaleReturn(issuanceToken.balanceOf(bob));

        // Bob is also able to withdraw half of his funded tokens.
        vm.startPrank(bob);
        {
            // Approve tokens to fundingmanager.
            issuanceToken.approve(
                address(fundingManager), issuanceToken.balanceOf(bob)
            );

            fundingManager.sell(issuanceToken.balanceOf(bob), buf_minAmountOut);
            assertApproxEqRel(token.balanceOf(bob), 2500e18, 0.00001e18); //ensures that the imprecision introduced by the math stays below 0.001%
        }
        vm.stopPrank();

        // Alice is now able to withdraw half her funded tokens.
        buf_minAmountOut =
            fundingManager.calculateSaleReturn(issuanceToken.balanceOf(alice));

        vm.startPrank(alice);
        {
            // Approve tokens to fundingmanager.
            issuanceToken.approve(
                address(fundingManager), issuanceToken.balanceOf(alice)
            );

            fundingManager.sell(
                issuanceToken.balanceOf(alice), buf_minAmountOut
            );
            assertApproxEqRel(token.balanceOf(alice), 500e18, 0.00001e18); //ensures that the imprecision introduced by the math stays below 0.001%
        }
        vm.stopPrank();

        // After redeeming all their fundingmanager function tokens, the tokens got
        // burned.
        // Half of the deposited funds (the ones we set to "ignore" by modifying the virtual supply) are still in the manager
        assertEq(issuanceToken.balanceOf(alice), 0);
        assertEq(issuanceToken.balanceOf(bob), 0);
        assertApproxEqRel(
            token.balanceOf(address(fundingManager)), halfOfDeposit, 0.00001e18
        );
    }
}
