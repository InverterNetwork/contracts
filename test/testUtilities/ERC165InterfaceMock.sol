// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

contract ERC165InterfaceMock is ERC165Upgradeable {
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC165Upgradeable)
        returns (bool)
    {
        for (uint i = 0; i < interfaceIds.length; i++) {
            if (interfaceIds[i] == interfaceId) {
                return true;
            }
        }
        return super.supportsInterface(interfaceId);
    }

    bytes4[] public interfaceIds;

    function registerInterface(bytes4 interfaceId) external {
        interfaceIds.push(interfaceId);
    }

    function unregisterInterface(bytes4 interfaceId) external {
        for (uint i = 0; i < interfaceIds.length; i++) {
            if (interfaceIds[i] == interfaceId) {
                interfaceIds[i] = interfaceIds[interfaceIds.length - 1];
                interfaceIds.pop();
                return;
            }
        }
    }
}
