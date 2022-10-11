// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IModule} from "src/interfaces/IModule.sol";

/**
 * @title Metadata Library
 *
 * @dev Provides common functions {IModule}'s Metadata type.
 *
 * @author byterocket
 */
library MetadataLib {
    /// @dev Returns the identifier for given metadata.
    /// @param metadata The metadata.
    /// @return The metadata's identifier.
    function identifier(IModule.Metadata memory metadata)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(metadata.majorVersion, metadata.gitURL)
        );
    }

    /// @dev Returns whether the given metadata is valid.
    /// @param metadata The metadata.
    /// @return True if metadata valid, false otherwise.
    function isValid(IModule.Metadata memory metadata)
        internal
        pure
        returns (bool)
    {
        // Invalid if git url empty.
        if (bytes(metadata.gitURL).length == 0) {
            return false;
        }

        return true;
    }
}
