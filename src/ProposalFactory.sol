// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Dependencies
import {Clones} from "@oz/proxy/Clones.sol";

// Interfaces
import {IAuthorizer} from "src/interfaces/IAuthorizer.sol";
import {IProposal} from "src/interfaces/IProposal.sol";

contract ProposalFactory {
    address public immutable implementation;
    address public immutable moduleFactory;

    mapping(address => uint) private _idPerDeployer;
    uint private _proposalId;

    constructor(address implementation_, address moduleFactory_) {
        implementation = implementation_;
        moduleFactory = moduleFactory_;
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    function createProposal(
        address[] memory funders,
        bytes32[] memory moduleIds,
        bytes[] memory moduleData,
        IAuthorizer authorizer
    )
        external
    {
        _createProposal(funders, modules, authorizer);
    }

    //--------------------------------------------------------------------------
    // Public View Functions

    function predictProposalAddress() external view returns (address) {
        address predicted = Clones.predictDeterministicAddress(
            implementation, // @todo mp: Is arg implementation correct?
            _peekSalt(msg.sender),
            address(this)
        );

        return predicted;
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    function _createProposal(
        address[] memory funders,
        bytes32[] memory moduleIds,
        bytes[] memory moduleData,
        IAuthorizer authorizer
    )
        internal
        returns (address)
    {
        // Deploy each module.
        address[] modules = address[](moduleIds.length);
        for (uint i; i < moduleIds.length; i++) {
            address module =
                moduleFactory.createModule(moduleIds[i], moduleData[i]);

            modules[i] = module;
        }

        // Deploy, initialize and return proposal.
        address clone =
            Clones.cloneDeterministic(implementation, _useSalt(msg.sender));

        IProposal(clone).initialize(
            _useProposalId(), funders, modules, authorizer
        );

        return clone;
    }

    function _peekSalt(address from) internal view returns (bytes32) {
        uint id = _idPerDeployer[from];

        return bytes32(keccak256(abi.encodePacked(id, from)));
    }

    function _useSalt(address from) internal returns (bytes32) {
        bytes32 salt = _peekSalt(from);

        _idPerDeployer[from]++;

        return salt;
    }

    function _useProposalId() internal returns (uint) {
        uint id = _proposalId;

        _proposalId++;

        return id;
    }
}
