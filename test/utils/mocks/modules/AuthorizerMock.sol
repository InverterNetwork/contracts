// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {Module, IModule, IProposal} from "src/modules/base/Module.sol";

import {IAuthorizer} from "src/modules/IAuthorizer.sol";

contract AuthorizerMock is IAuthorizer, Module {
    mapping(address => bool) private _authorized;

    bool private _allAuthorized;

    function setIsAuthorized(address who, bool to) external {
        _authorized[who] = to;
    }

    function setAllAuthorized(bool to) external {
        _allAuthorized = to;
    }

    //--------------------------------------------------------------------------
    // IModule Functions

    function init(
        IProposal proposal_,
        Metadata memory metadata,
        bytes memory configdata
    ) public override(Module) initializer {
        __Module_init(proposal_, metadata);

        // Read first authorized address from configdata.
        address authorized = abi.decode(configdata, (address));
        require(authorized != address(0), "Zero address can not be authorized");

        _authorized[authorized] = true;
    }

    //--------------------------------------------------------------------------
    // IAuthorizer Functions

    function isAuthorized(address who, bytes32 role) external view returns (bool) {
        return _authorized[who] || _allAuthorized;
    }
}
