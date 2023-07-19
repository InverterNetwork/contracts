// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

//Internal Dependencies
import {ModuleTest, IModule, IProposal} from "test/modules/ModuleTest.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// SuT
import {
    MetadataManager, IMetadataManager
} from "src/modules/MetadataManager.sol";

contract MetadataManagerTest is ModuleTest {
    bool hasDependency;
    string[] dependencies = new string[](0);

    // SuT
    MetadataManager metadataManager;

    // Constants
    IMetadataManager.ManagerMetadata MANAGER_METADATA;
    IMetadataManager.ProposalMetadata PROPOSAL_METADATA;
    IMetadataManager.MemberMetadata[] TEAM_METADATA;

    function setUp() public {
        //Set up Preset Metadata
        MANAGER_METADATA = IMetadataManager.ManagerMetadata(
            "Name", address(0xBEEF), "TwitterHandle"
        );

        PROPOSAL_METADATA = IMetadataManager.ProposalMetadata(
            "Title",
            "DescriptionShort",
            "DescriptionLong",
            new string[](0),
            new string[](0)
        );

        PROPOSAL_METADATA.externalMedias.push("externalMedia1");
        PROPOSAL_METADATA.externalMedias.push("externalMedia2");
        PROPOSAL_METADATA.externalMedias.push("externalMedia3");

        PROPOSAL_METADATA.categories.push("category1");
        PROPOSAL_METADATA.categories.push("category2");
        PROPOSAL_METADATA.categories.push("category3");

        TEAM_METADATA.push(
            IMetadataManager.MemberMetadata(
                "Name", address(0xBEEF), "Something"
            )
        );

        //Add Module to Mock Proposal

        address impl = address(new MetadataManager());
        metadataManager = MetadataManager(Clones.clone(impl));

        _setUpProposal(metadataManager);

        //Init Module
        metadataManager.init(
            _proposal,
            _METADATA,
            abi.encode(
                MANAGER_METADATA,
                PROPOSAL_METADATA,
                TEAM_METADATA,
                hasDependency,
                dependencies
            )
        );
    }

    //--------------------------------------------------------------------------
    // Test: Initialization

    //This function also tests all the getters
    function testInit() public override(ModuleTest) {
        MANAGER_METADATA = IMetadataManager.ManagerMetadata(
            "newName", address(0x606), "newTwitterHandle"
        );

        PROPOSAL_METADATA = IMetadataManager.ProposalMetadata(
            "newTitle",
            "newDescriptionShort",
            "newDescriptionLong",
            new string[](0),
            new string[](0)
        );

        PROPOSAL_METADATA.externalMedias.push("newExternalMedia");

        PROPOSAL_METADATA.categories.push("newCategory1");

        TEAM_METADATA.push(
            IMetadataManager.MemberMetadata(
                "newName", address(0x606), "newSomething"
            )
        );

        //-----------------------
        // MANAGER_METADATA
        metadataManager.setManagerMetadata(MANAGER_METADATA);
        assertMetadataManagerManagerMetadataEqualTo(MANAGER_METADATA);

        //-----------------------
        // PROPOSAL_METADATA
        metadataManager.setProposalMetadata(PROPOSAL_METADATA);
        assertMetadataManagerProposalMetadataEqualTo(PROPOSAL_METADATA);

        //-----------------------
        // TEAM_METADATA
        metadataManager.setTeamMetadata(TEAM_METADATA);
        assertMetadataManagerTeamMetadataEqualTo(TEAM_METADATA);
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        metadataManager.init(_proposal, _METADATA, bytes(""));
    }

    function testSetter() public {
        //-----------------------
        // MANAGER_METADATA

        assertMetadataManagerManagerMetadataEqualTo(
            metadataManager.getManagerMetadata()
        );

        //-----------------------
        // PROPOSAL_METADATA

        assertMetadataManagerProposalMetadataEqualTo(
            metadataManager.getProposalMetadata()
        );

        //-----------------------
        // TEAM_METADATA

        assertMetadataManagerTeamMetadataEqualTo(
            metadataManager.getTeamMetadata()
        );
    }

    //--------------------------------------------------------------------------
    // Helper - Functions

    function assertMetadataManagerManagerMetadataEqualTo(
        IMetadataManager.ManagerMetadata memory ownerMetadata_
    ) private {
        assertEq(metadataManager.getManagerMetadata().name, ownerMetadata_.name);
        assertEq(
            metadataManager.getManagerMetadata().account, ownerMetadata_.account
        );
        assertEq(
            metadataManager.getManagerMetadata().twitterHandle,
            ownerMetadata_.twitterHandle
        );
    }

    function assertMetadataManagerProposalMetadataEqualTo(
        IMetadataManager.ProposalMetadata memory proposalMetadata_
    ) private {
        assertEq(
            metadataManager.getProposalMetadata().title, proposalMetadata_.title
        );
        assertEq(
            metadataManager.getProposalMetadata().descriptionShort,
            proposalMetadata_.descriptionShort
        );
        assertEq(
            metadataManager.getProposalMetadata().descriptionLong,
            proposalMetadata_.descriptionLong
        );

        assertEq(
            metadataManager.getProposalMetadata().externalMedias.length,
            proposalMetadata_.externalMedias.length
        );

        //asserted Length is equal
        uint len = proposalMetadata_.externalMedias.length;
        for (uint i = 0; i < len; ++i) {
            assertEq(
                proposalMetadata_.externalMedias[i],
                metadataManager.getProposalMetadata().externalMedias[i]
            );
        }

        assertEq(
            metadataManager.getProposalMetadata().categories.length,
            proposalMetadata_.categories.length
        );

        //asserted Length is equal
        len = proposalMetadata_.categories.length;
        for (uint i = 0; i < len; ++i) {
            assertEq(
                proposalMetadata_.categories[i],
                metadataManager.getProposalMetadata().categories[i]
            );
        }
    }

    function assertMetadataManagerTeamMetadataEqualTo(
        IMetadataManager.MemberMetadata[] memory teamMetadata_
    ) private {
        assertEq(metadataManager.getTeamMetadata().length, teamMetadata_.length);

        //asserted Length is equal
        uint len = teamMetadata_.length;
        for (uint i = 0; i < len; ++i) {
            assertMemberMetadataEqual(
                metadataManager.getTeamMetadata()[i], teamMetadata_[i]
            );
        }
    }

    function assertMemberMetadataEqual(
        IMetadataManager.MemberMetadata memory firstMemberMetadata,
        IMetadataManager.MemberMetadata memory secondMemberMetadata_
    ) private {
        assertEq(firstMemberMetadata.name, secondMemberMetadata_.name);
        assertEq(firstMemberMetadata.account, secondMemberMetadata_.account);
        assertEq(firstMemberMetadata.url, secondMemberMetadata_.url);
    }

    // =========================================================================
}
