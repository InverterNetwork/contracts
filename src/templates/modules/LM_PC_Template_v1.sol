// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {ILM_PC_Template_v1} from "src/templates/modules/ILM_PC_Template_v1.sol";
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

/**
 * @title   Inverter Template Logic Module Payment Client
 *
 * @notice  A template for a logic module payment client.
 *          Users can deposit tokens up to a maximum amount, and
 *          authorized admins can process these deposits into payment orders.
 *
 * @dev     This contract implements the following key functionality:
 *          - Deposit handling with maximum amount validation
 *          - Payment order creation and processing through the Orchestrator
 *          - Role-based access control for deposit processing
 *          - ERC20 token integration with SafeERC20
 *          - Interface compliance checks via ERC165
 *
 *          Key components:
 *          - Inherits from ERC20PaymentClientBase_v2
 *          - Uses DEPOSIT_ADMIN_ROLE for authorized payment processing
 *          - Tracks user deposits in _depositedAmounts mapping
 *          - Enforces maximum deposit limit of 100 ether
 *          - Processes payments through Orchestrator's payment processor
 *
 * @custom:setup    This module requires the following MANDATORY setup steps:
 *
 *                  1. Configure DEPOSIT_ADMIN_ROLE:
 *                     - Purpose: Implements access control for processing user
 *                               deposits. Only authorized admins can process
 *                               deposits into payment orders.
 *                     - How:     The OrchestratorAdmin must:
 *                               1. Retrieve the deposit admin role identifier
 *                               2. Grant the role to designated admins
 *                     - Example: module.grantModuleRole(
 *                                 module.DEPOSIT_ADMIN_ROLE(),
 *                                 adminAddress
 *                               );
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
    // -------------------------------------------------------------------------
    // Libraries

    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
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

    //--------------------------------------------------------------------------
    // Constants

    /// @notice The maximum deposit amount.
    uint internal constant _maxDepositAmount = 100 ether;

    //--------------------------------------------------------------------------
    // State

    /// @notice The role that allows processing deposits
    bytes32 public constant DEPOSIT_ADMIN_ROLE = "DEPOSIT_ADMIN";

    /// @notice    Mapping of user addresses to their deposited token amounts.
    mapping(address user => uint amount) internal _depositedAmounts;

    /// @notice    Payment token.
    IERC20 internal _paymentToken;

    /// @notice    Storage gap for future upgrades.
    uint[50] private __gap;

    // -------------------------------------------------------------------------
    // Modifiers

    /// @notice Ensures the deposit amount is valid.
    /// @param  amount_ The amount to validate.
    modifier onlyValidDepositAmount(uint amount_) {
        _ensureValidDepositAmount(amount_);
        _;
    }

    // -------------------------------------------------------------------------
    // Constructor & Init

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata_,
        bytes memory configData_
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata_);

        // Decode module specific init data through use of configData bytes.
        // This value is an example value used to showcase the setters/getters
        // and internal functions/state formatting style.
        (address paymentToken) = abi.decode(configData_, (address));

        // Set init state.
        _paymentToken = IERC20(paymentToken);
    }

    // -------------------------------------------------------------------------
    // Public - Mutating

    /// @inheritdoc ILM_PC_Template_v1
    function deposit(uint amount_)
        external
        virtual
        onlyValidDepositAmount(amount_)
    {
        // Update state.
        _depositedAmounts[_msgSender()] += amount_;

        // Transfer tokens.
        _paymentToken.safeTransferFrom(_msgSender(), address(this), amount_);

        // Emit event.
        emit Deposited(_msgSender(), amount_);
    }

    /// @inheritdoc ILM_PC_Template_v1
    function processDeposit(address user_)
        external
        onlyModuleRole(DEPOSIT_ADMIN_ROLE)
    {
        uint amount = _depositedAmounts[user_];

        // Clear the deposit amount before processing.
        _depositedAmounts[user_] = 0;

        // Create and add payment order.
        PaymentOrder memory order = PaymentOrder({
            recipient: user_,
            paymentToken: address(_paymentToken),
            amount: amount,
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: 0,
            data: new bytes32[](0)
        });

        _addPaymentOrder(order);

        // Process the payment.
        __Module_orchestrator.paymentProcessor().processPayments(
            IERC20PaymentClientBase_v2(address(this))
        );
    }

    // -------------------------------------------------------------------------
    // Public - Getters

    /// @inheritdoc ILM_PC_Template_v1
    function getDepositedAmount(address user_) external view returns (uint) {
        return _depositedAmounts[user_];
    }

    // -------------------------------------------------------------------------
    // Internal

    /// @notice Ensures the deposit amount is valid.
    /// @param  amount_ The amount to validate.
    function _ensureValidDepositAmount(uint amount_) internal pure {
        if (amount_ == 0 || amount_ > _maxDepositAmount) {
            revert Module__LM_PC_Template_InvalidDepositAmount();
        }
    }
}
