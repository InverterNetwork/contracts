// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

// Internal Libraries
import {LibMetadata} from "src/modules/lib/LibMetadata.sol";

// Internal Interfaces
import {IModule} from "src/modules/base/IModule.sol";

contract LibMetadataTest is Test {
    function setUp() public {}

    /// @dev The identifier is defined as the hash of the major version, url
    ///      and title.
    function testIdentifier(IModule.Metadata memory data) public {
        bytes32 got = LibMetadata.identifier(data);
        bytes32 want =
            keccak256(abi.encodePacked(data.majorVersion, data.url, data.title));

        assertEq(got, want);
    }

    function testMetadataInvalidIfURLEmpty(uint majorVersion, uint minorVersion)
        public
    {
        IModule.Metadata memory data =
            IModule.Metadata(majorVersion, minorVersion, "", "title");

        assertTrue(!LibMetadata.isValid(data));
    }

    function testMetadataInvalidIfTitleEmpty(
        uint majorVersion,
        uint minorVersion
    ) public {
        IModule.Metadata memory data =
            IModule.Metadata(majorVersion, minorVersion, "url", "");

        assertTrue(!LibMetadata.isValid(data));
    }
}
