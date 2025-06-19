pragma solidity ^0.8.0;

import {Module_v2_Mock} from "@mocks/modules/base/Module_v2_Mock.sol";
import {IModuleImplementationMock} from
    "@mocks/proxies/IModuleImplementationMock.sol";

contract ModuleImplementationV1Mock is
    Module_v2_Mock,
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
