// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Dependencies
import {Module_v1} from "src/modules/base/Module_v1.sol";
import {IFM_EXT_TokenVault_v1} from
    "src/modules/fundingManager/extensions/interfaces/IFM_EXT_TokenVault_v1.sol";

// External Dependencies
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

/**
 * @title   Inverter Token Vault
 *
 * @notice  Pool holding token Reserves for later use.
 *
 * @dev     Funds can be withdrawn by OrchestratorAdmin
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
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
    modifier validAmount(uint amt_) {
        _onlyValidAmount(amt_);
        _;
    }

    //--------------------------------------------------------------------------
    // Mutating Functions

    /// @inheritdoc IFM_EXT_TokenVault_v1
    function withdraw(address tok_, uint amt_, address dst_)
        external
        virtual
        //@note do we want to keep it that way? Special role?
        onlyOrchestratorAdmin
        validAddress(tok_)
        validAmount(amt_)
        validAddress(dst_)
    {
        IERC20(tok_).safeTransfer(dst_, amt_);
        emit TokensWithdrawn(tok_, dst_, amt_);
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @dev Revert given the amount is invalid, i.e. equal to 0.
    function _onlyValidAmount(uint amt_) internal pure {
        if (amt_ == 0) {
            revert Module__FM_EXT_TokenVault__InvalidAmount();
        }
    }
}
