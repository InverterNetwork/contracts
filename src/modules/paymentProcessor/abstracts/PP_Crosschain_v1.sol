// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal
import {IPaymentProcessor_v1} from "@pp/IPaymentProcessor_v1.sol";
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";
import {CrossChainBase_v1} from "@pp/abstracts/CrossChainBase_v1.sol";
import {IPP_Crosschain_v1} from "@pp/interfaces/IPP_Crosschain_v1.sol";

// External
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

/**
 * @title   Cross-chain Payment Processor Base Contract
 *
 * @notice  Abstract base contract for implementing cross-chain payment processing functionality.
 *
 * @dev     This contract serves as the base for cross-chain payment processors and provides:
 *          - Extension of CrossChainBase_v1 for cross-chain functionality
 *          - Implementation of IPP_Crosschain_v1 interface
 *          - Core payment validation logic
 *          - Basic security checks for payment processing
 *          - Abstract functions for bridge-specific implementations
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 *
 * @custom:version 1.0.0
 *
 * @custom:standard-version 1.0.0
 */
abstract contract PP_Crosschain_v1 is CrossChainBase_v1, IPP_Crosschain_v1 {
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId_)
        public
        view
        virtual
        override(CrossChainBase_v1)
        returns (bool)
    {
        return interfaceId_ == type(IPP_Crosschain_v1).interfaceId
            || super.supportsInterface(interfaceId_);
    }

    //--------------------------------------------------------------------------
    // Storage Variables

    uint internal _paymentId;

    /// @notice Tracks all payments that could not be made to the paymentReceiver due to any reason.
    /// @dev	paymentClient => token address => paymentReceiver => unclaimable Amount.
    mapping(
        address paymentClient
            => mapping(
                address token => mapping(address recipient => uint amount)
            )
    ) internal _unclaimableAmountsForRecipient;

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

    // -------------------------------------------------------------------------
    // View Functions

    /// @inheritdoc IPP_Crosschain_v1
    function getPaymentId() external view returns (uint paymentId_) {
        return _paymentId;
    }

    /// @inheritdoc IPaymentProcessor_v1
    function unclaimable(address client, address token, address paymentReceiver)
        public
        view
        virtual
        override
        returns (uint amount)
    {
        return _unclaimableAmountsForRecipient[client][token][paymentReceiver];
    }

    //--------------------------------------------------------------------------
    // External/Public Functions

    /// @inheritdoc IPaymentProcessor_v1
    function claimPreviouslyUnclaimable(
        address client,
        address token,
        address receiver
    ) external virtual override {
        if (unclaimable(client, token, _msgSender()) == 0) {
            revert Module__PaymentProcessor__NothingToClaim(
                client, _msgSender()
            );
        }

        _claimPreviouslyUnclaimable(client, token, receiver);
    }

    /// @inheritdoc IPaymentProcessor_v1
    function cancelRunningPayments(IERC20PaymentClientBase_v2 client)
        external
        virtual
        onlyModule
        validClient(address(client))
    {
        // Implementation depends on specific bridge requirements
        revert("Not implemented");
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @notice used to claim the unclaimable amount of a particular `paymentReceiver` for a given payment client.
    /// @param  client address of the payment client.
    /// @param  token address of the payment token.
    /// @param  paymentReceiver address of the paymentReceiver for which the unclaimable amount will be claimed.
    function _claimPreviouslyUnclaimable(
        address client,
        address token,
        address paymentReceiver
    ) internal {
        address sender = _msgSender();
        uint amount = _unclaimableAmountsForRecipient[client][token][sender];
        delete _unclaimableAmountsForRecipient[client][token][sender];

        IERC20(token).transfer(paymentReceiver, amount);
        emit TokensReleased(paymentReceiver, address(token), amount);
    }

    /// @dev    Validate address input.
    /// @param  addr Address to validate.
    /// @return True if address is valid.
    function _validPaymentReceiver(address addr)
        internal
        view
        virtual
        returns (bool)
    {
        return !(
            addr == address(0) || addr == _msgSender() || addr == address(this)
                || addr == address(orchestrator())
                || addr == address(orchestrator().fundingManager().token())
        );
    }

    /// @dev    Validate transfer amount bigger than 0.
    /// @param  _total uint to validate.
    /// @return True if amount is valid.
    function _validTotal(uint _total) internal pure virtual returns (bool) {
        return _total != 0;
    }

    /// @dev    Validate payment token input.
    /// @param  _token Address of the token to validate.
    /// @return True if address is valid.
    function _validPaymentToken(address _token)
        internal
        virtual
        returns (bool)
    {
        (bool success, bytes memory data) = _token.call(
            abi.encodeWithSelector(
                IERC20(_token).balanceOf.selector, address(this)
            )
        );
        return success && data.length >= 32;
    }

    /// @dev    Gap for possible future upgrades.
    uint[50] private __gap;
}
