// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {IFM_DepositVault_v1} from
    "@fm/depositVault/interfaces/IFM_DepositVault_v1.sol";

// Internal Dependencies
import {Module_v1, IModule_v1} from "src/modules/base/Module_v1.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/extensions/IERC20Metadata.sol";

// External Dependencies
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

/**
 * @title   Inverter Deposit Vault Funding Manager
 *
 * @notice  This contract allows users to deposit tokens to fund the workflow.
 *
 * @dev     Implements {IFundingManager_v1} interface.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer
 *                          to our Security Policy at security.inverter.network
 *                          or email us directly!
 *
 * @custom:version 1.1.0
 *
 * @author  Inverter Network
 */
contract FM_DepositVault_v1 is
    IFundingManager_v1,
    IFM_DepositVault_v1,
    Module_v1
{
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(Module_v1)
        returns (bool)
    {
        return interfaceId == type(IFundingManager_v1).interfaceId
            || interfaceId == type(IFM_DepositVault_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Storage

    /// @dev	Base Points used for percentage calculation.
    ///         This value represents 100%.
    uint internal constant BPS = 10_000;

    /// @dev    The token that is deposited.
    IERC20 private _token;

    /// @dev    Storage gap for future upgrades.
    uint[50] private __gap;

    //--------------------------------------------------------------------------
    // Init Function

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override initializer {
        __Module_init(orchestrator_, metadata);

        address orchestratorTokenAddress = abi.decode(configData, (address));
        _token = IERC20(orchestratorTokenAddress);
    }

    //--------------------------------------------------------------------------
    // Public View Functions

    /// @inheritdoc IFundingManager_v1
    function token() public view returns (IERC20) {
        return _token;
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IFM_DepositVault_v1
    function deposit(uint amount) external {
        address from = _msgSender();
        token().safeTransferFrom(from, address(this), amount);

        (uint collateralFeePercentage, address collateralTreasury) =
        _getFeeManagerCollateralFeeData(
            bytes4(keccak256(bytes("deposit(uint)")))
        );

        // skip protocol fee collection if fee is 0
        if (collateralFeePercentage > 0) {
            uint protocolFeeAmount = amount * collateralFeePercentage / BPS;

            _processProtocolFeeViaTransfer(
                collateralTreasury, _token, protocolFeeAmount
            );
        }
        emit Deposit(from, amount);
    }

    //--------------------------------------------------------------------------
    // OnlyOrchestrator Mutating Functions

    /// @inheritdoc IFundingManager_v1
    function transferOrchestratorToken(address to, uint amount)
        external
        onlyPaymentClient
        validAddress(to)
    {
        token().safeTransfer(to, amount);

        emit TransferOrchestratorToken(to, amount);
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @dev	Transfer protocol fees to the treasury.
    /// @param  treasury_ The address of the protocol treasury.
    /// @param  token_ The token to transfer the fees from.
    /// @param  feeAmount_ The amount of fees to transfer.
    function _processProtocolFeeViaTransfer(
        address treasury_,
        IERC20 token_,
        uint feeAmount_
    ) internal {
        // skip protocol fee collection if fee is 0
        if (feeAmount_ > 0) {
            _validateRecipient(treasury_);

            // transfer fee amount
            token_.safeTransfer(treasury_, feeAmount_);
            emit IModule_v1.ProtocolFeeTransferred(
                address(token_), treasury_, feeAmount_
            );
        }
    }

    /// @dev    Validates the recipient address.
    function _validateRecipient(address _receiver) internal view {
        if (_receiver == address(0) || _receiver == address(this)) {
            revert Module__DepositVault__InvalidRecipient();
        }
    }
}
