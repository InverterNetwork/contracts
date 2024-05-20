// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IAuthorizer_v1} from "@aut/IAuthorizer_v1.sol";
import {ILM_PC_PaymentRouter_v1} from "@lm/interfaces/ILM_PC_PaymentRouter_v1.sol";
import {
    IERC20PaymentClientBase_v1,
    IPaymentProcessor_v1
} from "@lm/abstracts/ERC20PaymentClientBase_v1.sol";

// Internal Dependencies
import {
    ERC20PaymentClientBase_v1,
    Module_v1
} from "@lm/abstracts/ERC20PaymentClientBase_v1.sol";

// Internal Libraries


// External Libraries


// NOTE: Development halted until the payment processor can handle multiple tokens,  and not only the native orchestrator one

/**
 * @title   Payment Router
 *
 * @notice  Tis module is a stopgap solution to enable pushing payments to the Payment Processor. 
 *
 *
 * @dev     Extends {ERC20PaymentClientBase_v1} to integrate payment processing with
 *          bounty management, supporting dynamic additions, updates, and the locking
 *          of bounties. Utilizes roles for managing permissions and maintaining robust
 *          control over bounty operations.
 *
 * @author  Inverter Network
 */
contract LM_PC_PaymentRouter_v1 is ILM_PC_PaymentRouter_v1, ERC20PaymentClientBase_v1 {
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC20PaymentClientBase_v1)
        returns (bool)
    {
        return interfaceId == type(ILM_PC_PaymentRouter_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }


    

}