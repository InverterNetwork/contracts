// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IModule_v1} from "src/modules/base/IModule_v1.sol";

/**
 * @title   Inverter Metadata Library
 *
 * @dev     Provides common functions for {IModule_v1}'s Metadata type.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 */
library LibMetadata {
    /// @dev    Returns the identifier for given metadata.
    /// @param  metadata The metadata.
    /// @return The metadata's identifier.
    function identifier(IModule_v1.Metadata memory metadata)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(metadata.majorVersion, metadata.url, metadata.title)
        );
    }

    /// @dev	Returns whether the given metadata is valid.
    /// @param  metadata The metadata.
    /// @return True if metadata valid, false otherwise.
    function isValid(IModule_v1.Metadata memory metadata)
        internal
        pure
        returns (bool)
    {
        // Invalid if url empty.
        if (bytes(metadata.url).length == 0) {
            return false;
        }

        // Invalid if title empty.
        if (bytes(metadata.title).length == 0) {
            return false;
        }

        // Invalid if version is v0.0.0.
        if (
            metadata.majorVersion == 0 && metadata.minorVersion == 0
                && metadata.patchVersion == 0
        ) {
            return false;
        }

        return true;
    }
}
