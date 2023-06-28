// // SPDX-License-Identifier: LGPL-3.0-only
// pragma solidity 0.8.19;
// // External Libraries

// import {AccessControlEnumerableUpgradeable} from
//     "@oz-up/access/AccessControlEnumerableUpgradeable.sol";
// import {Module, IModule} from "src/modules/base/Module.sol";
// import {IProposal} from "src/proposal/IProposal.sol";
// import {IRoleAuthorizer} from "./RoleAuthorizer.sol";

// import "forge-std/console.sol";

// contract TokenGatedRoleAuthorizer is
//     RoleAuthorizer,
//     AccessControlEnumerableUpgradeable,
//     Module
// {
//     /*
//     * This Module expands on the RoleAuthorizer by adding the possibility to set a role as "Token-Gated"
//     * Instead of whitelisting a user address, the whitelisted addresses will correspond to a token address, and on authotrization the contract will check on ownership
//     * of one of the specifed tokens.
//     */

//     mapping(bytes32 => bool) isTokenGated;
//     mapping(bytes32 => uint) thresholdMap;

//     modifier onlyEmptyRole(bytes32 role) {
//         //Check that the role is empty
//         if (getRoleMemberCount(role) != 0) {
//             // TODO make real error;
//             revert("Role is not empty");
//         }
//         _;
//     }

//     modifier onlyTokenGatedRole(bytes32 role) {
//         //Check that the role is empty
//         if (!isTokenGated[role]) {
//             // TODO make real error;
//             revert("Role is not token-gated");
//         }
//         _;
//     }

//     function toggleTokenGated(bytes memory role)
//         public
//         onlyModule
//         onlySelfManaged
//         onlyEmptyRole(role)
//     {
//         isTokenGated[role] = !isTokenGated[role];
//     }

//     /// @dev This function does not validate the threshold. It is technically possible to set a threshold above the total supply of the token.
//     function setThreshold(bytes32 role, address token, uint threshold)
//         public
//         onlyTokenGatedRole(role)
//     {
//         //check that the caller is either the module itself or the role admin
//         if (
//             !proposal().isModule(_msgSender())
//                 && !_checkRole(getRoleAdmin(role))
//         ) {
//             // TODO make real error;
//             revert("not allowed to set threshold");
//         }

//         bytes32 id = keccak256(abi.encodePacked(role, token));
//         thresholdMap[id] = threshold;
//     }

//     function isAuthorized(uint8 role, address who)
//         public
//         view
//         override
//         returns (bool)
//     {
//         //Note: since it uses msgSender to generate ID, this should only be used by modules. Users should call hasRole()
//         bytes32 roleId;
//         // If the module uses its own roles, check if account has the role.
//         // else check if account has role in proposal
//         if (selfManagedModules[_msgSender()]) {
//             //generate role hash
//              roleId = generateRoleId(_msgSender(), role);
//             //check if token gated:
//             if (isTokenGated[roleId]) {
//                 // check if it qualifies for  token ownership
//                 return hasTokenRole(role, who);
//             } else {
//                 // regular module role check
//                 return hasRole(roleId, who);
//             }
//         } else {
//             //check if in global roles
//             roleId = generateRoleId(address(proposal()), role);
//             return hasRole(roleId, who);
//         }
//     }

//     // @dev override for simpler queries.
//     function hasRole(address module, uint8 role, address who)
//         public
//         view
//         override
//         returns (bool)
//     {
//         //Note: since it uses msgSender to generate ID, this should only be used by modules. Users should call hasRole()
//         bytes32 roleId;
//         // If the module uses its own roles, check if account has the role.
//         // else check if account has role in proposal
//         if (selfManagedModules[module]) {
//             //generate role hash
//              roleId = generateRoleId(module, role);
//             //check if token gated:
//             if (isTokenGated[roleId]) {
//                 // check if it qualifies for  token ownership
//                 return hasTokenRole(role, who);
//             } else {
//                 // regular module role check
//                 return hasRole(roleId, who);
//             }
//         } else {
//             //check if in global roles
//             roleId = generateRoleId(address(proposal()), role);
//             return hasRole(roleId, who);
//         }
//     }

//     function hasTokenRole(bytes role, address who) public view returns (bool) {
//         //get list of role addresses
//         // loop thorugh them and check for balance > threshold
//     }
// }
