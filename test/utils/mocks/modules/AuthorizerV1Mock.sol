// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";

import {
    Module_v1,
    IModule_v1,
    IOrchestrator_v1
} from "src/modules/base/Module_v1.sol";

import {IAuthorizer_v1} from "@aut/IAuthorizer_v1.sol";

contract AuthorizerV1Mock is IAuthorizer_v1, Module_v1 {
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(Module_v1)
        returns (bool)
    {
        bytes4 interfaceId_IAuthorizer = type(IAuthorizer_v1).interfaceId;
        return interfaceId == interfaceId_IAuthorizer
            || super.supportsInterface(interfaceId);
    }

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
    // IModule_v1 Functions

    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) public override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata);

        // Read first authorized address from configData.
        address authorized = abi.decode(configData, (address));
        require(authorized != address(0), "Zero address can not be authorized");

        _authorized[authorized] = true;

        _roleAuthorized["0x00"][msg.sender] = true;
        _roleAuthorized["0x02"][msg.sender] = true;
    }

    function mockInit(bytes memory configData) public {
        // Read first authorized address from configData.
        address authorized = abi.decode(configData, (address));
        require(authorized != address(0), "Zero address can not be authorized");

        _authorized[authorized] = true;
    }

    //--------------------------------------------------------------------------
    // IAuthorizer_v1 Functions

    function generateRoleId(address module, bytes32 role)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(module, role));
    }

    function grantRoleFromModule(bytes32 role, address target) external {
        _roleAuthorized[generateRoleId(_msgSender(), role)][target] = true;
    }

    function grantRoleFromModuleBatched(
        bytes32 role,
        address[] calldata targets
    ) external {
        for (uint i = 0; i < targets.length; i++) {
            _roleAuthorized[generateRoleId(_msgSender(), role)][targets[i]] =
                true;
        }
    }

    function revokeRoleFromModule(bytes32 role, address target) external {
        _roleAuthorized[generateRoleId(_msgSender(), role)][target] = false;
    }

    function revokeRoleFromModuleBatched(
        bytes32 role,
        address[] calldata targets
    ) external {
        for (uint i = 0; i < targets.length; i++) {
            _roleAuthorized[generateRoleId(_msgSender(), role)][targets[i]] =
                false;
        }
    }

    function grantRole(bytes32 role, address who) public {
        _roleAuthorized[role][who] = true;
    }

    function hasRole(bytes32 role, address who) external view returns (bool) {
        return _authorized[who] || _roleAuthorized[role][who] || _allAuthorized;
    }

    function hasModuleRole(bytes32 role, address who)
        external
        view
        returns (bool)
    {
        bytes32 roleId = generateRoleId(_msgSender(), role);
        return
            _authorized[who] || _roleAuthorized[roleId][who] || _allAuthorized;
    }

    function checkRoleMembership(bytes32 role, address who)
        external
        view
        returns (bool)
    {
        return _roleAuthorized[role][who];
    }

    function revokeRole(bytes32 role, address who) public {
        _roleAuthorized[role][who] = false;
    }

    function getAdminRole() external pure returns (bytes32) {
        return "0x00";
    }

    function grantGlobalRole(bytes32 role, address target) external {
        bytes32 roleID = generateRoleId(address(orchestrator()), role);
        grantRole(roleID, target);
    }

    function revokeGlobalRole(bytes32 role, address target) external {
        bytes32 roleID = generateRoleId(address(orchestrator()), role);
        revokeRole(roleID, target);
    }

    //--------------------------------------------------------------------------
    // Functions left empty

    function grantGlobalRoleBatched(bytes32, address[] calldata)
        external
        pure
    {
        revert("Not implemented in Authorizer Mock");
    }

    function revokeGlobalRoleBatched(bytes32, address[] calldata)
        external
        pure
    {
        revert("Not implemented in Authorizer Mock");
    }

    function renounceRole(bytes32, address) external pure {
        revert("Not implemented in Authorizer Mock");
    }

    function transferAdminRole(bytes32, bytes32) external pure {
        revert("Not implemented in Authorizer Mock");
    }

    function burnAdminFromModuleRole(bytes32) external pure {
        revert("Not implemented in Authorizer Mock");
    }

    function getRoleAdmin(bytes32) external pure returns (bytes32) {
        return "0x00"; // In this mock, all roles have the owner as admin
    }

    function getRoleMember(bytes32, uint) external pure returns (address) {
        revert("Not implemented in Authorizer Mock");
    }

    function getRoleMemberCount(bytes32) external pure returns (uint) {
        revert("Not implemented in Authorizer Mock");
    }
}
