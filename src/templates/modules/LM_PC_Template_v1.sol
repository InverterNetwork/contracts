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

    //--------------------------------------------------------------------------
    // Constants

    uint internal constant _maxDepositAmount = 100 ether;

    //--------------------------------------------------------------------------
    // State

    /// @dev The role that allows processing deposits
    bytes32 public constant DEPOSIT_ADMIN_ROLE = "DEPOSIT_ADMIN";

    /// @notice    Mapping of user addresses to their deposited token amounts.
    mapping(address user => uint amount) internal _depositedAmounts;

    /// @notice    Payment token.
    IERC20 internal _paymentToken;

    /// @notice    Storage gap for future upgrades.
    uint[50] private __gap;

    // =========================================================================
    // Modifiers

    modifier onlyValidDepositAmount(uint amount_) {
        _ensureValidDepositAmount(amount_);
        _;
    }

    // =========================================================================
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

    // =========================================================================
    // Public - Mutating

    /// @inheritdoc ILM_PC_Template_v1
    function deposit(uint amount_) external virtual onlyValidDepositAmount(amount_) {
        // Update state.
        _depositedAmounts[_msgSender()] += amount_;

        // Transfer tokens.
        _paymentToken.safeTransferFrom(
            _msgSender(), address(this), amount_
        );

        // Emit event.
        emit Deposited(_msgSender(), amount_);
    }

    /// @inheritdoc ILM_PC_Template_v1
    function processDeposit(address user_) external onlyModuleRole(DEPOSIT_ADMIN_ROLE) {
        uint amount = _depositedAmounts[user_];
        require(amount > 0, "No deposit to process");

        // Clear the deposit amount before processing
        _depositedAmounts[user_] = 0;

        // Create and add payment order
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

        // Process the payment
        __Module_orchestrator.paymentProcessor().processPayments(
            IERC20PaymentClientBase_v2(address(this))
        );
    }

    // =========================================================================
    // Public - Getters

    /// @inheritdoc ILM_PC_Template_v1
    function getDepositedAmount(address user_) external view returns (uint) {
        return _depositedAmounts[user_];
    }

    //--------------------------------------------------------------------------
    // Internal

    /// @dev    Ensures the deposit amount is valid.
    /// @param  amount_ The amount to validate.
    function _ensureValidDepositAmount(uint amount_) internal pure {
        if (amount_ > _maxDepositAmount) {
            revert Module__LM_PC_Template_InvalidDepositAmount();
        }
    }
}
