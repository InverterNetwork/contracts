// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Internal Dependencies
import {Module_v1} from "src/modules/base/Module_v1.sol";
import {IReservePool_v1} from
    "src/modules/fundingManager/extensions/interfaces/IReservePool_v1.sol";

// External Dependencies
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

/// @title Reserve pool
/// @notice Pool holding the spreads between mint and burn.

/**
 * @title   Reserve Pool //@note do we really wanna call it Reserve Pool?
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
contract ReservePool_v1 is IReservePool_v1, Module_v1 {
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(Module_v1)
        returns (bool)
    {
        return interfaceId == type(IReservePool_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Mutating Functions

    /// @inheritdoc IReservePool_v1
    function withdraw(address tok, uint amt, address dst)
        external
        //@note do we want to keep it that way? Special role?
        onlyOrchestratorAdmin
    {
        // if tok == address(0) then send eth //@note do we want to enable sending eth?
        if (tok == address(0)) {
            (bool success,) = dst.call{value: amt}("");
            require(success);
            emit EthWithdrawn(dst, amt);
        }
        // else send tokens
        else {
            IERC20(tok).safeTransfer(dst, amt);
            emit TokensWithdrawn(tok, dst, amt);
        }
    }
}
