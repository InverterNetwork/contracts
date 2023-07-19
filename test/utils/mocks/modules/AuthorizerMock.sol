// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {Module, IModule, IProposal} from "src/modules/base/Module.sol";

import {IAuthorizer} from "src/modules/authorizer/IAuthorizer.sol";
import {IRoleAuthorizer} from "src/modules/authorizer/IRoleAuthorizer.sol";

contract AuthorizerMock is IRoleAuthorizer, Module {
    mapping(address => bool) private _authorized;
    mapping(bytes32 => mapping(address => bool)) private _roleAuthorized;

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

    function isAuthorized(address who) external view returns (bool) {
        return _authorized[who] || _allAuthorized;
    }

    //IRoleAuthorizer

    function isAuthorized(uint8 role, address who)
        external
        view
        returns (bool)
    {
        return _authorized[who]
            || _roleAuthorized[generateRoleId(msg.sender, role)][who]
            || _allAuthorized;
    }

    function generateRoleId(address module, uint8 role)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(module, role));
    }

    function grantRoleFromModule(uint8 role, address target) external {
        _roleAuthorized[generateRoleId(msg.sender, role)][target] = true;
    }

    function revokeRoleFromModule(uint8 role, address target) external {
        _roleAuthorized[generateRoleId(msg.sender, role)][target] = false;
    }

    function toggleModuleSelfManagement() external {}

    function transferAdminRole(bytes32, bytes32) external {}

    function burnAdminRole(uint8) external {}

    //IAccessControlUpgradeable

    function getRoleAdmin(bytes32) external pure returns (bytes32) {
        return bytes32("");
    }

    function getRoleMember(bytes32, uint) external pure returns (address) {
        return address(0);
    }

    function getRoleMemberCount(bytes32) external pure returns (uint) {
        return 0;
    }

    function grantRole(bytes32, address) external {}

    function hasRole(bytes32, address) external pure returns (bool) {
        return false;
    }

    function revokeRole(bytes32, address) external pure {}

    function renounceRole(bytes32, address) external pure {}
}
