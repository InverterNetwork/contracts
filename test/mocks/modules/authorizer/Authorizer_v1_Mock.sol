// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IAuthorizer_v1} from "@aut/IAuthorizer_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {IOrchestrator_v2} from
    "src/orchestrator/interfaces/IOrchestrator_v2.sol";

import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

contract Authorizer_v1_Mock is IAuthorizer_v1, IModule_v1, ERC165Upgradeable {
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165Upgradeable)
        returns (bool)
    {
        return interfaceId == type(IAuthorizer_v1).interfaceId
            || interfaceId == type(IModule_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }
    // ------------------------------------------------------------------------
    // IAuthorizer_v1 Functions

    function checkForRole(bytes32, address) external view returns (bool) {
        return false;
    }

    function generateRoleId(address, bytes32) external pure returns (bytes32) {
        return bytes32(0);
    }

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

    function transferAdminRole(bytes32, bytes32) external pure {
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

    function getAdminRole() external pure returns (bytes32) {
        return bytes32(0);
    }

    // ------------------------------------------------------------------------
    // IAccessControlEnumerable Functions

    function getRoleMember(bytes32, uint) external pure returns (address) {
        return address(0);
    }

    function getRoleMemberCount(bytes32) external pure returns (uint) {
        return 0;
    }

    // ------------------------------------------------------------------------
    // IAccessControl Functions

    function hasRole(bytes32, address) external view returns (bool) {
        return false;
    }

    function getRoleAdmin(bytes32) external pure returns (bytes32) {
        return bytes32(0);
    }

    function grantRole(bytes32, address) external pure {
        revert("Not implemented in Authorizer Mock");
    }

    function revokeRole(bytes32, address) external pure {
        revert("Not implemented in Authorizer Mock");
    }

    function renounceRole(bytes32, address) external pure {
        revert("Not implemented in Authorizer Mock");
    }

    // ------------------------------------------------------------------------
    // IModule_v1 Functions

    function init(IOrchestrator_v2, Metadata memory, bytes memory)
        public
        virtual
    {}

    function identifier() external view returns (bytes32) {
        return bytes32(0);
    }

    function version() external view returns (uint, uint, uint) {
        return (0, 0, 0);
    }

    function url() external view returns (string memory) {
        return "";
    }

    /// @notice Returns the module's title.
    /// @return The module's title.
    function title() external view returns (string memory) {
        return "";
    }

    function orchestrator() external view returns (IOrchestrator_v2) {
        return IOrchestrator_v2(address(0));
    }

    function grantModuleRole(bytes32, address) external {
        revert("Not implemented in Authorizer Mock");
    }

    function grantModuleRoleBatched(bytes32, address[] calldata) external {
        revert("Not implemented in Authorizer Mock");
    }

    function revokeModuleRole(bytes32, address) external {
        revert("Not implemented in Authorizer Mock");
    }

    function revokeModuleRoleBatched(bytes32, address[] calldata) external {
        revert("Not implemented in Authorizer Mock");
    }
}
