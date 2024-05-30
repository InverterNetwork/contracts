// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

// Internal Libraries
import {LibMetadata} from "src/modules/lib/LibMetadata.sol";

// Internal Interfaces
import {IModule_v1} from "src/modules/base/IModule_v1.sol";

contract LibMetadataTest is Test {
    function setUp() public {}

    /// @dev The identifier is defined as the hash of the major version, url
    ///      and title.
    function testIdentifier(IModule_v1.Metadata memory data) public {
        bytes32 got = LibMetadata.identifier(data);
        bytes32 want =
            keccak256(abi.encode(data.majorVersion, data.url, data.title));

        assertEq(got, want);
    }

    function testMetadataIsValid(
        uint majorVersion,
        uint minorVersion,
        string memory url,
        string memory title
    ) public {
        vm.assume(majorVersion != 0 || minorVersion != 0);
        vm.assume(bytes(url).length != 0);
        vm.assume(bytes(title).length != 0);

        IModule_v1.Metadata memory data =
            IModule_v1.Metadata(majorVersion, minorVersion, url, title);

        assertTrue(LibMetadata.isValid(data));
    }

    function testMetadataInvalidIfURLEmpty(uint majorVersion, uint minorVersion)
        public
    {
        vm.assume(majorVersion != 0 || minorVersion != 0);
        IModule_v1.Metadata memory data =
            IModule_v1.Metadata(majorVersion, minorVersion, "", "title");

        assertTrue(!LibMetadata.isValid(data));
    }

    function testMetadataInvalidIfTitleEmpty(
        uint majorVersion,
        uint minorVersion
    ) public {
        vm.assume(majorVersion != 0 || minorVersion != 0);

        IModule_v1.Metadata memory data =
            IModule_v1.Metadata(majorVersion, minorVersion, "url", "");

        assertTrue(!LibMetadata.isValid(data));
    }

    function testMetadataInvalidIfVersionOnlyZero(
        uint majorVersion,
        uint minorVersion
    ) public {
        IModule_v1.Metadata memory data =
            IModule_v1.Metadata(majorVersion, minorVersion, "url", "title");
        if (majorVersion == 0 && minorVersion == 0) {
            assertFalse(LibMetadata.isValid(data));
        } else {
            assertTrue(LibMetadata.isValid(data));
        }
    }
}
