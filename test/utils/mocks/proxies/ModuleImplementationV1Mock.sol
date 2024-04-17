pragma solidity ^0.8.0;

import {ModuleMock} from "test/utils/mocks/modules/base/ModuleMock.sol";
import {IModuleImplementationMock} from
    "test/utils/mocks/proxies/IModuleImplementationMock.sol";

contract ModuleImplementationV1Mock is ModuleMock, IModuleImplementationMock {
    uint public data;

    function initialize(uint _data) external initializer {
        data = _data;
    }

    function getMockVersion() external pure returns (uint) {
        return 1;
    }
}
