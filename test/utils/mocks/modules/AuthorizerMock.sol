// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";

import {Module, IModule, IOrchestrator} from "src/modules/base/Module.sol";

import {IAuthorizer} from "src/modules/authorizer/IAuthorizer.sol";

contract AuthorizerMock is IAuthorizer, Module {
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

    constructor() Module(address(0)) {}

    function init(
        IOrchestrator orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) public override(Module) initializer {
        __Module_init(orchestrator_, metadata);

        // Read first authorized address from configData.
        address authorized = abi.decode(configData, (address));
        require(authorized != address(0), "Zero address can not be authorized");

        _authorized[authorized] = true;

        _roleAuthorized["0x01"][msg.sender] = true;
        _roleAuthorized["0x02"][msg.sender] = true;
    }

    function mockInit(bytes memory configData) public {
        // Read first authorized address from configData.
        address authorized = abi.decode(configData, (address));
        require(authorized != address(0), "Zero address can not be authorized");

        _authorized[authorized] = true;
    }

    //--------------------------------------------------------------------------
    // IAuthorizer Functions

    // Also accepts the owner role as authorized.
    /*     function isAuthorized(address who) external view returns (bool) {
        return _authorized[who] || _allAuthorized
            || _roleAuthorized[generateRoleId(address(orchestrator()), uint8(0))][who];
    }

    //IRoleAuthorizer

    function isAuthorized(uint8 role, address who)
        external
        view
        returns (bool)
    {
        return _authorized[who]
            || _roleAuthorized[generateRoleId(msg.sender, role)][who]
            || _roleAuthorized[generateRoleId(address(orchestrator()), uint8(0))][who]
            || _roleAuthorized[generateRoleId(address(orchestrator()), uint8(1))][who]
            || _allAuthorized;
    }
    */
    function generateRoleId(address module, bytes32 role)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(module, role));
    }

    function grantRoleFromModule(bytes32 role, address target) external {
        console.log(_msgSender());
        _roleAuthorized[generateRoleId(_msgSender(), role)][target] = true;
    }

    function revokeRoleFromModule(bytes32 role, address target) external {
        _roleAuthorized[generateRoleId(_msgSender(), role)][target] = false;
    }

    function toggleModuleSelfManagement() external {}

    function transferAdminRole(bytes32, bytes32) external {}

    function burnAdminFromModuleRole(bytes32) external {}

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

    function renounceRole(bytes32, address) external pure {}

    function getOwnerRole() external pure returns (bytes32) {
        return "0x01";
    }

    function getManagerRole() external pure returns (bytes32) {
        return "0x02";
    }

    /// @notice Grants a global role to a target
    /// @param role The role to grant
    /// @param target The address to grant the role to
    /// @dev Only the addresses with the Owner role should be able to call this function
    function grantGlobalRole(bytes32 role, address target) external {
        bytes32 roleID = generateRoleId(address(orchestrator()), role);
        grantRole(roleID, target);
    }

    /// @notice Revokes a global role from a target
    /// @param role The role to grant
    /// @param target The address to grant the role to
    /// @dev Only the addresses with the Owner role should be able to call this function
    function revokeGlobalRole(bytes32 role, address target) external {
        bytes32 roleID = generateRoleId(address(orchestrator()), role);
        revokeRole(roleID, target);
    }
}
