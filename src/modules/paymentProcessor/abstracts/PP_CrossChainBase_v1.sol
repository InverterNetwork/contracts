// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal
import {IPaymentProcessor_v1} from "@pp/IPaymentProcessor_v1.sol";
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol";
import {IPP_CrossChainBase_v1} from "@pp/interfaces/IPP_CrossChainBase_v1.sol";

// External
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

/**
 * @title   Cross-chain Payment Processor Base Contract.
 *
 * @notice  Abstract base contract for implementing cross-chain payment
 *          processing functionality.
 *
 * @dev     Inherits functionality from:
 *          - IPP_CrossChainBase_v1: Implementation interface.
 *          - IPaymentProcessor_v1: Payment processor interface.
 *          - Module_v1: Base module functionality.
 *
 *          Key features:
 *              - Bridge Data Management
 *                Stores and retrieves bridge-specific data for each bridge
 *                operation.
 *
 *              - Payment ID tracking.
 *                Tracks the payment ID for each cross-chain payment.
 *
 *              - Enforces interface implementation.
 *                Abstract bridge transfer function enforcing custom
 *                implementation in inheriting contracts.
 *
 *              - Unclaimable amounts tracking.
 *                Provides functionality to claim unclaimable amounts
 *                (failed bridge transfers) for each payment client, token,
 *                and recipient to the current chain.
 *
 *              - Base cross-chain payment validation.
 *                Implements basic validation checks for cross-chain payments.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @custom:version 1.0.0
 *
 * @custom:standard-version 1.0.0
 *
 * @author  33Audits
 */
abstract contract PP_CrossChainBase_v1 is IPP_CrossChainBase_v1, Module_v1 {
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId_)
        public
        view
        virtual
        override(Module_v1)
        returns (bool)
    {
        return interfaceId_ == type(IPP_CrossChainBase_v1).interfaceId
            || interfaceId_ == type(IPaymentProcessor_v1).interfaceId
            || super.supportsInterface(interfaceId_);
    }

    //--------------------------------------------------------------------------
    // Storage Variables

    /// @notice Payment ID incremented for each CrossChain payment.
    uint internal _paymentId;

    /// @notice Tracks all payments that could not be made to the paymentReceiver due to any reason.
    /// @dev	paymentClient => token address => paymentReceiver => unclaimable Amount.
    mapping(
        address paymentClient
            => mapping(
                address token => mapping(address recipient => uint amount)
            )
    ) internal _unclaimableAmountsForRecipient;

    /// @notice Mapping of payment IDs to bridge data.
    mapping(uint paymentId => bytes bridgeData) internal _paymentIdToBridgeData;

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
    modifier validClient(address client_) {
        if (_msgSender() != client_) {
            revert Module__PaymentProcessor__CannotCallOnOtherClientsOrders();
        }
        _;
    }

    // -------------------------------------------------------------------------
    // View Functions

    /// @inheritdoc IPP_CrossChainBase_v1
    function getBridgeDataByPaymentId(uint paymentId_)
        public
        view
        virtual
        returns (bytes memory bridgeData_)
    {
        return _paymentIdToBridgeData[paymentId_];
    }

    /// @inheritdoc IPP_CrossChainBase_v1
    function getPaymentId() external view virtual returns (uint paymentId_) {
        return _paymentId;
    }

    /// @inheritdoc IPaymentProcessor_v1
    function unclaimable(
        address client_,
        address token_,
        address paymentReceiver_
    ) public view virtual override returns (uint amount_) {
        return
            _unclaimableAmountsForRecipient[client_][token_][paymentReceiver_];
    }

    //--------------------------------------------------------------------------
    // External Functions

    /// @inheritdoc IPaymentProcessor_v1
    function claimPreviouslyUnclaimable(
        address client_,
        address token_,
        address receiver_
    ) external virtual override {
        if (unclaimable(client_, token_, _msgSender()) == 0) {
            revert Module__PaymentProcessor__NothingToClaim(
                client_, _msgSender()
            );
        }

        _claimPreviouslyUnclaimable(client_, token_, receiver_);
    }

    /// @inheritdoc IPaymentProcessor_v1
    function cancelRunningPayments(IERC20PaymentClientBase_v2 client_)
        external
        virtual
        onlyModule
        validClient(address(client_))
    {
        // Implementation depends on specific bridge requirements
        revert("Not implemented");
    }

    // -------------------------------------------------------------------------
    // Internal Functions Implemented in Downstream Contract

    /// @notice Execute the cross-chain bridge transfer.
    /// @dev    Override this function to implement specific bridge logic.
    /// @param  order_ The payment order containing all necessary transfer details.
    function _executeBridgeTransfer(
        IERC20PaymentClientBase_v2.PaymentOrder memory order_
    ) internal virtual;

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
    ) internal virtual {
        address sender = _msgSender();
        uint amount = _unclaimableAmountsForRecipient[client_][token_][sender];
        delete _unclaimableAmountsForRecipient[client_][token_][sender];

        IERC20(token_).transfer(paymentReceiver_, amount);
        emit TokensReleased(paymentReceiver_, address(token_), amount);
    }

    /// @notice Validate address input.
    /// @param addr_ The address to validate
    /// @return valid_ True if address is valid.
    function _validPaymentReceiver(address addr_)
        internal
        view
        virtual
        returns (bool valid_)
    {
        return !(
            addr_ == address(0) || addr_ == _msgSender()
                || addr_ == address(this) || addr_ == address(orchestrator())
                || addr_ == address(orchestrator().fundingManager().token())
        );
    }

    /// @notice Validate transfer amount bigger than 0.
    /// @param  total_ uint to validate.
    /// @return valid_ True if amount is valid.
    function _validTotal(uint total_)
        internal
        pure
        virtual
        returns (bool valid_)
    {
        return total_ != 0;
    }

    /// @notice Validate payment token input.
    /// @param  token_ Address of the token to validate.
    /// @return valid_ True if token is valid.
    function _validPaymentToken(address token_)
        internal
        virtual
        returns (bool valid_)
    {
        (bool success, bytes memory data) = token_.call(
            abi.encodeWithSelector(
                IERC20(token_).balanceOf.selector, address(this)
            )
        );
        valid_ = success && data.length >= 32;
        return valid_;
    }

    /// @dev    Gap for possible future upgrades.
    uint[50] private __gap;
}
