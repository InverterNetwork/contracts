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

    mapping(
        address caller
            => mapping(
                address target
                    => mapping(bytes4 functionSelector => bool permission)
            )
    ) internal _permissions;

    bool private _allAuthorized;
    address _defaultAdmin;

    function setDefaultAdmin(address who) external {
        _defaultAdmin = who;
    }

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

        _roleAuthorized[0x00][msg.sender] = true;

        _defaultAdmin = authorized;
    }

    function mockInit(bytes memory configData) public {
        // Read first authorized address from configData.
        address authorized = abi.decode(configData, (address));
        require(authorized != address(0), "Zero address can not be authorized");

        _authorized[authorized] = true;
    }

    // ========================================================================
    // Mock Overrides

    function grantRole(bytes32 role, address who) public {
        _roleAuthorized[role][who] = true;
    }

    function hasRole(bytes32 role, address who) external view returns (bool) {
        return _authorized[who] || _roleAuthorized[role][who] || _allAuthorized;
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

    function renounceRole(bytes32, address) external pure {
        revert("Not implemented in Authorizer Mock");
    }

    function getRoleAdmin(bytes32) external pure returns (bytes32) {
        return 0x00; // In this mock, all roles have the owner as admin
    }

    function getRoleMember(bytes32, uint) external pure returns (address) {
        revert("Not implemented in Authorizer Mock");
    }

    function getRoleMemberCount(bytes32) external pure returns (uint) {
        revert("Not implemented in Authorizer Mock");
    }

    // ========================================================================
    // Public Getter Functions

    // ------------------------------------------------------------------------
    // Getter -  Authorization

    function getPermissions(address, bytes4)
        external
        view
        returns (bytes32[] memory)
    {}

    function getLastAssignedRoleId()
        external
        view
        returns (uint lastAssignedRoleId_)
    {}

    function isRolePermissioned(address, bytes4, bytes32)
        external
        view
        returns (bool)
    {}

    function hasPermission(
        address caller_,
        address target_,
        bytes4 functionSelector_
    ) external view returns (bool) {
        if (_allAuthorized) {
            return true;
        }
        if (caller_ == _defaultAdmin) {
            return true;
        }
        return _permissions[caller_][target_][functionSelector_];
    }

    function setHasPermission(
        address caller_,
        address target_,
        bytes4 functionSelector_,
        bool to
    ) external {
        _permissions[caller_][target_][functionSelector_] = to;
    }

    // ------------------------------------------------------------------------
    // Getter -  Role Management

    function getAdminRole() external pure returns (bytes32) {
        return 0x00;
    }

    // ------------------------------------------------------------------------
    // Getter - Out of Order

    function checkForRole(bytes32 role, address who)
        external
        view
        returns (bool)
    {
        return _authorized[who] || _roleAuthorized[role][who] || _allAuthorized;
    }

    function generateRoleId(address module, bytes32 role)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(module, role));
    }

    // ========================================================================
    // Mutating Functions

    // ------------------------------------------------------------------------
    // Mutating - Authorization

    function addAccessPermission(address, bytes4, bytes32) external {}

    function removeAccessPermission(address, bytes4, bytes32) external {}

    // ------------------------------------------------------------------------
    // Mutating - Role Management

    function createRole(string memory, bytes32, address[] memory)
        external
        returns (bytes32)
    {}

    function labelRole(bytes32, string memory) external {}

    function transferAdminRole(bytes32, bytes32) external pure {
        revert("Not implemented in Authorizer Mock");
    }

    function burnRoleAdmin(bytes32) external pure {
        revert("Not implemented in Authorizer Mock");
    }

    // ------------------------------------------------------------------------
    // Mutating - Mixed Utility

    function createRoleAndAddAccessPermissions(
        string memory,
        bytes32,
        address[] memory,
        address[] memory,
        bytes4[][] memory
    ) external returns (bytes32) {}

    // ------------------------------------------------------------------------
    // Mutating - Out of Order

    function grantRoleFromModule(bytes32, address) external pure {
        revert("Not implemented in Authorizer Mock");
    }

    function grantRoleFromModuleBatched(bytes32, address[] calldata)
        external
        pure
    {
        revert("Not implemented in Authorizer Mock");
    }

    function revokeRoleFromModule(bytes32, address) external pure {
        revert("Not implemented in Authorizer Mock");
    }

    function revokeRoleFromModuleBatched(bytes32, address[] calldata)
        external
        pure
    {
        revert("Not implemented in Authorizer Mock");
    }

    function burnAdminFromModuleRole(bytes32) external pure {
        revert("Not implemented in Authorizer Mock");
    }

    function grantGlobalRole(bytes32, address) external pure {
        revert("Not implemented in Authorizer Mock");
    }

    function grantGlobalRoleBatched(bytes32, address[] calldata)
        external
        pure
    {
        revert("Not implemented in Authorizer Mock");
    }

    function revokeGlobalRole(bytes32, address) external pure {
        revert("Not implemented in Authorizer Mock");
    }

    function revokeGlobalRoleBatched(bytes32, address[] calldata)
        external
        pure
    {
        revert("Not implemented in Authorizer Mock");
    }
}
