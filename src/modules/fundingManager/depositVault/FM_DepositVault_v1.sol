// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {IFM_DepositVault_v1} from
    "@fm/depositVault/interfaces/IFM_DepositVault_v1.sol";

// Internal Dependencies
import {Module_v1} from "src/modules/base/Module_v1.sol";

import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";

// External Interfaces
import {
    IERC20,
    IERC20Metadata
} from "@oz/token/ERC20/extensions/IERC20Metadata.sol";

// External Dependencies
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {Strings} from "@oz/utils/Strings.sol";

/**
 * @title   Deposit Vault Funding Manager
 *
 * @notice  This contract allows users to deposit tokens that fund the workflow.
 *
 * @dev     Implements {IFundingManager_v1} interface.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
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
    // Modifier

    /// @dev Checks if the given Address is valid.
    modifier validAddress(address to) {
        if (to == address(0) || to == address(this)) {
            revert Module__FundingManager__InvalidAddress();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    /// @dev The token that is deposited.
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
    ) external override initializer {
        address orchestratorTokenAddress = abi.decode(configData, (address));
        _token = IERC20(orchestratorTokenAddress);
    }

    /// @inheritdoc IFundingManager_v1
    function token() public view returns (IERC20) {
        return _token;
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IFM_DepositVault_v1
    function deposit(uint amount) external {
        _deposit(_msgSender(), amount);
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
    // Internal Mutating Functions

    /// @notice Deposits a specified amount of tokens into the contract
    /// @dev    Reverts if attempting self-deposits
    /// @param from The address from which the tokens are taken.
    /// @param amount The number of tokens to deposit.
    function _deposit(address from, uint amount) internal {
        token().safeTransferFrom(from, address(this), amount);

        emit Deposit(from, amount);
    }

    /// @dev Transfers orchestrator tokens to the specified address.
    /// @param to The address to transfer to.
    /// @param amount The amount of tokens to transfer.
    function _transferOrchestratorToken(address to, uint amount) internal {
        token().safeTransfer(to, amount);

        emit TransferOrchestratorToken(to, amount);
    }
}
