// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// External Dependencies
import {ERC2771Forwarder} from "@oz/metatx/ERC2771Forwarder.sol";
import {Nonces} from "@oz/utils/Nonces.sol";

contract ForwarderSignatureHelper is Nonces, Test {
    address private immutable forwarder;
    bytes32 private immutable _CACHED_DOMAIN_SEPARATOR;
    uint private immutable _CACHED_CHAIN_ID;

    bytes32 private immutable _HASHED_NAME;
    bytes32 private immutable _HASHED_VERSION;
    bytes32 private immutable _TYPE_HASH;
    bytes32 private immutable _FORWARD_REQUEST_TYPEHASH;

    //Domain Seperator
    constructor(address _forwarder) {
        forwarder = _forwarder;
        string memory name = "ERC2771Forwarder";
        string memory version = "1";
        bytes32 hashedName = keccak256(bytes(name));
        bytes32 hashedVersion = keccak256(bytes(version));
        bytes32 typeHash = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
        bytes32 forwardRequestTypehash = keccak256(
            "ForwardRequest(address from,address to,uint256 value,uint256 gas,uint256 nonce,uint48 deadline,bytes data)"
        );

        _HASHED_NAME = hashedName;
        _HASHED_VERSION = hashedVersion;
        _CACHED_CHAIN_ID = block.chainid;
        _CACHED_DOMAIN_SEPARATOR =
            _buildDomainSeparator(typeHash, hashedName, hashedVersion);
        _TYPE_HASH = typeHash;
        _FORWARD_REQUEST_TYPEHASH = forwardRequestTypehash;
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

    struct HelperForwardRequest {
        address from;
        address to;
        uint value;
        uint gas;
        uint48 deadline;
        bytes data;
    }

    // computes the hash of a permit
    function getStructHash(HelperForwardRequest memory req)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                _FORWARD_REQUEST_TYPEHASH,
                req.from,
                req.to,
                req.value,
                req.gas,
                nonces(req.from),
                req.deadline,
                keccak256(req.data)
            )
        );
    }

    //Copied from Openzeppelins MessageHashUtils
    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash)
        internal
        pure
        returns (bytes32 digest)
    {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, hex"1901")
            mstore(add(ptr, 0x02), domainSeparator)
            mstore(add(ptr, 0x22), structHash)
            digest := keccak256(ptr, 0x42)
        }
    }

    function getForwardRequestData(
        HelperForwardRequest memory req,
        address signer,
        uint signerPrivateKey
    ) public returns (ERC2771Forwarder.ForwardRequestData memory) {
        //Get digest for signature creation
        bytes32 digest =
            toTypedDataHash(_CACHED_DOMAIN_SEPARATOR, getStructHash(req));

        //Create Signature
        vm.prank(signer);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        //Make sure the nonce is counted up correctly
        _useNonce(signer);

        return ERC2771Forwarder.ForwardRequestData(
            req.from,
            req.to,
            req.value,
            req.gas,
            req.deadline,
            req.data,
            signature
        );
    }
}
