// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal
import {Module_v1} from "src/modules/base/Module_v1.sol";
import {IFM_EXT_TokenVault_v1} from
    "src/modules/fundingManager/extensions/interfaces/IFM_EXT_TokenVault_v1.sol";

// External
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

/**
 * @title   Inverter Token Vault
 *
 * @notice  Vault holding token reserves for later use.
 *
 * @dev     Funds can be withdrawn by the orchestrator admin.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @author  Inverter Network
 */
contract FM_EXT_TokenVault_v1 is IFM_EXT_TokenVault_v1, Module_v1 {
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(Module_v1)
        returns (bool)
    {
        return interfaceId == type(IFM_EXT_TokenVault_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Modifiers

    /// @dev    Modifier to guarantee the amount is valid.
    modifier validAmount(uint amount_) {
        _onlyValidAmount(amount_);
        _;
    }

    //--------------------------------------------------------------------------
    // Mutating Functions

    /// @inheritdoc IFM_EXT_TokenVault_v1
    function withdraw(address token_, uint amount_, address recipient_)
        external
        virtual
        onlyOrchestratorAdmin
        validAddress(token_)
        validAmount(amount_)
        validAddress(recipient_)
    {
        IERC20(token_).safeTransfer(recipient_, amount_);
        emit TokensWithdrawn(token_, recipient_, amount_);
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @notice Ensure that the amount is valid.
    /// @dev    Reverts if the amount is invalid, i.e. zero.
    /// @param  amount_ The amount to validate.
    function _onlyValidAmount(uint amount_) internal pure {
        if (amount_ == 0) {
            revert Module__FM_EXT_TokenVault__InvalidAmount();
        }
    }
}
