// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Dependencies
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Dependencies
import {Module} from "src/modules/base/Module.sol";
import {Types} from "src/common/Types.sol";

// Internal Interfaces
import {
    IPaymentManager,
    IPayer,
    IModule
} from "src/interfaces/IPaymentManager.sol";
import {IProposal} from "src/interfaces/IProposal.sol";

/**
 * @title PaymentManager
 *
 * @dev @todo mp: Write docs...
 *
 * @author byterocket
 */
contract PaymentManager is IPaymentManager, Module {
    //--------------------------------------------------------------------------
    // Modifiers

    /// @dev Guarantees that function is only callable with valid payment id.
    modifier validId(uint id) {
        if (id >= _paymentIdCounter) {
            revert("Invalid Payment ID");
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    mapping(uint => Payment) private _payments;

    uint private _paymentIdCounter;

    /// @custom:invariant Not mutated after initialization.
    IERC20 private _paymentToken;

    //--------------------------------------------------------------------------
    // Initialization

    /// @inheritdoc Module
    function init(
        IProposal proposal_,
        Metadata memory metadata,
        bytes memory configdata
    ) external override (Module, IModule) initializer {
        __Module_init(proposal_, metadata);

        // Decode configdata.
        address token = abi.decode(configdata, (address));

        if (token == address(this) || token == address(0)) {
            revert("Invalid Payment Token");
        }

        _paymentToken = IERC20(token);
    }

    //--------------------------------------------------------------------------
    // onlyAuthorized Functions

    /// @inheritdoc IPayer
    function pay(address recipient, uint amount, bytes memory) external {
        // @todo mp: Problem with authentication?
        //           This caller could be e.g. the milestone module.
        addPayment(recipient, amount);
    }

    // Triggers delegatecall callback from proposal to send tokens inside
    // proposal into this contract. Assume proposal is already filled with
    // tokens for future payments.
    // This ensures that the tokens are there if needed.
    function addPayment(address recipient, uint amount)
        public
        onlyAuthorized
        returns (uint)
    {
        // Cache to save one SLOAD.
        uint id = _paymentIdCounter++;

        // Create new Payment instance.
        _payments[id] = Payment(id, recipient, amount, false, false, false);

        // Trigger proposal callback to fetch tokens to this contract.
        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__PaymentManager_fetchERC20FromProposal(address,uint)",
                address(this),
                amount
            ),
            Types.Operation.DelegateCall
        );

        // Return the payment's id.
        return id;
    }

    function pausePayment(uint id) external onlyAuthorized validId(id) {
        Payment storage p = _payments[id];

        _requirePausable(p);

        if (!p.isPaused) {
            p.isPaused = true;
            // @todo mp: Emit event.
        }
    }

    function unpausePayment(uint id) external onlyAuthorized validId(id) {
        Payment storage p = _payments[id];

        _requireUnpausable(p);

        if (p.isPaused) {
            p.isPaused = false;
            // @todo mp: Emit event.
        }
    }

    function removePayment(uint id) external onlyAuthorized validId(id) {
        Payment storage p = _payments[id];

        _requireRemovable(p);

        if (!p.isRemoved) {
            p.isRemoved = true;
            // @todo mp: Emit event.
        }
    }

    //--------------------------------------------------------------------------
    // User Mutating Functions

    // Sends tokens from this contract to caller (if caller has active payment).
    function claim(uint id) external validId(id) {
        Payment storage p = _payments[id];

        _requireClaimable(p);

        // Transfer tokens to caller.
        SafeERC20.safeTransfer(_paymentToken, msg.sender, p.amount);

        // Mark as being claimed.
        p.isClaimed = true;
        // @todo mp: Emit event.
    }

    //--------------------------------------------------------------------------
    // Public View Functions

    function listPayments() external view returns (Payment[] memory) {
        return listPayments(0, _paymentIdCounter);
    }

    // Return _payment[start:end] -> start inclusive, end exclusive
    function listPayments(uint start, uint end)
        public
        view
        returns (Payment[] memory)
    {
        if (start >= end) {
            revert("Start must be less then end");
        }

        uint diff = end - start;

        Payment[] memory payments = new Payment[](diff);

        uint returnIndex;
        for (uint i = start; i < end; i++) {
            Payment storage p = _payments[i];
            payments[returnIndex] = p;

            ++returnIndex;
        }

        return payments;
    }

    /// @inheritdoc IPayer
    function paymentToken() external view returns (IERC20) {
        return _paymentToken;
    }

    //--------------------------------------------------------------------------
    // Proposal Callbacks

    function __PaymentManager_transferERC20FromProposal(
        address recipient,
        uint amount
    ) external wantProposalContext {
        // Note that this function is called via `delegatecall`.
        // Therefore:
        // - address(this) == Proposal
        // - Only access storage variables prefixed with `__Proposal_`

        // Fetch paymentToken from proposal's IPayer instance.
        // Note that the IPayer instance is probably this contract.
        IERC20 token = __Proposal_payer.paymentToken();

        // Require that token balance is sufficient.
        uint balance = token.balanceOf(address(this));
        if (balance < amount) {
            revert("Not enough tokens");
        }

        // Transfer tokens from Proposal to recipient.
        SafeERC20.safeTransfer(token, recipient, amount);
    }

    //--------------------------------------------------------------------------
    // Internal Helper Functions

    function _hasAllowanceToClaim(address claimer, Payment storage p)
        internal
        view
        returns (bool)
    {
        // Currently boring.
        // Could later have allowance mapping.
        return claimer == p.recipient;
    }

    function _requireClaimable(Payment storage p) internal view {
        _requireNotClaimed(p);
        _requireNotPaused(p);
        _requireNotRemoved(p);
    }

    function _requirePausable(Payment storage p) internal view {
        _requireNotClaimed(p);
        _requireNotRemoved(p);
    }

    function _requireUnpausable(Payment storage p) internal view {
        _requireNotClaimed(p);
        _requireNotRemoved(p);
    }

    function _requireRemovable(Payment storage p) internal view {
        _requireNotClaimed(p);
    }

    function _requireNotClaimed(Payment storage p) internal view {
        if (p.isClaimed) {
            revert("Payment already claimed");
        }
    }

    function _requireNotRemoved(Payment storage p) internal view {
        if (p.isRemoved) {
            revert("Payment removed");
        }
    }

    function _requireNotPaused(Payment storage p) internal view {
        if (p.isPaused) {
            revert("Payment paused");
        }
    }
}
