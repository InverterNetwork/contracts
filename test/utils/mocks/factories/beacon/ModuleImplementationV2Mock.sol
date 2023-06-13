pragma solidity ^0.8.0;

import "@oz/proxy/utils/Initializable.sol";

import {ModuleMock} from "test/utils/mocks/modules/base/ModuleMock.sol";

contract ModuleImplementationV2Mock is ModuleMock {
    uint public data;

    function initialize(uint data_) external initializer {
        data = data_;
    }

    function getVersion() external pure returns (uint) {
        return 2;
    }
}
