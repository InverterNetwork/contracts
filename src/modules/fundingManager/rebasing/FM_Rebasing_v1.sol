// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {IRebasingERC20} from "@fm/rebasing/interfaces/IRebasingERC20.sol";

// Internal Dependencies
import {ERC165, Module_v1} from "src/modules/base/Module_v1.sol";
import {
    ElasticReceiptTokenUpgradeable_v1,
    ElasticReceiptTokenBase_v1
} from "@fm/rebasing/abstracts/ElasticReceiptTokenUpgradeable_v1.sol";

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
 * @dev     Extends {ElasticReceiptTokenUpgradeable_v1} for rebasing functionalities and
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
    ElasticReceiptTokenUpgradeable_v1,
    Module_v1
{
    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ElasticReceiptTokenUpgradeable_v1, Module_v1)
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
    uint internal constant DEPOSIT_CAP = 100_000_000e18;

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

    /// @inheritdoc IFundingManager_v1
    function token() public view returns (IERC20) {
        return _token;
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @notice Deposits `amount` of tokens from `msg.sender` to `msg.sender`.
    /// @param amount The amount of tokens to deposit.
    function deposit(uint amount) external {
        _deposit(_msgSender(), _msgSender(), amount);
    }

    /// @notice Deposits `amount` of tokens from `msg.sender` to `to`.
    /// @param to The address to deposit to.
    /// @param amount The amount of tokens to deposit.
    function depositFor(address to, uint amount) external {
        _deposit(_msgSender(), to, amount);
    }

    /// @notice Withdraws `amount` of tokens from `msg.sender` to `msg.sender`.
    /// @param amount The amount of tokens to withdraw.
    function withdraw(uint amount) external {
        _withdraw(_msgSender(), _msgSender(), amount);
    }

    /// @notice Withdraws `amount` of tokens from `msg.sender` to `to`.
    /// @param to The address to withdraw to.
    /// @param amount The amount of tokens to withdraw.
    function withdrawTo(address to, uint amount) external {
        _withdraw(_msgSender(), to, amount);
    }

    //--------------------------------------------------------------------------
    // OnlyOrchestrator Mutating Functions

    /// @inheritdoc IFundingManager_v1
    function transferOrchestratorToken(address to, uint amount)
        external
        onlyOrchestrator
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
