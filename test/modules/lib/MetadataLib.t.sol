// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Internal Libraries
import {LibMetadata} from "src/modules/lib/LibMetadata.sol";

// Internal Interfaces
import {IModule} from "src/modules/base/IModule.sol";

/**
 * @dev Note that these tests are more of a specification than actual
 *      functionality tests.
 */
contract LibMetadataTest is Test {
    function setUp() public {}

    function testIdentifierIsHashOfMajorVersionAndGitURL(
        IModule.Metadata memory data
    ) public {
        bytes32 got = LibMetadata.identifier(data);
        bytes32 want =
            keccak256(abi.encodePacked(data.majorVersion, data.gitURL));

        assertEq(got, want);
    }

    function testMetadataInvalidIfGitURLEmpty(uint majorVersion) public {
        IModule.Metadata memory data = IModule.Metadata(majorVersion, "");

        assertTrue(!LibMetadata.isValid(data));
    }
}
