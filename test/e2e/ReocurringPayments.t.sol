// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {E2eTest} from "test/e2e/E2eTest.sol";
import "forge-std/console.sol";

//Internal Dependencies
import {ModuleTest, IModule, IProposal} from "test/modules/ModuleTest.sol";
import {IProposalFactory} from "src/factories/ProposalFactory.sol";
import {AuthorizerMock} from "test/utils/mocks/modules/AuthorizerMock.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {RebasingFundingManager} from
    "src/modules/fundingManager/RebasingFundingManager.sol";
// SuT
import {
    ReocurringPaymentManager,
    IReocurringPaymentManager,
    IPaymentClient
} from "src/modules/logicModule/ReocurringPaymentManager.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

 // 1. deopsit some funds to fundingManager
 // 2. create reocurringPayments: 2 for alice, 1 for bob
 // 3. warp forward, they both withdraw
 // 4. remove 1 payment for alice and 1 for bob
 // 5. warp forward they both withdraw again
 // 6. bob gets nothing while alice still gets 1 payment

contract ReocurringPayments is E2eTest {

    // Alice and Bob are receivers
    address alice = address(0xA11CE);
    address bob = address(0x606);

    // Parameters for reocurring payments
    uint paymentAmount = 10e12;
    uint startEpoch;
    uint epochLength = 604800; // 1 week;
    uint epochsAmount = 10;

    // Constants
    uint constant _SENTINEL = type(uint).max;

    ERC20Mock token = new ERC20Mock("Mock", "MOCK");

    // Module Constants
    uint constant _MAJOR_VERSION = 1;
    uint constant _MINOR_VERSION = 1;
    string constant _URL = "https://github.com/organization/module";
    string constant _TITLE = "Module";

    function test_e2e_ReocurringPayments() public {

        ReocurringPaymentManager reocurringPaymentManager;

        // -----------INIT
        // address(this) creates a new proposal.
        IProposalFactory.ProposalConfig memory proposalConfig = IProposalFactory
            .ProposalConfig({owner: address(this), token: token});

        IProposal proposal = _createNewProposalWithAllModules(proposalConfig);

        RebasingFundingManager fundingManager =
            RebasingFundingManager(address(proposal.fundingManager()));

        // ------------------ FROM ModuleTest.sol
        address impl = address(new ReocurringPaymentManager());
        reocurringPaymentManager = ReocurringPaymentManager(Clones.clone(impl));

        IModule.Metadata memory _METADATA =
            IModule.Metadata(_MAJOR_VERSION, _MINOR_VERSION, _URL, _TITLE);

        AuthorizerMock _authorizer = new AuthorizerMock();

        //Init Module correct
        reocurringPaymentManager.init(proposal, _METADATA, abi.encode(1 weeks));
        assertEq(reocurringPaymentManager.getEpochLength(), 1 weeks);

        _authorizer.setIsAuthorized(address(this), true);

        // ----------------

        // 1. deopsit some funds to fundingManager
        uint initialDeposit = 10e18;
        token.mint(address(this), initialDeposit);
        token.approve(address(fundingManager), initialDeposit);
        fundingManager.deposit(initialDeposit);

        // 2. create reocurringPayments: 2 for alice, 1 for bob
        startEpoch = reocurringPaymentManager.getCurrentEpoch();
        reocurringPaymentManager.addReocurringPayment(
            paymentAmount, startEpoch+1, bob
        );
        reocurringPaymentManager.addReocurringPayment(
            paymentAmount, startEpoch+1, alice
        );
        reocurringPaymentManager.addReocurringPayment(
            paymentAmount, startEpoch+1, alice
        );

        // 3. warp forward, they both withdraw
        vm.warp(epochLength * epochsAmount + 1);
        reocurringPaymentManager.trigger();

        // Alice should have twice as much as Bob, since two reocurring
        // payments were made for her.
        assertEq(token.balanceOf(alice), epochLength * epochsAmount * 2);
        assertEq(token.balanceOf(bob), epochLength * epochsAmount);

        // 4. remove 1 payment for alice and 1 for bob
        reocurringPaymentManager.removeReocurringPayment(_SENTINEL, 2);  // Alice at index 2
        reocurringPaymentManager.removeReocurringPayment(_SENTINEL, 1);  // Bob at index 1

        // 5. warp forward they both withdraw again
        vm.warp(epochLength + epochsAmount + 1);
        reocurringPaymentManager.trigger();

        // 6. bob gets nothing while alice still gets 1 payment
        // In total Alice should received 30 payments (3 * epochsAmount),
        // while Bob should received 10 payments (1 * epochs amount)
        assertEq(token.balanceOf(alice), epochLength * epochsAmount * 3);
        assertEq(token.balanceOf(alice), epochLength * epochsAmount);
    }
}
