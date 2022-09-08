// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {Types} from "src/common/Types.sol";
import {Module} from "src/modules/base/Module.sol";

// Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IProposal} from "src/interfaces/IProposal.sol";

contract Payment is Module {
    struct PaymentTerms {
        uint id;
        address token;
        address receiver;
        uint amount;
        uint executableAfter;
        bool executed;
    }

    mapping(uint => PaymentTerms) private _payments;

    uint private _id;

    function initialize(IProposal proposal, bytes memory) external {
        __Module_init(proposal);

        // Decode params like:
        // (uint a) = abi.decode(data, (uint));
    }

    //--------------------------------------------------------------------------
    // wantProposalContext Functions
    //
    // For more info see {Module}.

    function __Proposal_executeTokenTransfer(
        address token,
        address receiver,
        uint amount
    )
        external
        wantProposalContext
    {
        bool ok;
        ok = IERC20(token).transfer(receiver, amount);
        if (!ok) {
            revert();
        }
    }

    //--------------------------------------------------------------------------
    // External Functions

    function addPayment(
        address token,
        address receiver,
        uint amount,
        uint executableAfter
    )
        external
        onlyAuthorized
        returns (uint)
    {
        uint id = _id;
        _id++;

        if (executableAfter < block.timestamp) {
            revert("Executability must be not be in the past");
        }

        PaymentTerms memory payment =
            PaymentTerms(id, token, receiver, amount, executableAfter, false);

        _payments[id] = payment;

        return id;
    }

    function executePayment(uint id) external onlyAuthorized {
        if (id >= _id) {
            revert("Invalid id");
        }

        PaymentTerms storage payment = _payments[id];

        // Revert if payment not executable.
        if (payment.executableAfter > block.timestamp) {
            revert("Not yet executable");
        }

        // Revert if payment already executed.
        if (payment.executed) {
            revert("Already executed");
        }

        // Revert if proposal has insufficient funds.
        uint balance =
            IERC20(payment.token).balanceOf(address(__Module_proposal));
        if (balance < payment.amount) {
            revert("Insufficient balance");
        }

        // Execute ERC20 token transfer in context of the proposal.
        bytes memory funcData = abi.encodeWithSignature(
            "__Proposal_executeTokenTransfer(address,address,uint256)",
            payment.token,
            payment.receiver,
            payment.amount
        );
        _triggerProposalCallback(funcData, Types.Operation.DelegateCall);
    }

    function removePayment(uint id) external onlyAuthorized {
        PaymentTerms storage payment = _payments[id];

        if (!payment.executed) {
            delete _payments[id];
        } else {
            revert("Cannot delete already executed payment");
        }
    }
}
