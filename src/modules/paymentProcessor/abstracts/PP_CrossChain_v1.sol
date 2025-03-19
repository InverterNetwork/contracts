// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal
import {IPaymentProcessor_v1} from "@pp/IPaymentProcessor_v1.sol";
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";
import {CrossChainBase_v1} from "@pp/abstracts/CrossChainBase_v1.sol";
import {IPP_CrossChain_v1} from "@pp/interfaces/IPP_CrossChain_v1.sol";

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
 *          - Implementation of IPP_CrossChain_v1 interface
 *          - Core payment validation logic
 *          - Basic security checks for payment processing
 *          - Abstract functions for bridge-specific implementations
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Audit33
 *
 * @custom:version 1.0.0
 *
 * @custom:standard-version 1.0.0
 */
abstract contract PP_CrossChain_v1 is CrossChainBase_v1, IPP_CrossChain_v1 {
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId_)
        public
        view
        virtual
        override(CrossChainBase_v1)
        returns (bool)
    {
        return interfaceId_ == type(IPP_CrossChain_v1).interfaceId
            || super.supportsInterface(interfaceId_);
    }

    //--------------------------------------------------------------------------
    // Storage Variables

    /// @notice Payment ID incremented for each CrossChain payment
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

    /// @notice Checks that the caller is an active module.
    modifier onlyModule() {
        if (!orchestrator().isModule(_msgSender())) {
            revert Module__PaymentProcessor__OnlyCallableByModule();
        }
        _;
    }

    /// @notice Checks that the client is calling for itself.
    modifier validClient(address client) {
        if (_msgSender() != client) {
            revert Module__PaymentProcessor__CannotCallOnOtherClientsOrders();
        }
        _;
    }

    // -------------------------------------------------------------------------
    // View Functions

    /// @inheritdoc IPP_CrossChain_v1
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
    /// @param  client_ address of the payment client.
    /// @param  token_ address of the payment token.
    /// @param  paymentReceiver_ address of the paymentReceiver for which the unclaimable amount will be claimed.
    function _claimPreviouslyUnclaimable(
        address client_,
        address token_,
        address paymentReceiver_
    ) internal {
        address sender = _msgSender();
        uint amount = _unclaimableAmountsForRecipient[client_][token_][sender];
        delete _unclaimableAmountsForRecipient[client_][token_][sender];

        IERC20(token_).transfer(paymentReceiver_, amount);
        emit TokensReleased(paymentReceiver_, address(token_), amount);
    }

    /// @notice Validate address input.
    /// @param  addr_ Address to validate.
    /// @return True if address is valid.
    function _validPaymentReceiver(address addr_)
        internal
        view
        virtual
        returns (bool)
    {
        return !(
            addr_ == address(0) || addr_ == _msgSender()
                || addr_ == address(this) || addr_ == address(orchestrator())
                || addr_ == address(orchestrator().fundingManager().token())
        );
    }

    /// @notice Validate transfer amount bigger than 0.
    /// @param  total_ uint to validate.
    /// @return True if amount is valid.
    function _validTotal(uint total_) internal pure virtual returns (bool) {
        return total_ != 0;
    }

    /// @notice Validate payment token input.
    /// @param  token_ Address of the token to validate.
    /// @return True if address is valid.
    function _validPaymentToken(address token_)
        internal
        virtual
        returns (bool)
    {
        (bool success, bytes memory data) = token_.call(
            abi.encodeWithSelector(
                IERC20(token_).balanceOf.selector, address(this)
            )
        );
        return success && data.length >= 32;
    }

    /// @dev    Gap for possible future upgrades.
    uint[50] private __gap;
}
