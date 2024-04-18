// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Dependencies
import {Orchestrator_v1} from "src/orchestrator/Orchestrator_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";

// Internal Interfaces
import {
    IOrchestrator_v1,
    IAuthorizer,
    IPaymentProcessor
} from "src/orchestrator/interfaces/IOrchestrator_v1.sol";

import {TransactionForwarder_v1} from
    "src/external/forwarder/TransactionForwarder_v1.sol";

// Mocks
import {
    FundingManagerMock,
    IFundingManager_v1
} from "test/utils/mocks/modules/FundingManagerMock.sol";
import {AuthorizerMock} from "test/utils/mocks/modules/AuthorizerMock.sol";
import {PaymentProcessorMock} from
    "test/utils/mocks/modules/PaymentProcessorMock.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// Helper
import {TypeSanityHelper} from "test/orchestrator/helper/TypeSanityHelper.sol";

contract OrchestratorV1Test is Test {
    // SuT
    Orchestrator_v1 orchestrator;

    // Helper
    TypeSanityHelper types;

    // Mocks
    FundingManagerMock fundingManager;
    AuthorizerMock authorizer;
    PaymentProcessorMock paymentProcessor;
    ERC20Mock token;
    TransactionForwarder_v1 forwarder;

    event AuthorizerUpdated(address indexed _address);
    event FundingManagerUpdated(address indexed _address);
    event PaymentProcessorUpdated(address indexed _address);
    event OrchestratorInitialized(
        uint indexed orchestratorId_,
        address fundingManager,
        address authorizer,
        address paymentProcessor,
        address[] modules
    );

    function setUp() public {
        fundingManager = new FundingManagerMock();
        authorizer = new AuthorizerMock();
        paymentProcessor = new PaymentProcessorMock();
        forwarder = new TransactionForwarder_v1("TransactionForwarder_v1");
        token = new ERC20Mock("TestToken", "TST");

        address impl = address(new Orchestrator_v1(address(forwarder)));
        orchestrator = Orchestrator_v1(Clones.clone(impl));

        types = new TypeSanityHelper(address(orchestrator));
    }

    //--------------------------------------------------------------------------
    // Tests: Initialization

    function testInit(uint orchestratorId, address[] memory modules) public {
        types.assumeValidOrchestratorId(orchestratorId);
        types.assumeValidModules(modules);

        address[] memory truncatedModules = new address[](125);
        if (modules.length > 125) {
            for (uint i; i < 125; i++) {
                truncatedModules[i] = modules[i];
            }
            types.assumeValidModules(truncatedModules);

            // Make sure mock addresses are not in set of modules.
            assumeMockAreNotInSet(truncatedModules);

            vm.expectEmit(true, true, true, false);
            emit OrchestratorInitialized(
                orchestratorId,
                address(fundingManager),
                address(authorizer),
                address(paymentProcessor),
                truncatedModules
            );

            // Initialize orchestrator.
            orchestrator.init(
                orchestratorId,
                truncatedModules,
                fundingManager,
                authorizer,
                paymentProcessor
            );
        } else {
            // Make sure mock addresses are not in set of modules.
            assumeMockAreNotInSet(modules);

            vm.expectEmit(true, true, true, false);
            emit OrchestratorInitialized(
                orchestratorId,
                address(fundingManager),
                address(authorizer),
                address(paymentProcessor),
                truncatedModules
            );

            // Initialize orchestrator.
            orchestrator.init(
                orchestratorId,
                modules,
                fundingManager,
                authorizer,
                paymentProcessor
            );
        }

        // Check that orchestrator's storage correctly initialized.
        assertEq(orchestrator.orchestratorId(), orchestratorId);
        assertEq(address(orchestrator.authorizer()), address(authorizer));
        assertEq(
            address(orchestrator.paymentProcessor()), address(paymentProcessor)
        );
        assertTrue(orchestrator.isTrustedForwarder(address(forwarder)));
    }

    function testReinitFails(uint orchestratorId, address[] memory modules)
        public
    {
        types.assumeValidOrchestratorId(orchestratorId);

        address[] memory truncatedModules = new address[](125);
        if (modules.length > 125) {
            for (uint i; i < 125; i++) {
                truncatedModules[i] = modules[i];
            }

            types.assumeValidModules(truncatedModules);
            // Make sure mock addresses are not in set of modules.
            assumeMockAreNotInSet(truncatedModules);

            // Initialize orchestrator.
            orchestrator.init(
                orchestratorId,
                truncatedModules,
                fundingManager,
                authorizer,
                paymentProcessor
            );

            vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
            orchestrator.init(
                orchestratorId,
                truncatedModules,
                fundingManager,
                authorizer,
                paymentProcessor
            );
        } else {
            types.assumeValidModules(modules);
            // Make sure mock addresses are not in set of modules.
            assumeMockAreNotInSet(modules);

            // Initialize orchestrator.
            orchestrator.init(
                orchestratorId,
                modules,
                fundingManager,
                authorizer,
                paymentProcessor
            );

            vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
            orchestrator.init(
                orchestratorId,
                modules,
                fundingManager,
                authorizer,
                paymentProcessor
            );
        }
    }

    //--------------------------------------------------------------------------
    // Tests: Replacing the three base modules: authorizer, funding manager,
    //        payment processor

    function testSetAuthorizer(uint orchestratorId, address[] memory modules)
        public
    {
        // limit to 100, otherwise we could run into the max module limit
        modules = cutArray(100, modules);

        types.assumeValidOrchestratorId(orchestratorId);
        types.assumeValidModules(modules);

        // Make sure mock addresses are not in set of modules.
        assumeMockAreNotInSet(modules);

        // Initialize orchestrator.
        orchestrator.init(
            orchestratorId,
            modules,
            fundingManager,
            authorizer,
            paymentProcessor
        );

        authorizer.setIsAuthorized(address(this), true);

        // Create new authorizer module
        AuthorizerMock newAuthorizer = new AuthorizerMock();
        vm.assume(newAuthorizer != authorizer);
        types.assumeElemNotInSet(modules, address(newAuthorizer));

        newAuthorizer.mockInit(abi.encode(address(0xA11CE)));

        // set the new authorizer module
        vm.expectEmit(true, true, true, true);
        emit AuthorizerUpdated(address(newAuthorizer));

        orchestrator.setAuthorizer(newAuthorizer);
        assertTrue(orchestrator.authorizer() == newAuthorizer);

        // verify whether the init value is set and not the value from the old
        // authorizer, to check whether the replacement is successful
        bytes32 ownerRole = orchestrator.authorizer().getOwnerRole();
        assertFalse(orchestrator.authorizer().hasRole(ownerRole, address(this)));
        assertTrue(
            orchestrator.authorizer().hasRole(ownerRole, address(0xA11CE))
        );
    }

    function testSetAuthorizerFailsIfWrongModuleType(
        uint orchestratorId,
        address[] memory modules
    ) public {
        // limit to 100, otherwise we could run into the max module limit
        modules = cutArray(100, modules);

        types.assumeValidOrchestratorId(orchestratorId);
        types.assumeValidModules(modules);

        // Make sure mock addresses are not in set of modules.
        assumeMockAreNotInSet(modules);

        // Initialize orchestrator.
        orchestrator.init(
            orchestratorId,
            modules,
            fundingManager,
            authorizer,
            paymentProcessor
        );

        authorizer.setIsAuthorized(address(this), true);

        // Create new authorizer module
        address newAuthorizer = address(0x8888);
        vm.assume(newAuthorizer != address(authorizer));
        types.assumeElemNotInSet(modules, address(newAuthorizer));

        // set the new payment processor module. First the verification function reverts, then the setter.
        vm.expectRevert();
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrchestrator_v1.Orchestrator_v1__InvalidModuleType.selector,
                newAuthorizer
            )
        );

        orchestrator.setAuthorizer(IAuthorizer(newAuthorizer));
        assertTrue(orchestrator.authorizer() == authorizer);
    }

    function testSetFundingManager(
        uint orchestratorId,
        address[] memory modules
    ) public {
        // limit to 100, otherwise we could run into the max module limit
        modules = cutArray(100, modules);

        types.assumeValidOrchestratorId(orchestratorId);
        types.assumeValidModules(modules);

        // Make sure mock addresses are not in set of modules.
        assumeMockAreNotInSet(modules);

        // Initialize orchestrator.
        orchestrator.init(
            orchestratorId,
            modules,
            fundingManager,
            authorizer,
            paymentProcessor
        );

        authorizer.setIsAuthorized(address(this), true);
        FundingManagerMock(address(orchestrator.fundingManager())).setToken(
            IERC20(address(0xA11CE))
        );

        // Create new funding manager module
        FundingManagerMock newFundingManager = new FundingManagerMock();
        vm.assume(newFundingManager != fundingManager);
        types.assumeElemNotInSet(modules, address(newFundingManager));

        // set the new funding manager module
        vm.expectEmit(true, true, true, true);
        emit FundingManagerUpdated(address(newFundingManager));

        orchestrator.setFundingManager(newFundingManager);
        assertTrue(orchestrator.fundingManager() == newFundingManager);
        assertTrue(
            address((orchestrator.fundingManager()).token()) == address(0)
        );
    }

    function testSetFundingManagerFailsIfWrongModuleType(
        uint orchestratorId,
        address[] memory modules
    ) public {
        // limit to 100, otherwise we could run into the max module limit
        modules = cutArray(100, modules);

        types.assumeValidOrchestratorId(orchestratorId);
        types.assumeValidModules(modules);

        // Make sure mock addresses are not in set of modules.
        assumeMockAreNotInSet(modules);

        // Initialize orchestrator.
        orchestrator.init(
            orchestratorId,
            modules,
            fundingManager,
            authorizer,
            paymentProcessor
        );

        authorizer.setIsAuthorized(address(this), true);
        FundingManagerMock(address(orchestrator.fundingManager())).setToken(
            IERC20(address(0xA11CE))
        );

        // Create new funding manager module
        address newFundingManager = address(0x8888);
        vm.assume(newFundingManager != address(fundingManager));
        types.assumeElemNotInSet(modules, newFundingManager);

        vm.expectRevert();
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrchestrator_v1.Orchestrator_v1__InvalidModuleType.selector,
                newFundingManager
            )
        );
        orchestrator.setFundingManager(IFundingManager_v1(newFundingManager));
        assertTrue(orchestrator.fundingManager() == fundingManager);
    }

    function testSetPaymentProcessor(
        uint orchestratorId,
        address[] memory modules
    ) public {
        // limit to 100, otherwise we could run into the max module limit
        modules = cutArray(100, modules);

        types.assumeValidOrchestratorId(orchestratorId);
        types.assumeValidModules(modules);

        // Make sure mock addresses are not in set of modules.
        assumeMockAreNotInSet(modules);

        // Initialize orchestrator.
        orchestrator.init(
            orchestratorId,
            modules,
            fundingManager,
            authorizer,
            paymentProcessor
        );

        authorizer.setIsAuthorized(address(this), true);

        // Create new payment processor module
        PaymentProcessorMock newPaymentProcessor = new PaymentProcessorMock();
        vm.assume(newPaymentProcessor != paymentProcessor);
        types.assumeElemNotInSet(modules, address(newPaymentProcessor));

        // set the new payment processor module
        vm.expectEmit(true, true, true, true);
        emit PaymentProcessorUpdated(address(newPaymentProcessor));

        orchestrator.setPaymentProcessor(newPaymentProcessor);
        assertTrue(orchestrator.paymentProcessor() == newPaymentProcessor);
    }

    function testSetPaymentProcessorFailsIfWrongModuleType(
        uint orchestratorId,
        address[] memory modules
    ) public {
        // limit to 100, otherwise we could run into the max module limit
        modules = cutArray(100, modules);

        types.assumeValidOrchestratorId(orchestratorId);
        types.assumeValidModules(modules);

        // Make sure mock addresses are not in set of modules.
        assumeMockAreNotInSet(modules);

        // Initialize orchestrator.
        orchestrator.init(
            orchestratorId,
            modules,
            fundingManager,
            authorizer,
            paymentProcessor
        );

        authorizer.setIsAuthorized(address(this), true);

        // Create new payment processor module
        address newPaymentProcessor = address(0x8888);
        vm.assume(newPaymentProcessor != address(paymentProcessor));
        types.assumeElemNotInSet(modules, newPaymentProcessor);

        // set the new payment processor module. First the verification function reverts, then the setter.
        vm.expectRevert();
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrchestrator_v1.Orchestrator_v1__InvalidModuleType.selector,
                newPaymentProcessor
            )
        );
        orchestrator.setPaymentProcessor(IPaymentProcessor(newPaymentProcessor));

        assertTrue(orchestrator.paymentProcessor() == paymentProcessor);
    }

    //--------------------------------------------------------------------------
    // Tests: Transaction Execution

    function testExecuteTx(uint orchestratorId, address[] memory modules)
        public
    {
        types.assumeValidOrchestratorId(orchestratorId);

        address[] memory truncatedModules = new address[](125);
        if (modules.length > 125) {
            for (uint i; i < 125; i++) {
                truncatedModules[i] = modules[i];
            }

            types.assumeValidModules(truncatedModules);

            // Make sure mock addresses are not in set of truncatedModules.
            assumeMockAreNotInSet(truncatedModules);

            // Initialize orchestrator.
            orchestrator.init(
                orchestratorId,
                truncatedModules,
                fundingManager,
                authorizer,
                paymentProcessor
            );
        } else {
            types.assumeValidModules(modules);

            // Make sure mock addresses are not in set of modules.
            assumeMockAreNotInSet(modules);

            // Initialize orchestrator.
            orchestrator.init(
                orchestratorId,
                modules,
                fundingManager,
                authorizer,
                paymentProcessor
            );
        }
        authorizer.setIsAuthorized(address(this), true);

        bytes memory returnData = orchestrator.executeTx(
            address(this), abi.encodeWithSignature("ok()")
        );
        assertTrue(abi.decode(returnData, (bool)));
    }

    function testExecuteTxFailsIfCallFails(
        uint orchestratorId,
        address[] memory modules
    ) public {
        types.assumeValidOrchestratorId(orchestratorId);
        address[] memory truncatedModules = new address[](125);
        if (modules.length > 125) {
            for (uint i; i < 125; i++) {
                truncatedModules[i] = modules[i];
            }

            types.assumeValidModules(truncatedModules);

            // Make sure mock addresses are not in set of truncatedModules.
            assumeMockAreNotInSet(truncatedModules);

            // Initialize orchestrator.
            orchestrator.init(
                orchestratorId,
                truncatedModules,
                fundingManager,
                authorizer,
                paymentProcessor
            );
        } else {
            types.assumeValidModules(modules);

            // Make sure mock addresses are not in set of modules.
            assumeMockAreNotInSet(modules);

            // Initialize orchestrator.
            orchestrator.init(
                orchestratorId,
                modules,
                fundingManager,
                authorizer,
                paymentProcessor
            );
        }

        authorizer.setIsAuthorized(address(this), true);

        vm.expectRevert(
            IOrchestrator_v1.Orchestrator_v1__ExecuteTxFailed.selector
        );
        orchestrator.executeTx(
            address(this), abi.encodeWithSignature("fails()")
        );
    }

    function testExecuteTxFailsIfCallerNotAuthorized(
        uint orchestratorId,
        address[] memory modules
    ) public {
        types.assumeValidOrchestratorId(orchestratorId);

        address[] memory truncatedModules = new address[](125);
        if (modules.length > 125) {
            for (uint i; i < 125; i++) {
                truncatedModules[i] = modules[i];
            }

            types.assumeValidModules(truncatedModules);

            // Make sure mock addresses are not in set of truncatedModules.
            assumeMockAreNotInSet(truncatedModules);

            // Initialize orchestrator.
            orchestrator.init(
                orchestratorId,
                truncatedModules,
                fundingManager,
                authorizer,
                paymentProcessor
            );
        } else {
            types.assumeValidModules(modules);

            // Make sure mock addresses are not in set of modules.
            assumeMockAreNotInSet(modules);

            // Initialize orchestrator.
            orchestrator.init(
                orchestratorId,
                modules,
                fundingManager,
                authorizer,
                paymentProcessor
            );
        }

        authorizer.setIsAuthorized(address(this), false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrchestrator_v1.Orchestrator_v1__CallerNotAuthorized.selector,
                authorizer.getOwnerRole(),
                address(this)
            )
        );
        orchestrator.executeTx(address(this), abi.encodeWithSignature("ok()"));
    }

    function ok() public pure returns (bool) {
        return true;
    }

    function fails() public pure {
        revert("failed");
    }

    //--------------------------------------------------------------------------
    // Tests: Other

    function testVersion() public {
        assertEq(orchestrator.version(), "1");
    }

    //--------------------------------------------------------------------------
    // Helper Functions

    function assumeMockAreNotInSet(address[] memory modules) private view {
        types.assumeElemNotInSet(modules, address(fundingManager));
        types.assumeElemNotInSet(modules, address(authorizer));
        types.assumeElemNotInSet(modules, address(paymentProcessor));
        types.assumeElemNotInSet(modules, address(token));
    }

    function cutArray(uint size, address[] memory addrs)
        internal
        pure
        returns (address[] memory)
    {
        uint length = addrs.length;
        vm.assume(length > 0); //Array has to be at least 1

        if (length <= size) {
            return addrs;
        }

        address[] memory cutArry = new address[](size);
        for (uint i; i < size - 1;) {
            cutArry[i] = addrs[i];
            unchecked {
                ++i;
            }
        }
        return cutArry;
    }
}
