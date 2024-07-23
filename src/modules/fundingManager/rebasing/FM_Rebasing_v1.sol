// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {IRebasingERC20} from "@fm/rebasing/interfaces/IRebasingERC20.sol";

// Internal Dependencies
import {ERC165, Module_v1} from "src/modules/base/Module_v1.sol";
import {ElasticReceiptTokenBase_v1} from
    "@fm/rebasing/abstracts/ElasticReceiptTokenBase_v1.sol";

import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";

// External Interfaces
import {
    IERC20,
    IERC20Metadata
} from "@oz/token/ERC20/extensions/IERC20Metadata.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {Strings} from "@oz/utils/Strings.sol";

/**
 * @title   Rebasing Funding Manager
 *
 * @notice  This contract manages the issuance and redemption of rebasable funding tokens
 *          within the Inverter Network. It supports operations like deposits and withdrawals,
 *          implementing dynamic supply adjustments to maintain proportional ownership.
 *
 * @dev     Extends {ElasticReceiptTokenBase_v1} for rebasing functionalities and
 *          implements {IFundingManager_v1} interface. Manages deposits up to a defined cap,
 *          preventing excess balance accumulation and ensuring operational integrity.
 *          Custom rebase mechanics are applied based on the actual token reserves.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 */
contract FM_Rebasing_v1 is IFundingManager_v1, ElasticReceiptTokenBase_v1 {
    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ElasticReceiptTokenBase_v1)
        returns (bool)
    {
        return interfaceId == type(IFundingManager_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    using Strings for uint;
    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Modifier

    /// @dev Checks if the given Address is valid.
    modifier validAddress(address to) {
        if (to == address(0) || to == address(this)) {
            revert Module__FundingManager__InvalidAddress();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Constants

    /// @dev The maximum amount of tokens that can be deposited.
    // This cap is one power of ten lower than the MAX_SUPPLY of
    // the underlying ElasticReceiptTokenBase, just to be safe.
    uint internal constant DEPOSIT_CAP = 100_000_000_000_000_000e18;

    //--------------------------------------------------------------------------
    // Storage

    /// @dev The token that is used for the rebasing.
    IERC20 private _token;

    // Storage gap for future upgrades
    uint[50] private __gap;

    //--------------------------------------------------------------------------
    // Init Function

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override(ElasticReceiptTokenBase_v1) initializer {
        address orchestratorTokenAddress = abi.decode(configData, (address));
        _token = IERC20(orchestratorTokenAddress);

        string memory _id = orchestrator_.orchestratorId().toString();
        string memory _name = string(
            abi.encodePacked("Inverter Funding Token - Orchestrator_v1 #", _id)
        );
        string memory _symbol = string(abi.encodePacked("IFT-", _id));
        bytes memory underlyingConfigData = abi.encode(
            _name, _symbol, IERC20Metadata(orchestratorTokenAddress).decimals()
        );
        // Initial upstream contracts.
        __ElasticReceiptTokenBase_init(
            orchestrator_, metadata, underlyingConfigData
        );
    }

    /// @inheritdoc IFundingManager_v1
    function token() public view returns (IERC20) {
        return _token;
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @notice Deposits a specified amount of tokens into the contract from the sender's account.
    /// @dev    Reverts if attempting self-deposits or if the deposit exceeds the allowed cap,
    ///         ensuring compliance with token issuance rules. Please Note: when using the transactionForwarder,
    ///         validate transaction success to prevent nonce exploitation and ensure transaction integrity.
    /// @param amount The number of tokens to deposit.
    function deposit(uint amount) external {
        _deposit(_msgSender(), _msgSender(), amount);
    }

    /// @notice Deposits a specified amount of tokens into the contract on behalf of another account.
    /// @dev    Reverts if attempting self-deposits or if the deposit exceeds the allowed cap,
    ///         ensuring compliance with token issuance rules. Please Note: when using the transactionForwarder,
    ///         validate transaction success to prevent nonce exploitation and ensure transaction integrity.
    /// @param to The address to which the tokens are credited.
    /// @param amount The number of tokens to deposit.
    function depositFor(address to, uint amount) external {
        _deposit(_msgSender(), to, amount);
    }

    /// @notice Withdraws a specified amount of tokens from the sender's account back to their own address.
    /// @dev    Reverts if the withdrawal amount exceeds the available balance.
    ///         Please Note: when using the transactionForwarder, validate transaction success to
    ///         prevent nonce exploitation and ensure transaction integrity.
    /// @param amount The number of tokens to withdraw.
    function withdraw(uint amount) external {
        _withdraw(_msgSender(), _msgSender(), amount);
    }

    /// @notice Withdraws a specified amount of tokens from the sender's account to another specified account.
    /// @dev    Reverts if the withdrawal amount exceeds the available balance.
    ///         Please Note: when using the transactionForwarder, validate transaction success to
    ///         prevent nonce exploitation and ensure transaction integrity.
    /// @param to The address to which the tokens are sent.
    /// @param amount The number of tokens to withdraw.
    function withdrawTo(address to, uint amount) external {
        _withdraw(_msgSender(), to, amount);
    }

    //--------------------------------------------------------------------------
    // OnlyOrchestrator Mutating Functions

    /// @inheritdoc IFundingManager_v1
    function transferOrchestratorToken(address to, uint amount)
        external
        onlyPaymentClient
        validAddress(to)
    {
        _transferOrchestratorToken(to, amount);
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @dev Returns the current token balance as supply target.
    /// @return The current token balance as supply target.
    function _supplyTarget()
        internal
        view
        override(ElasticReceiptTokenBase_v1)
        returns (uint)
    {
        return token().balanceOf(address(this));
    }

    /// @dev Deposits tokens into the contract.
    /// @param from The address to deposit from.
    /// @param to The address to deposit to.
    /// @param amount The amount of tokens to deposit.
    function _deposit(address from, address to, uint amount) internal {
        // Depositing from itself with its own balance would mint tokens without increasing underlying balance.
        if (from == address(this)) {
            revert Module__FundingManager__CannotSelfDeposit();
        }

        if ((amount + token().balanceOf(address(this))) > DEPOSIT_CAP) {
            revert Module__FundingManager__DepositCapReached();
        }

        _mint(to, amount);

        token().safeTransferFrom(from, address(this), amount);

        emit Deposit(from, to, amount);
    }

    /// @dev Withdraws `amount` of tokens from the funds of `from` to `to`.
    /// @param from The address to withdraw from.
    /// @param to The address to withdraw to.
    /// @param amount The amount of tokens to withdraw.
    function _withdraw(address from, address to, uint amount) internal {
        amount = _burn(from, amount);

        token().safeTransfer(to, amount);

        emit Withdrawal(from, to, amount);
    }

    //--------------------------------------------------------------------------
    // IFundingManager_v1 Functions

    /// @notice Transfers `amount` of tokens from the orchestrator to `to`.
    /// @param to The address to transfer to.
    /// @param amount The amount of tokens to transfer.
    function _transferOrchestratorToken(address to, uint amount) internal {
        token().safeTransfer(to, amount);

        emit TransferOrchestratorToken(to, amount);
    }
}
