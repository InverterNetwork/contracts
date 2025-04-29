// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import {IERC20} from "@oz/token/ERC20/IERC20.sol";

/**
 * @title NonStandardTokenMock
 * @dev Mock implementation of a non-standard ERC20 token that returns false on transfer
 *      instead of reverting. This is used to test error handling in the payment processor.
 */
contract NonStandardTokenMock is IERC20 {
    mapping(address => uint) private _balances;
    mapping(address => mapping(address => uint)) private _allowances;
    uint private _totalSupply;
    address private _failTransferTo;

    function setFailTransferTo(address recipient) external {
        _failTransferTo = recipient;
    }

    function mint(address account, uint amount) external {
        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function totalSupply() external view returns (uint) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint) {
        return _balances[account];
    }

    function transfer(address to, uint amount) external returns (bool) {
        if (to == _failTransferTo) {
            return false;
        }
        if (_balances[msg.sender] < amount) {
            return false;
        }
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender)
        external
        view
        returns (uint)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint amount)
        external
        returns (bool)
    {
        if (to == _failTransferTo) {
            return false;
        }
        if (_balances[from] < amount || _allowances[from][msg.sender] < amount)
        {
            return false;
        }
        _balances[from] -= amount;
        _balances[to] += amount;
        _allowances[from][msg.sender] -= amount;
        emit Transfer(from, to, amount);
        return true;
    }
}
