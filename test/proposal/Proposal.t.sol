// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Dependencies
import {Proposal} from "src/proposal/Proposal.sol";

// Internal Interfaces
import {IProposal} from "src/proposal/IProposal.sol";
import {IAuthorizer} from "src/modules/IAuthorizer.sol";
import {IPaymentProcessor} from "src/modules/mixins/IPaymentProcessor.sol";

// Helpers
import {FuzzInputChecker} from "test/proposal/helper/FuzzInputChecker.sol";

// Mocks
import {AuthorizerMock} from "test/utils/mocks/AuthorizerMock.sol";
import {PaymentProcessorMock} from
    "test/utils/mocks/modules/mixins/PaymentProcessorMock.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract ProposalTest is Test, FuzzInputChecker {
    // SuT
    Proposal proposal;

    // Mocks
    AuthorizerMock authorizer;
    PaymentProcessorMock paymentProcessor;
    ERC20Mock token;

    function setUp() public {
        authorizer = new AuthorizerMock();
        paymentProcessor = new PaymentProcessorMock();
        token = new ERC20Mock("TestToken", "TST");

        proposal = new Proposal();
    }

    //--------------------------------------------------------------------------
    // Tests: Initialization

    function testInit(
        uint proposalId,
        address[] memory funders,
        address[] memory modules
    ) public {
        _assumeValidProposalId(proposalId);
        _assumeValidFunders(funders);
        _assumeValidModules(modules);

        // Make sure that the addresses we'll set manually are not already in the module list
        _assumeAddressNotInSet(modules, address(authorizer));
        _assumeAddressNotInSet(modules, address(paymentProcessor));
        _assumeAddressNotInSet(modules, address(token));

        // Set last two module to authorizer and paymentProcessor.
        modules[modules.length - 1] = address(authorizer);
        modules[modules.length - 2] = address(paymentProcessor);

        // Initialize proposal.
        proposal.init(
            proposalId, funders, modules, authorizer, paymentProcessor, token
        );

        // Check that proposal's storage correctly initialized.
        assertEq(address(proposal.authorizer()), address(authorizer));
        assertEq(
            address(proposal.paymentProcessor()), address(paymentProcessor)
        );
        assertEq(address(proposal.token()), address(token));
    }

    function testReinitFails(
        uint proposalId,
        address[] memory funders,
        address[] memory modules
    ) public {
        _assumeValidProposalId(proposalId);
        _assumeValidFunders(funders);
        _assumeValidModules(modules);

        // Make sure that the addresses we'll set manually are not already in the module list
        _assumeAddressNotInSet(modules, address(authorizer));
        _assumeAddressNotInSet(modules, address(paymentProcessor));
        _assumeAddressNotInSet(modules, address(token));

        // Set last two module to authorizer and paymentProcessor.
        modules[modules.length - 1] = address(authorizer);
        modules[modules.length - 2] = address(paymentProcessor);

        // Initialize proposal.
        proposal.init(
            proposalId, funders, modules, authorizer, paymentProcessor, token
        );

        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        proposal.init(
            proposalId, funders, modules, authorizer, paymentProcessor, token
        );
    }

    function testInitFailsForInvalidAuthorizer(
        uint proposalId,
        address[] memory funders,
        address[] memory modules
    ) public {
        _assumeValidProposalId(proposalId);
        _assumeValidFunders(funders);
        _assumeValidModules(modules);

        // Make sure that the addresses we'll set manually are not already in the module list
        _assumeAddressNotInSet(modules, address(paymentProcessor));
        _assumeAddressNotInSet(modules, address(token));

        // Note that the authorizer is not added to the modules list.
        modules[modules.length - 1] = address(paymentProcessor);

        vm.expectRevert(IProposal.Proposal__InvalidAuthorizer.selector);
        proposal.init(
            proposalId, funders, modules, authorizer, paymentProcessor, token
        );
    }

    function testInitFailsForInvalidPaymentProcessor(
        uint proposalId,
        address[] memory funders,
        address[] memory modules
    ) public {
        _assumeValidProposalId(proposalId);
        _assumeValidFunders(funders);
        _assumeValidModules(modules);

        // Make sure that the addresses we'll set manually are not already in the module list
        _assumeAddressNotInSet(modules, address(authorizer));
        _assumeAddressNotInSet(modules, address(token));

        // Note that the paymentProcessor is not added to the modules list.
        modules[modules.length - 1] = address(authorizer);

        vm.expectRevert(IProposal.Proposal__InvalidPaymentProcessor.selector);
        proposal.init(
            proposalId, funders, modules, authorizer, paymentProcessor, token
        );
    }

    function testInitFailsForInvalidToken(
        uint proposalId,
        address[] memory funders,
        address[] memory modules
    ) public {
        _assumeValidProposalId(proposalId);
        _assumeValidFunders(funders);
        _assumeValidModules(modules);

        // Make sure that the addresses we'll set manually are not already in the module list
        _assumeAddressNotInSet(modules, address(authorizer));
        _assumeAddressNotInSet(modules, address(paymentProcessor));

        // Set last two module to authorizer and paymentProcessor.
        modules[modules.length - 1] = address(authorizer);
        modules[modules.length - 2] = address(paymentProcessor);

        vm.expectRevert(IProposal.Proposal__InvalidToken.selector);
        proposal.init(
            proposalId,
            funders,
            modules,
            authorizer,
            paymentProcessor,
            IERC20(address(0))
        );
    }

    //--------------------------------------------------------------------------
    // Tests: Transaction Execution

    function testExecuteTx() public {
        // @todo mp: Add Proposal::executeTx tests.
    }

    //--------------------------------------------------------------------------
    // Tests: Other

    function testVersion() public {
        assertEq(proposal.version(), "1");
    }
}
