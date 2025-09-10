// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// External Imports
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IEverclear} from "@pp/interfaces/IEverclear.sol";

contract EverclearPaymentMock {
    event IntentAdded(
        bytes32 intentId, uint queuePosition, IEverclear.Intent intent
    );

    uint public nonce;
    uint32 public DOMAIN;
    IntentStatus public nextIntentStatus;
    mapping(bytes32 => IntentStatus) public status;
    bool public mockBridgeToFail;

    enum IntentStatus {
        NONE,
        ADDED,
        SETTLED,
        FAILED,
        SETTLED_AND_MANUALLY_EXECUTED
    }

    function newIntent(
        uint32[] memory _destinations,
        address _to,
        address _inputAsset,
        address _outputAsset,
        uint _amount,
        uint24 _maxFee,
        uint48 _ttl,
        bytes calldata _data
    ) external returns (bytes32 _intentId, IEverclear.Intent memory _intent) {
        // Increment nonce for each new intent
        nonce++;

        // if maxFee is 333, intentional fail
        if (_maxFee == 333) {
            return (bytes32(0), _intent);
        }

        _intent = IEverclear.Intent({
            initiator: bytes32(uint(uint160(msg.sender))), // convert address to bytes32
            receiver: bytes32(uint(uint160(_to))),
            inputAsset: bytes32(uint(uint160(_inputAsset))),
            outputAsset: bytes32(uint(uint160(_outputAsset))),
            amount: _amount,
            maxFee: _maxFee,
            origin: DOMAIN,
            destinations: _destinations,
            nonce: uint64(nonce), // convert uint to uint64
            timestamp: uint48(block.timestamp),
            ttl: _ttl,
            data: _data
        });

        if (mockBridgeToFail == false) {
            // Generate a unique intent ID
            _intentId = keccak256(abi.encode(_intent));

            IERC20(_inputAsset).transferFrom(msg.sender, address(this), _amount);

            // Set intent status to ADDED and emit the event
            status[_intentId] = IntentStatus.ADDED;
            emit IntentAdded(_intentId, nonce, _intent);
        } else {
            _intentId = bytes32(0);
            status[_intentId] = IntentStatus.FAILED;
        }
        return (_intentId, _intent);
    }

    function setNextIntentStatus(IntentStatus _status) external {
        nextIntentStatus = _status;
    }

    function setMockBridgeToFail(bool _fail) external {
        mockBridgeToFail = _fail;
    }
}
