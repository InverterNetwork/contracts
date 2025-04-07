// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IEverclear {
    /**
     * @notice The structure of an intent
     * @param initiator The address of the intent initiator
     * @param receiver The address of the intent receiver
     * @param inputAsset The address of the intent asset on origin
     * @param outputAsset The address of the intent asset on destination
     * @param maxFee The maximum fee that can be taken by solvers
     * @param origin The origin chain of the intent
     * @param destinations The possible destination chains of the intent
     * @param nonce The nonce of the intent
     * @param timestamp The timestamp of the intent
     * @param ttl The time to live of the intent
     * @param amount The amount of the intent asset normalized to 18 decimals
     * @param data The data of the intent
     */
    struct Intent {
        bytes32 initiator;
        bytes32 receiver;
        bytes32 inputAsset;
        bytes32 outputAsset;
        uint24 maxFee;
        uint32 origin;
        uint64 nonce;
        uint48 timestamp;
        uint48 ttl;
        uint amount;
        uint32[] destinations;
        bytes data;
    }

    /**
     * @notice Creates a new intent
     * @param _destinations The possible destination chains of the intent
     * @param _receiver The destinantion address of the intent
     * @param _inputAsset The asset address on origin
     * @param _outputAsset The asset address on destination
     * @param _amount The amount of the asset
     * @param _maxFee The maximum fee that can be taken by solvers
     * @param _ttl The time to live of the intent
     * @param _data The data of the intent
     * @return _intentId The ID of the intent
     * @return _intent The intent object
     */
    function newIntent(
        uint32[] memory destinations,
        address to,
        address inputAsset,
        address outputAsset,
        uint amount,
        uint24 maxFee,
        uint48 ttl,
        bytes calldata data
    ) external returns (bytes32 _intentId, Intent memory _intent);
}
