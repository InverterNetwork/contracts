// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {IRebasingERC20} from "@fm/rebasing/interfaces/IRebasingERC20.sol";

// Internal Dependencies
import {Module_v1} from "src/modules/base/Module_v1.sol";
import {ElasticReceiptToken_v1} from
    "@fm/rebasing/abstracts/ElasticReceiptToken_v1.sol";

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
 * @dev     Extends {ElasticReceiptToken_v1} for rebasing functionalities and
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
contract FM_Rebasing_v1 is
    IFundingManager_v1,
    ElasticReceiptToken_v1,
    Module_v1
{
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ElasticReceiptToken_v1, Module_v1)
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

    // This cap is one power of ten lower than the MAX_SUPPLY of
    // the underlying ElasticReceiptToken, just to be safe.
    uint internal constant DEPOSIT_CAP = 100_000_000_000_000_000e18;

    //--------------------------------------------------------------------------
    // Storage

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
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata);

        address orchestratorTokenAddress = abi.decode(configData, (address));
        _token = IERC20(orchestratorTokenAddress);

        string memory _id = orchestrator_.orchestratorId().toString();
        string memory _name = string(
            abi.encodePacked("Inverter Funding Token - Orchestrator_v1 #", _id)
        );
        string memory _symbol = string(abi.encodePacked("IFT-", _id));
        // Initial upstream contracts.
        __ElasticReceiptToken_init(
            _name, _symbol, IERC20Metadata(orchestratorTokenAddress).decimals()
        );
    }

    function token() public view returns (IERC20) {
        return _token;
    }

    /// @dev Returns the current token balance as supply target.
    function _supplyTarget()
        internal
        view
        override(ElasticReceiptToken_v1)
        returns (uint)
    {
        return token().balanceOf(address(this));
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

    function transferOrchestratorToken(address to, uint amount)
        external
        onlyPaymentClient
        validAddress(to)
    {
        _transferOrchestratorToken(to, amount);
    }

    //--------------------------------------------------------------------------
    // Internal Mutating Functions

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

    function _withdraw(address from, address to, uint amount) internal {
        amount = _burn(from, amount);

        token().safeTransfer(to, amount);

        emit Withdrawal(from, to, amount);
    }

    function _transferOrchestratorToken(address to, uint amount) internal {
        token().safeTransfer(to, amount);

        emit TransferOrchestratorToken(to, amount);
    }
}
