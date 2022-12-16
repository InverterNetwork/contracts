// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {ERC20} from "@oz/token/ERC20/ERC20.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

import {IElasticTokenWrapper} from "src/proposal/token/IElasticTokenWrapper.sol";

/**
 * IMPORTANT:
 *  - underlier    -> The elastic (rebasing) token that is being wrapped
 *  - token        -> The token being created, i.e. address(this)
 *  - uAmount      -> An amount of underlier tokens
 *  - Amount       -> An amount of tokens
 *  - uTotalSupply -> The total supply of the underlier token
 */
contract ElasticTokenWrapper is IElasticTokenWrapper, ERC20 {
    using SafeERC20 for IERC20;

    uint public constant MAX_TOKEN_SUPPLY = 10_000_000e18; // 10M

    IERC20 private immutable _underlier;

    constructor(IERC20 underlier, string memory name_, string memory symbol_)
        ERC20(name_, symbol_)
    {
        _underlier = underlier;
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @dev Deposits `uAmount` of underlier tokens and mints tokens to `to`.
    /// @return Returns the amount of tokens minted.
    function depositFor(address to, uint uAmount) external returns (uint) {
        uint amount = _fromUnderlier(uAmount, _uTotalSupply());
        _deposit(msg.sender, to, uAmount, amount);
        return amount;
    }

    /// @dev Burns `amount` of tokens and sends underlier tokens to `to`.
    /// @return Returns the amount of underlier tokens send.
    function burnTo(address to, uint amount) external returns (uint) {
        uint uAmount = _toUnderlier(amount, _uTotalSupply());
        _withdraw(msg.sender, to, uAmount, amount);
        return uAmount;
    }

    //--------------------------------------------------------------------------
    // Public View Functions

    function underlying() external view returns (IERC20) {
        return _underlier;
    }

    function totalUnderlying() external view returns (uint) {
        return _toUnderlier(totalSupply(), _uTotalSupply());
    }

    function balanceOfUnderlying(address owner) external view returns (uint) {
        return _toUnderlier(balanceOf(owner), _uTotalSupply());
    }

    function underlyingToToken(uint uAmount) external view returns (uint) {
        uint uTotalSupply = _uTotalSupply();

        if (uTotalSupply == 0) {
            revert ElasticTokenWrapper__TotalSupplyOfUnderlierIsZero();
        }

        return _fromUnderlier(uAmount, _uTotalSupply());
    }

    function tokenToUnderlying(uint amount) external view returns (uint) {
        return _toUnderlier(amount, _uTotalSupply());
    }

    //--------------------------------------------------------------------------
    // Private Mutating Functions

    function _deposit(address from, address to, uint uAmount, uint amount)
        private
    {
        _underlier.safeTransferFrom(from, address(this), uAmount);

        _mint(to, amount);
    }

    function _withdraw(address from, address to, uint uAmount, uint amount)
        private
    {
        _burn(from, amount);

        _underlier.safeTransfer(to, uAmount);
    }

    //--------------------------------------------------------------------------
    // Private View Functions

    function _uTotalSupply() private view returns (uint) {
        return _underlier.totalSupply();
    }

    function _fromUnderlier(uint uAmount, uint uSupply)
        private
        pure
        returns (uint)
    {
        return (uAmount * MAX_TOKEN_SUPPLY) / uSupply;
    }

    function _toUnderlier(uint amount, uint uSupply)
        private
        pure
        returns (uint)
    {
        return (amount * uSupply) / MAX_TOKEN_SUPPLY;
    }
}
