// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";

//Internal Dependencies
import {ModuleTest, IModule, IOrchestrator} from "test/modules/ModuleTest.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// SuT
import {
    MetadataManager,
    IMetadataManager
} from "src/modules/utils/MetadataManager.sol";

contract MetadataManagerTest is ModuleTest {
    bool hasDependency;
    string[] dependencies = new string[](0);

    // SuT
    MetadataManager metadataManager;

    // Constants
    IMetadataManager.ManagerMetadata MANAGER_METADATA;
    IMetadataManager.OrchestratorMetadata ORCHESTRATOR_METADATA;
    IMetadataManager.MemberMetadata[] TEAM_METADATA;

    function setUp() public {
        //Set up Preset Metadata
        MANAGER_METADATA = IMetadataManager.ManagerMetadata(
            "Name", address(0xBEEF), "TwitterHandle"
        );

        ORCHESTRATOR_METADATA = IMetadataManager.OrchestratorMetadata(
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
            IMetadataManager.MemberMetadata(
                "Name", address(0xBEEF), "Something"
            )
        );

        //Add Module to Mock Orchestrator

        address impl = address(new MetadataManager());
        metadataManager = MetadataManager(Clones.clone(impl));

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
        MANAGER_METADATA = IMetadataManager.ManagerMetadata(
            "newName", address(0x606), "newTwitterHandle"
        );

        ORCHESTRATOR_METADATA = IMetadataManager.OrchestratorMetadata(
            "newTitle",
            "newDescriptionShort",
            "newDescriptionLong",
            new string[](0),
            new string[](0)
        );

        ORCHESTRATOR_METADATA.externalMedias.push("newExternalMedia");

        ORCHESTRATOR_METADATA.categories.push("newCategory1");

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
        // ORCHESTRATOR_METADATA
        metadataManager.setOrchestratorMetadata(ORCHESTRATOR_METADATA);
        assertMetadataManagerOrchestratorMetadataEqualTo(ORCHESTRATOR_METADATA);

        //-----------------------
        // TEAM_METADATA
        metadataManager.setTeamMetadata(TEAM_METADATA);
        assertMetadataManagerTeamMetadataEqualTo(TEAM_METADATA);
    }

    function testSupportsInterface(bytes4 interfaceId) public {
        bool shouldBeInterface = type(IMetadataManager).interfaceId
            == interfaceId || type(IModule).interfaceId == interfaceId
            || type(IERC165).interfaceId == interfaceId;

        assertEq(
            shouldBeInterface, metadataManager.supportsInterface(interfaceId)
        );
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        metadataManager.init(_orchestrator, _METADATA, bytes(""));
    }

    function testInit2MetadataManager() public {
        // Attempting to call the init2 function with malformed data
        // SHOULD FAIL
        vm.expectRevert(
            IModule.Module__NoDependencyOrMalformedDependencyData.selector
        );
        metadataManager.init2(_orchestrator, abi.encode(123));

        // Calling init2 for the first time with no dependency
        // SHOULD FAIL
        bytes memory dependencyData = abi.encode(hasDependency, dependencies);
        vm.expectRevert(
            IModule.Module__NoDependencyOrMalformedDependencyData.selector
        );
        metadataManager.init2(_orchestrator, dependencyData);

        // Calling init2 for the first time with dependency = true
        // SHOULD PASS
        dependencyData = abi.encode(true, dependencies);
        metadataManager.init2(_orchestrator, dependencyData);

        // Attempting to call the init2 function again.
        // SHOULD FAIL
        vm.expectRevert(IModule.Module__CannotCallInit2Again.selector);
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

    function assertMetadataManagerOrchestratorMetadataEqualTo(
        IMetadataManager.OrchestratorMetadata memory orchestratorMetadata_
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
