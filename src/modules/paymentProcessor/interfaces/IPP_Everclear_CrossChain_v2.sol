// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

// Internal
import {IPaymentProcessor_v2} from
    "src/modules/paymentProcessor/IPaymentProcessor_v2.sol";

// External
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";
import {IEverclear} from
    "src/modules/paymentProcessor/interfaces/IEverclear.sol";

/**
 * @title   Everclear Protocol Integrated Cross-Chain Payment Processor.
 *
 * @notice  A payment processor implementation that enables cross-chain payments
 *          using the Everclear protocol. This module processes payment orders created by an Inverter Payment Client
 *          and bridges the payments to the target chain through Everclear's infrastructure.
 *
 * @dev     Inherits functionality from:
 *          - IPP_Everclear_CrossChain_v2: Implementation interface.
 *          - PP_CrossChainBase_v2: Cross-chain Payment Processor Base.
 *
 *          Key features:
 *              - Cross-chain payment processing
 *                Enables execution of payment orders across different networks.
 *
 *              - Everclear Bridge integration.
 *                Integrates with Everclear protocol for secure cross-chain transfers, creating a new intent for each payment order through calling the Everclear Spoke contract.
 *
 *              - Failed bridge transfer retry.
 *                Provides mechanism to retry failed bridge transfers through leveraging the unclaimable amounts and providing a new payment order.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @custom:version  v2.0.0
 *
 * @custom:standard-version v1.0.0
 *
 * @author  33Audits
 */
interface IPP_Everclear_CrossChain_v2 {
    //--------------------------------------------------------------------------
    // View Functions

    /// @notice Returns the Everclear spoke contract address.
    /// @return everClearSpoke_ The Everclear contract address.
    function getEverClearSpoke()
        external
        view
        returns (IEverclear everClearSpoke_);

    /// @notice Returns the Everclear intent for a given intent ID.
    /// @param  intentId_ The intent ID.
    /// @return intent_ The Everclear intent.
    function getIntentByIntentId(bytes32 intentId_)
        external
        view
        returns (IEverclear.Intent memory intent_);
}
