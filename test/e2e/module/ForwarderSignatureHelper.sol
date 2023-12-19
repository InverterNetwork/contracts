// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Dependencies
import {MinimalForwarder} from "@oz/metatx/MinimalForwarder.sol";

contract ForwarderSignatureHelper {
    address private immutable forwarder;
    bytes32 private immutable _CACHED_DOMAIN_SEPARATOR;
    uint private immutable _CACHED_CHAIN_ID;
    address private immutable _CACHED_THIS;

    bytes32 private immutable _HASHED_NAME;
    bytes32 private immutable _HASHED_VERSION;
    bytes32 private immutable _TYPE_HASH;
    bytes32 private immutable _minimal_Forwarder_TYPE_HASH;

    //Domain Seperator
    constructor(address _forwarder) {
        forwarder = _forwarder;
        string memory name = "MinimalForwarder";
        string memory version = "0.0.1";
        bytes32 hashedName = keccak256(bytes(name));
        bytes32 hashedVersion = keccak256(bytes(version));
        bytes32 typeHash = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
        bytes32 minimalForwarderTypeHash = keccak256(
            "ForwardRequest(address from,address to,uint256 value,uint256 gas,uint256 nonce,bytes data)"
        );

        _HASHED_NAME = hashedName;
        _HASHED_VERSION = hashedVersion;
        _CACHED_CHAIN_ID = block.chainid;
        _CACHED_DOMAIN_SEPARATOR =
            _buildDomainSeparator(typeHash, hashedName, hashedVersion);
        _CACHED_THIS = address(this);
        _TYPE_HASH = typeHash;
        _minimal_Forwarder_TYPE_HASH = minimalForwarderTypeHash;
    }

    function _buildDomainSeparator(
        bytes32 typeHash,
        bytes32 nameHash,
        bytes32 versionHash
    ) private view returns (bytes32) {
        return keccak256(
            abi.encode(
                typeHash, nameHash, versionHash, block.chainid, forwarder
            )
        );
    }

    struct ForwardRequest {
        address from;
        address to;
        uint value;
        uint gas;
        uint nonce;
        bytes data;
    }

    // computes the hash of a permit
    function getStructHash(ForwardRequest memory req)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                _minimal_Forwarder_TYPE_HASH,
                req.from,
                req.to,
                req.value,
                req.gas,
                req.nonce,
                keccak256(req.data)
            )
        );
    }

    function getTypedDataHash(ForwardRequest memory req)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(
                "\x19\x01", _CACHED_DOMAIN_SEPARATOR, getStructHash(req)
            )
        );
    }

    function getDigest(MinimalForwarder.ForwardRequest memory req)
        public
        view
        returns (bytes32)
    {
        return getTypedDataHash(toForwarderSignatureHelperForwardRequest(req));
    }

    function toForwarderSignatureHelperForwardRequest(
        MinimalForwarder.ForwardRequest memory req
    ) internal pure returns (ForwardRequest memory) {
        return ForwarderSignatureHelper.ForwardRequest(
            req.from, req.to, req.value, req.gas, req.nonce, req.data
        );
    }
}
