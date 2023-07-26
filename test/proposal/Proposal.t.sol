// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Dependencies
import {Proposal} from "src/proposal/Proposal.sol";
import {IModule} from "src/modules/base/IModule.sol";

// Internal Interfaces
import {
    IProposal,
    IAuthorizer,
    IPaymentProcessor
} from "src/proposal/IProposal.sol";

// Mocks
import {FundingManagerMock} from
    "test/utils/mocks/modules/FundingManagerMock.sol";
import {AuthorizerMock} from "test/utils/mocks/modules/AuthorizerMock.sol";
import {PaymentProcessorMock} from
    "test/utils/mocks/modules/PaymentProcessorMock.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// Helper
import {TypeSanityHelper} from "test/proposal/helper/TypeSanityHelper.sol";

contract ProposalTest is Test {
    // SuT
    Proposal proposal;

    // Helper
    TypeSanityHelper types;

    // Mocks
    FundingManagerMock fundingManager;
    AuthorizerMock authorizer;
    PaymentProcessorMock paymentProcessor;
    ERC20Mock token;

    event AuthorizerUpdated(address indexed _address);
    event FundingManagerUpdated(address indexed _address);
    event PaymentProcessorUpdated(address indexed _address);

    function setUp() public {
        fundingManager = new FundingManagerMock();
        authorizer = new AuthorizerMock();
        paymentProcessor = new PaymentProcessorMock();
        token = new ERC20Mock("TestToken", "TST");

        address impl = address(new Proposal());
        proposal = Proposal(Clones.clone(impl));

        types = new TypeSanityHelper(address(proposal));
    }

    //--------------------------------------------------------------------------
    // Tests: Initialization

    function testInit(uint proposalId, address[] memory modules) public {
        types.assumeValidProposalId(proposalId);
        types.assumeValidModules(modules);

        // Make sure mock addresses are not in set of modules.
        assumeMockAreNotInSet(modules);

        // Initialize proposal.
        proposal.init(
            proposalId,
            address(this),
            token,
            modules,
            fundingManager,
            authorizer,
            paymentProcessor
        );

        // Check that proposal's storage correctly initialized.
        assertEq(proposal.proposalId(), proposalId);
        assertEq(address(proposal.manager()), address(this));
        assertEq(address(proposal.token()), address(token));
        assertEq(address(proposal.authorizer()), address(authorizer));
        assertEq(
            address(proposal.paymentProcessor()), address(paymentProcessor)
        );

        // Check that proposal's dependencies correctly initialized.
        // Ownable:
        assertEq(proposal.manager(), address(this));
    }

    function testReinitFails(uint proposalId, address[] memory modules)
        public
    {
        types.assumeValidProposalId(proposalId);
        types.assumeValidModules(modules);

        // Make sure mock addresses are not in set of modules.
        assumeMockAreNotInSet(modules);

        // Initialize proposal.
        proposal.init(
            proposalId,
            address(this),
            token,
            modules,
            fundingManager,
            authorizer,
            paymentProcessor
        );

        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        proposal.init(
            proposalId,
            address(this),
            token,
            modules,
            fundingManager,
            authorizer,
            paymentProcessor
        );
    }

    //--------------------------------------------------------------------------
    // Tests: Replacing the three base modules: authorizer, funding manager,
    //        payment processor

    function testSetAuthorizer(uint proposalId, address[] memory modules)
        public
    {
        // limit to 100, otherwise we could run into the max module limit
        modules = cutArray(100, modules);

        types.assumeValidProposalId(proposalId);
        types.assumeValidModules(modules);

        // Make sure mock addresses are not in set of modules.
        assumeMockAreNotInSet(modules);

        // Initialize proposal.
        proposal.init(
            proposalId,
            address(this),
            token,
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

        proposal.setAuthorizer(newAuthorizer);
        vm.assume(proposal.authorizer() == newAuthorizer);

        // verify whether the init value is set and not the value from the old
        // authorizer, to check whether the replacement is successful
        vm.assume(
            !IAuthorizer(proposal.authorizer()).isAuthorized(address(this))
        );
        vm.assume(
            IAuthorizer(proposal.authorizer()).isAuthorized(address(0xA11CE))
        );
    }

    function testSetFundingManager(uint proposalId, address[] memory modules)
        public
    {
        // limit to 100, otherwise we could run into the max module limit
        modules = cutArray(100, modules);

        types.assumeValidProposalId(proposalId);
        types.assumeValidModules(modules);

        // Make sure mock addresses are not in set of modules.
        assumeMockAreNotInSet(modules);

        // Initialize proposal.
        proposal.init(
            proposalId,
            address(this),
            token,
            modules,
            fundingManager,
            authorizer,
            paymentProcessor
        );

        authorizer.setIsAuthorized(address(this), true);
        FundingManagerMock(address(proposal.fundingManager())).setToken(
            IERC20(address(0xA11CE))
        );

        // Create new funding manager module
        FundingManagerMock newFundingManager = new FundingManagerMock();
        vm.assume(newFundingManager != fundingManager);
        types.assumeElemNotInSet(modules, address(newFundingManager));

        // set the new funding manager module
        vm.assume(
            address((proposal.fundingManager()).token()) == address(0xA11CE)
        );
        vm.expectEmit(true, true, true, true);
        emit FundingManagerUpdated(address(newFundingManager));

        proposal.setFundingManager(newFundingManager);
        vm.assume(proposal.fundingManager() == newFundingManager);
        vm.assume(address((proposal.fundingManager()).token()) == address(0));
    }

    function testSetPaymentProcessor(uint proposalId, address[] memory modules)
        public
    {
        // limit to 100, otherwise we could run into the max module limit
        modules = cutArray(100, modules);

        types.assumeValidProposalId(proposalId);
        types.assumeValidModules(modules);

        // Make sure mock addresses are not in set of modules.
        assumeMockAreNotInSet(modules);

        // Initialize proposal.
        proposal.init(
            proposalId,
            address(this),
            token,
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

        proposal.setPaymentProcessor(newPaymentProcessor);
        vm.assume(proposal.paymentProcessor() == newPaymentProcessor);
    }

    //--------------------------------------------------------------------------
    // Tests: Transaction Execution

    function testExecuteTx(uint proposalId, address[] memory modules) public {
        types.assumeValidProposalId(proposalId);
        types.assumeValidModules(modules);

        // Make sure mock addresses are not in set of modules.
        assumeMockAreNotInSet(modules);

        // Initialize proposal.
        proposal.init(
            proposalId,
            address(this),
            token,
            modules,
            fundingManager,
            authorizer,
            paymentProcessor
        );

        authorizer.setIsAuthorized(address(this), true);

        bytes memory returnData =
            proposal.executeTx(address(this), abi.encodeWithSignature("ok()"));
        assertTrue(abi.decode(returnData, (bool)));
    }

    function testExecuteTxFailsIfCallFails(
        uint proposalId,
        address[] memory modules
    ) public {
        types.assumeValidProposalId(proposalId);
        types.assumeValidModules(modules);

        // Make sure mock addresses are not in set of modules.
        assumeMockAreNotInSet(modules);

        // Initialize proposal.
        proposal.init(
            proposalId,
            address(this),
            token,
            modules,
            fundingManager,
            authorizer,
            paymentProcessor
        );

        authorizer.setIsAuthorized(address(this), true);

        vm.expectRevert(IProposal.Proposal__ExecuteTxFailed.selector);
        proposal.executeTx(address(this), abi.encodeWithSignature("fails()"));
    }

    function testExecuteTxFailsIfCallerNotAuthorized(
        uint proposalId,
        address[] memory modules
    ) public {
        types.assumeValidProposalId(proposalId);
        types.assumeValidModules(modules);

        // Make sure mock addresses are not in set of modules.
        assumeMockAreNotInSet(modules);

        // Initialize proposal.
        proposal.init(
            proposalId,
            address(0xCAFE), // Note to not be the owner
            token,
            modules,
            fundingManager,
            authorizer,
            paymentProcessor
        );

        authorizer.setIsAuthorized(address(this), false);

        vm.expectRevert(IProposal.Proposal__CallerNotAuthorized.selector);
        proposal.executeTx(address(this), abi.encodeWithSignature("ok()"));
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
        assertEq(proposal.version(), "1");
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
