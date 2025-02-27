// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {
    IERC20PaymentClientBase_v2,
    IPaymentProcessor_v2
} from "@lm/abstracts/ERC20PaymentClientBase_v2.sol";
import {
    ERC20PaymentClientBase_v2,
    Module_v1
} from "@lm/abstracts/ERC20PaymentClientBase_v2.sol";

// External
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

// System under Test (SuT)
import {ILM_PC_Template_v1} from "src/templates/modules/ILM_PC_Template_v1.sol";

/**
 * @title   Inverter Template Logic Module Payment Client
 *
 * @notice  Basic template logic module payment client used as base for developing new
 *          logic module payment clients.
 *
 * @dev     This contract is used to showcase a basic setup for a logic module
 *          payment client. The contract showcases the following:
 *          - Inherit from the Module_v1 contract to enable interaction with
 *            the Inverter workflow.
 *          - Use of the ILM_PC_PaymentRouter_v2 interface to facilitate
 *            interaction as a Logic Module Payment Client.
 *          - Implement custom interface which has all the public facing
 *            functions, errors, events and structs.
 *          - Pre-defined layout for all contract functions, modifiers, state
 *            variables etc.
 *          - Use of the ERC165Upgradeable contract to check for interface
 *            support.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer
 *                          to our Security Policy at security.inverter.network
 *                          or email us directly!
 *
 * @custom:version 1.0.0
 *
 * @author  Inverter Network
 */
contract LM_PC_Template_v1 is ILM_PC_Template_v1, ERC20PaymentClientBase_v2 {
    // =========================================================================
    // Libraries

    using SafeERC20 for IERC20;

    // =========================================================================
    // ERC165

    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId_)
        public
        view
        virtual
        override(ERC20PaymentClientBase_v2)
        returns (bool)
    {
        return interfaceId_ == type(ILM_PC_Template_v1).interfaceId
            || super.supportsInterface(interfaceId_);
    }
}
