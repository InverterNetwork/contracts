// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";

//Internal Dependencies
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// SuT
import {
    MetadataManager_v1,
    IMetadataManager_v1
} from "src/modules/utils/MetadataManager_v1.sol";

contract MetadataManagerV1Test is ModuleTest {
    bool hasDependency;
    string[] dependencies = new string[](0);

    // SuT
    MetadataManager_v1 metadataManager;

    // Constants
    IMetadataManager_v1.ManagerMetadata MANAGER_METADATA;
    IMetadataManager_v1.OrchestratorMetadata ORCHESTRATOR_METADATA;
    IMetadataManager_v1.MemberMetadata[] TEAM_METADATA;

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when the owner metadata changed.
    event ManagerMetadataUpdated(
        string name, address account, string twitterHandle
    );

    /// @notice Event emitted when the orchestrator metadata changed.
    event OrchestratorMetadataUpdated(
        string title,
        string descriptionShort,
        string descriptionLong,
        string[] externalMedias,
        string[] categories
    );

    /// @notice Event emitted when the team metadata changed.
    event TeamMetadataUpdated(IMetadataManager_v1.MemberMetadata[] members);

    function setUp() public {
        //Set up Preset Metadata
        MANAGER_METADATA = IMetadataManager_v1.ManagerMetadata(
            "Name", address(0xBEEF), "TwitterHandle"
        );

        ORCHESTRATOR_METADATA = IMetadataManager_v1.OrchestratorMetadata(
            "Title",
            "DescriptionShort",
            "DescriptionLong",
            new string[](0),
            new string[](0)
        );

        ORCHESTRATOR_METADATA.externalMedias.push("externalMedia1");
        ORCHESTRATOR_METADATA.externalMedias.push("externalMedia2");
        ORCHESTRATOR_METADATA.externalMedias.push("externalMedia3");

        ORCHESTRATOR_METADATA.categories.push("category1");
        ORCHESTRATOR_METADATA.categories.push("category2");
        ORCHESTRATOR_METADATA.categories.push("category3");

        TEAM_METADATA.push(
            IMetadataManager_v1.MemberMetadata(
                "Name", address(0xBEEF), "Something"
            )
        );

        //Add Module to Mock Orchestrator_v1

        address impl = address(new MetadataManager_v1());
        metadataManager = MetadataManager_v1(Clones.clone(impl));

        _setUpOrchestrator(metadataManager);

        // Authorize this contract for the tests
        _authorizer.setIsAuthorized(address(this), true);

        //Init Module
        metadataManager.init(
            _orchestrator,
            _METADATA,
            abi.encode(MANAGER_METADATA, ORCHESTRATOR_METADATA, TEAM_METADATA)
        );
    }

    //--------------------------------------------------------------------------
    // Test: Initialization

    //This function also tests all the getters
    function testInit() public override(ModuleTest) {
        MANAGER_METADATA = IMetadataManager_v1.ManagerMetadata(
            "newName", address(0x606), "newTwitterHandle"
        );

        ORCHESTRATOR_METADATA = IMetadataManager_v1.OrchestratorMetadata(
            "newTitle",
            "newDescriptionShort",
            "newDescriptionLong",
            new string[](0),
            new string[](0)
        );

        ORCHESTRATOR_METADATA.externalMedias.push("newExternalMedia");

        ORCHESTRATOR_METADATA.categories.push("newCategory1");

        TEAM_METADATA.push(
            IMetadataManager_v1.MemberMetadata(
                "newName", address(0x606), "newSomething"
            )
        );

        //-----------------------
        // MANAGER_METADATA

        vm.expectEmit();
        emit ManagerMetadataUpdated(
            MANAGER_METADATA.name,
            MANAGER_METADATA.account,
            MANAGER_METADATA.twitterHandle
        );
        metadataManager.setManagerMetadata(MANAGER_METADATA);
        assertMetadataManagerManagerMetadataEqualTo(MANAGER_METADATA);

        //-----------------------
        // ORCHESTRATOR_METADATA

        vm.expectEmit();
        emit OrchestratorMetadataUpdated(
            ORCHESTRATOR_METADATA.title,
            ORCHESTRATOR_METADATA.descriptionShort,
            ORCHESTRATOR_METADATA.descriptionLong,
            ORCHESTRATOR_METADATA.externalMedias,
            ORCHESTRATOR_METADATA.categories
        );

        metadataManager.setOrchestratorMetadata(ORCHESTRATOR_METADATA);
        assertMetadataManagerOrchestratorMetadataEqualTo(ORCHESTRATOR_METADATA);

        //-----------------------
        // TEAM_METADATA

        /// @notice Event emitted when the team metadata changed.
        vm.expectEmit();
        emit TeamMetadataUpdated(TEAM_METADATA);
        metadataManager.setTeamMetadata(TEAM_METADATA);
        assertMetadataManagerTeamMetadataEqualTo(TEAM_METADATA);
    }

    function testSupportsInterface() public {
        assertTrue(
            metadataManager.supportsInterface(
                type(IMetadataManager_v1).interfaceId
            )
        );
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        metadataManager.init(_orchestrator, _METADATA, bytes(""));
    }

    function testInit2MetadataManager() public {
        // Attempting to call the init2 function with malformed data
        // SHOULD FAIL
        vm.expectRevert(
            IModule_v1.Module__NoDependencyOrMalformedDependencyData.selector
        );
        metadataManager.init2(_orchestrator, abi.encode(123));

        // Calling init2 for the first time with no dependency
        // SHOULD FAIL
        bytes memory dependencyData = abi.encode(hasDependency, dependencies);
        vm.expectRevert(
            IModule_v1.Module__NoDependencyOrMalformedDependencyData.selector
        );
        metadataManager.init2(_orchestrator, dependencyData);

        // Calling init2 for the first time with dependency = true
        // SHOULD PASS
        dependencyData = abi.encode(true, dependencies);
        metadataManager.init2(_orchestrator, dependencyData);

        // Attempting to call the init2 function again.
        // SHOULD FAIL
        vm.expectRevert(IModule_v1.Module__CannotCallInit2Again.selector);
        metadataManager.init2(_orchestrator, dependencyData);
    }

    function testSetter() public {
        //-----------------------
        // MANAGER_METADATA

        assertMetadataManagerManagerMetadataEqualTo(
            metadataManager.getManagerMetadata()
        );

        //-----------------------
        // ORCHESTRATOR_METADATA

        assertMetadataManagerOrchestratorMetadataEqualTo(
            metadataManager.getOrchestratorMetadata()
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
        IMetadataManager_v1.ManagerMetadata memory ownerMetadata_
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

    function assertMetadataManagerOrchestratorMetadataEqualTo(
        IMetadataManager_v1.OrchestratorMetadata memory orchestratorMetadata_
    ) private {
        assertEq(
            metadataManager.getOrchestratorMetadata().title,
            orchestratorMetadata_.title
        );
        assertEq(
            metadataManager.getOrchestratorMetadata().descriptionShort,
            orchestratorMetadata_.descriptionShort
        );
        assertEq(
            metadataManager.getOrchestratorMetadata().descriptionLong,
            orchestratorMetadata_.descriptionLong
        );

        assertEq(
            metadataManager.getOrchestratorMetadata().externalMedias.length,
            orchestratorMetadata_.externalMedias.length
        );

        //asserted Length is equal
        uint len = orchestratorMetadata_.externalMedias.length;
        for (uint i = 0; i < len; ++i) {
            assertEq(
                orchestratorMetadata_.externalMedias[i],
                metadataManager.getOrchestratorMetadata().externalMedias[i]
            );
        }

        assertEq(
            metadataManager.getOrchestratorMetadata().categories.length,
            orchestratorMetadata_.categories.length
        );

        //asserted Length is equal
        len = orchestratorMetadata_.categories.length;
        for (uint i = 0; i < len; ++i) {
            assertEq(
                orchestratorMetadata_.categories[i],
                metadataManager.getOrchestratorMetadata().categories[i]
            );
        }
    }

    function assertMetadataManagerTeamMetadataEqualTo(
        IMetadataManager_v1.MemberMetadata[] memory teamMetadata_
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
        IMetadataManager_v1.MemberMetadata memory firstMemberMetadata,
        IMetadataManager_v1.MemberMetadata memory secondMemberMetadata_
    ) private {
        assertEq(firstMemberMetadata.name, secondMemberMetadata_.name);
        assertEq(firstMemberMetadata.account, secondMemberMetadata_.account);
        assertEq(firstMemberMetadata.url, secondMemberMetadata_.url);
    }

    // =========================================================================
}
