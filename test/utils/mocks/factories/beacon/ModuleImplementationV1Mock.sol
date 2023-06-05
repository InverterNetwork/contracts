pragma solidity 0.8.19;

import {ModuleMock} from "test/utils/mocks/modules/base/ModuleMock.sol";

contract ModuleImplementationV1Mock is ModuleMock {
    uint public data;

    function initialize(uint _data) external initializer {
        data = _data;
    }

    function getVersion() external pure returns (uint) {
        return 1;
    }
}
