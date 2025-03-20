pragma solidity ^0.8.0;

import {ModuleV1Mock} from "@mock/modules/base/ModuleV1Mock.sol";
import {IModuleImplementationMock} from
    "@mock/proxies/IModuleImplementationMock.sol";

contract ModuleImplementationV1Mock is
    ModuleV1Mock,
    IModuleImplementationMock
{
    uint public data;

    function initialize(uint _data) external initializer {
        data = _data;
    }

    function getMockVersion() external pure returns (uint) {
        return 1;
    }
}
