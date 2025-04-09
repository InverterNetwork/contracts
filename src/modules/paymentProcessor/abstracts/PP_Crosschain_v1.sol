// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IPaymentProcessor_v2} from "@pp/IPaymentProcessor_v2.sol";
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";
import {ERC165Upgradeable, Module_v1} from "src/modules/base/Module_v1.sol";

import {CrosschainBase_v1} from "./CrosschainBase_v1.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Dependencies
import {ERC20} from "@oz/token/ERC20/ERC20.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

// Internal Interfaces
import {IPP_Crosschain_v1} from "../interfaces/IPP_Crosschain_v1.sol";

/**
 * @title   Inverter Template Payment Processor
 *
 * @notice  Basic template payment processor used as base for developing new payment processors.
 *
 * @dev     This contract is used to showcase a basic setup for a payment processor. The contract showcases the
 *          following:
 *          - Inherit from the Module_v1 contract to enable interaction with the Inverter workflow.
 *          - Use of the IPaymentProcessor_v2 interface to facilitate interaction with a payment client.
 *          - Implement custom interface which has all the public facing functions, errors, events and structs.
 *          - Pre-defined layout for all contract functions, modifiers, state variables etc.
 *          - Use of the ERC165Upgradeable contract to check for interface support.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 */
abstract contract PP_Crosschain_v1 is CrosschainBase_v1, IPP_Crosschain_v1 {
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId_)
        public
        view
        virtual
        override(CrosschainBase_v1)
        returns (bool)
    {
        return interfaceId_ == type(IPP_Crosschain_v1).interfaceId
            || super.supportsInterface(interfaceId_);
    }

    //--------------------------------------------------------------------------
    // Modifiers

    /// @dev    Checks that the caller is an active module.
    modifier onlyModule() {
        if (!orchestrator().isModule(_msgSender())) {
            revert Module__PaymentProcessor__OnlyCallableByModule();
        }
        _;
    }

    /// @dev    Checks that the client is calling for itself.
    modifier validClient(address client) {
        if (_msgSender() != client) {
            revert Module__PaymentProcessor__CannotCallOnOtherClientsOrders();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    bytes public executionData;

    /// @dev    Gap for possible future upgrades.
    uint[50] private __gap;

    //--------------------------------------------------------------------------
    // Virtual Functions

    /// @notice Process payments for a given payment client
    /// @param client The payment client to process payments for
    function processPayments(IERC20PaymentClientBase_v2 client)
        external
        virtual
        override(IPaymentProcessor_v2)
    {}

    /// @inheritdoc IPaymentProcessor_v2
    function cancelRunningPayments(IERC20PaymentClientBase_v2 client)
        external
        onlyModule
        validClient(address(client))
    {
        // Implementation depends on specific bridge requirements
        revert("Not implemented");
    }

    /// @inheritdoc IPaymentProcessor_v2
    function claimPreviouslyUnclaimable(
        address client,
        address token,
        address receiver
    ) external {
        // Implementation depends on specific bridge requirements
        revert("Not implemented");
    }

    /// @inheritdoc IPaymentProcessor_v2
    function unclaimable(address client, address token, address paymentReceiver)
        public
        view
        returns (uint amount)
    {
        // Implementation depends on specific bridge requirements
        return 0;
    }

    /// @inheritdoc IPaymentProcessor_v2
    function validPaymentOrder(
        IERC20PaymentClientBase_v2.PaymentOrder memory order
    ) external returns (bool) {
        return _validPaymentReceiver(order.recipient)
            && _validTotal(order.amount)
            && _validTimes(order.start, order.cliff, order.end)
            && _validPaymentToken(order.paymentToken);
    }

    /// @dev    Validate address input.
    /// @param  addr Address to validate.
    /// @return True if address is valid.
    function _validPaymentReceiver(address addr) internal view returns (bool) {
        return !(
            addr == address(0) || addr == _msgSender() || addr == address(this)
                || addr == address(orchestrator())
                || addr == address(orchestrator().fundingManager().token())
        );
    }

    /// @dev    Validate uint total amount input.
    /// @param  _total uint to validate.
    /// @return True if uint is valid.
    function _validTotal(uint _total) internal pure returns (bool) {
        return !(_total == 0);
    }

    /// @dev    Validate uint start input.
    /// @param  _start uint to validate.
    /// @param  _cliff uint to validate.
    /// @param  _end uint to validate.
    /// @return True if uint is valid.
    function _validTimes(uint _start, uint _cliff, uint _end)
        internal
        pure
        returns (bool)
    {
        // _start + _cliff should be less or equal to _end
        // this already implies that _start is not greater than _end
        return _start + _cliff <= _end;
    }

    /// @dev    Validate payment token input.
    /// @param  _token Address of the token to validate.
    /// @return True if address is valid.
    function _validPaymentToken(address _token) internal returns (bool) {
        // Only a basic sanity check that the address supports the balanceOf() function. The corresponding
        // module should ensure it's sending an ERC20.

        (bool success, bytes memory data) = _token.call(
            abi.encodeWithSelector(
                IERC20(_token).balanceOf.selector, address(this)
            )
        );
        return success && data.length >= 32;
    }
}
