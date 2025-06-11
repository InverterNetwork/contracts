pragma solidity ^0.8.0;

import "@oz/proxy/utils/Initializable.sol";

import {Module_v2_Mock} from "@mocks/modules/base/Module_v2_Mock.sol";
import {IModuleImplementationMock} from
    "@mocks/proxies/IModuleImplementationMock.sol";

contract ModuleImplementationV2Mock is
    Module_v2_Mock,
    IModuleImplementationMock
{
    uint public data;

    function initialize(uint data_) external initializer {
        data = data_;
    }

    function getMockVersion() external pure returns (uint) {
        return 2;
    }
}
